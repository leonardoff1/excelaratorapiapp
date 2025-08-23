// manage_plan_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/service/user_manager.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:firebase_storage/firebase_storage.dart' as gcs;

class ManagePlanPage extends StatefulWidget {
  const ManagePlanPage({super.key});

  @override
  State<ManagePlanPage> createState() => _ManagePlanPageState();
}

enum _Cycle { monthly, yearly }

class _ManagePlanPageState extends State<ManagePlanPage> {
  // ------- Firebase refs / org -------
  String? _orgId;
  DocumentReference<Map<String, dynamic>>? _pubRef;
  DocumentReference<Map<String, dynamic>>? _selRef;
  StreamSubscription? _subPub, _subSel;
  Timer? _saveDebounce;

  // ------- Current subscription state (billing/public) -------
  String _currentPlanId = 'free';
  String _status = 'active'; // active, trialing, past_due, canceled, ...
  final bool _active = false;
  bool _cancelAtPeriodEnd = false;
  String? _stripeSubscriptionId;

  DateTime? _renewsAt;
  String? _pmBrand;
  String? _pmLast4;

  // Usage demo (replace with real usage later)
  int _convUsed = 0, _convLimit = 3;
  int _seatsUsed = 1, _seatsIncluded = 1;
  int _storageUsedGb = 0, _storageLimitGb = 1;

  DateTime? _periodStart, _periodEnd;

  // ------- Purchase UI state (billing/selection) -------
  _Cycle _cycle = _Cycle.monthly;
  String _pendingPlanId = 'free'; // user selection

  // Add-ons (selection only; server can read them from selection on checkout)
  int _extraJobPacks = 0; // “extra conversions packs”
  int _extraSeats = 0;
  int _extraGBs = 0;

  bool _busy = false;

  // ------- Pricing model -------
  final Map<String, _Plan> _plans = {
    'free': _Plan(
      id: 'free',
      label: 'Free',
      monthly: 0,
      conversions: 3,
      minutes: 0,
      seats: 1,
      storageGb: 1,
      features: const [
        '3 conversions/mo',
        '10k rows/job cap',
        'Community support',
      ],
    ),
    'starter': _Plan(
      id: 'starter',
      label: 'Starter',
      monthly: 29,
      conversions: 10,
      minutes: 0,
      seats: 1,
      storageGb: 5,
      features: const [
        '10 conversions/mo',
        '50k rows/job cap',
        'Email support',
      ],
    ),
    'pro': _Plan(
      id: 'pro',
      label: 'Pro',
      monthly: 49,
      conversions: 100,
      minutes: 0,
      seats: 2,
      storageGb: 10,
      features: const [
        '100 conversions/mo',
        '1M rows/job cap',
        'Email support',
      ],
      highlight: true,
    ),
    'team': _Plan(
      id: 'team',
      label: 'Team',
      monthly: 149,
      conversions: 500,
      minutes: 4000,
      seats: 5,
      storageGb: 20,
      features: const [
        '500 conversions/mo',
        '1M rows/job cap',
        'Unlimited Seats',
      ],
    ),
  };

  // Add-on pricing (display only)
  static const int _extraJobPacksPrice = 10; // per pack
  static const double _extraSeatPrice = 8; // per seat / mo
  static const double _extraGBsPrice = 9; // per GB / mo

  // ------- Helpers -------
  double _priceFor(String planId, _Cycle cycle) {
    final p = _plans[planId]!;
    final monthly = p.monthly.toDouble();
    return cycle == _Cycle.monthly ? monthly : monthly * 10; // ~2 mo free
  }

  double _addonsCost(_Cycle cycle) {
    double base = 0;
    base += _extraJobPacks * _extraJobPacksPrice;
    base += _extraSeats * _extraSeatPrice;
    base += _extraGBs * _extraGBsPrice;
    return cycle == _Cycle.monthly ? base : base * 10;
  }

  /// Frontend base for success/cancel URLs.
  String _appBase() {
    if (kIsWeb) {
      final origin = Uri.base.origin; // e.g. https://app.yourhost.com
      final usesHash =
          Uri.base.hasFragment || Uri.base.toString().contains('/#/');
      return usesHash ? '$origin/#' : origin;
    }
    // If mobile/desktop, point to your web frontend host:
    return 'https://app.yourhost.com';
  }

  String _appUrl(String path) => '${_appBase()}$path';

  // ===================== FIREBASE WIRING =====================
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _subPub?.cancel();
    _subSel?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadUsageForCurrentPeriod() async {
    if (_orgId == null) return;

    final fs = FirebaseFirestore.instance;

    final DateTime now = DateTime.now();
    final DateTime start = _periodStart ?? DateTime(now.year, now.month, 1);
    final DateTime end =
        _periodEnd ?? _renewsAt ?? now.add(const Duration(days: 30));
    final startTs = Timestamp.fromDate(start);
    final endTs = Timestamp.fromDate(end);

    // ---------- Conversions used ----------
    int convUsed = 0;

    // Try the direct collection first: orgs/{orgId}/jobs
    final directJobs = fs.collection('orgs/$_orgId/jobs');

    // Helper to choose a timestamp field present on at least one doc
    Future<String?> pickTsField(
      CollectionReference<Map<String, dynamic>> coll,
    ) async {
      final snap = await coll.limit(1).get();
      if (snap.docs.isEmpty) return null;
      final m = snap.docs.first.data();
      for (final f in const ['completedAt', 'createdAt', 'startedAt']) {
        final v = m[f];
        if (v is Timestamp) return f;
      }
      return null;
    }

    Future<int> countWith(Query<Map<String, dynamic>> q) async {
      final agg = await q.count().get();
      return agg.count!;
    }

    try {
      String? tsField = await pickTsField(directJobs);
      bool usedDirect = false;

      if (tsField != null) {
        // First attempt on the direct collection
        Query<Map<String, dynamic>> q = directJobs
            .where(tsField, isGreaterThanOrEqualTo: startTs)
            .where(tsField, isLessThan: endTs);

        // Try with status filter first
        try {
          convUsed = await countWith(
            q.where('status', whereIn: ['succeeded', 'completed']),
          );
          usedDirect = true;
        } catch (_) {
          // If status doesn’t exist / fails, retry without it
          convUsed = await countWith(q);
          usedDirect = true;
        }
      }

      // If direct path had no docs or no timestamp field, try a collectionGroup fallback
      if (!usedDirect) {
        // collectionGroup fallback
        Query<Map<String, dynamic>> qGroup = fs
            .collectionGroup('jobs')
            .where('createdAt', isGreaterThanOrEqualTo: startTs)
            .where('createdAt', isLessThan: endTs);

        // Only add orgId filter if your jobs actually store it
        // If your jobs don’t store orgId, remove the next line.
        qGroup = qGroup.where('orgId', isEqualTo: _orgId);

        try {
          convUsed = await countWith(
            qGroup.where('status', whereIn: ['succeeded', 'completed']),
          );
        } catch (_) {
          convUsed = await countWith(qGroup);
        }
      }
    } catch (e) {
      // As a last resort, leave convUsed at 0
      // debugPrint('convUsed error: $e');
    }

    // ---------- Seats used ----------
    int seatsUsed = 1;

    Future<int> aggCount(Query<Map<String, dynamic>> q) async {
      try {
        final snap = await q.count().get();
        return snap.count!;
      } catch (_) {
        final docs = await q.limit(1000).get();
        return docs.size;
      }
    }

    Future<int> countSeatsForOrg(String orgId) async {
      // 1) orgs/{orgId}/members where active==true
      final mColl = fs.collection('orgs/$orgId/members');
      try {
        final active = await aggCount(mColl.where('active', isEqualTo: true));
        if (active > 0) return active;
        // 1b) if none marked active, fall back to all members
        final all = await aggCount(mColl);
        if (all > 0) return all;
      } catch (_) {}

      // 2) orgs/{orgId}/users (if you store people there)
      try {
        final usersColl = fs.collection('orgs/$orgId/users');
        // prefer not disabled
        final enabled = await aggCount(
          usersColl.where('disabled', isEqualTo: false),
        );
        if (enabled > 0) return enabled;
        final all = await aggCount(usersColl);
        if (all > 0) return all;
      } catch (_) {}

      // 3) collectionGroup('members') with orgId field
      try {
        final cg = fs
            .collectionGroup('members')
            .where('orgId', isEqualTo: orgId);
        final active = await aggCount(cg.where('active', isEqualTo: true));
        if (active > 0) return active;
        final all = await aggCount(cg);
        if (all > 0) return all;
      } catch (_) {}

      // default at least 1 seat (owner)
      return 1;
    }

    // ---------- Storage used (GB) ----------
    // --- Storage ---
    // --- Storage used (GB) from Firebase Storage under /orgs/{orgId} ---

    // Recursively sum sizes (bytes) of all objects under a folder.
    // Uses paginated listing to scale beyond 1,000 objects.
    Future<int> sumFolder(gcs.Reference dir) async {
      int total = 0;
      String? pageToken;
      do {
        final res = await dir.list(
          gcs.ListOptions(maxResults: 1000, pageToken: pageToken),
        );
        // files in this directory
        for (final item in res.items) {
          try {
            final meta = await item.getMetadata();
            total += meta.size ?? 0; // bytes
          } catch (_) {
            // ignore files we can't read metadata for (rules or transient errors)
          }
        }
        // recurse into subfolders
        for (final sub in res.prefixes) {
          total += await sumFolder(sub);
        }
        pageToken = res.nextPageToken;
      } while (pageToken != null);
      return total;
    }

    Future<int> storageBytesForOrg(String orgId) async {
      final root = gcs.FirebaseStorage.instance.ref('orgs/$orgId');
      return await sumFolder(root);
    }

    seatsUsed = await countSeatsForOrg(_orgId!);
    int storageBytes = await storageBytesForOrg(_orgId!);

    if (!mounted) return;
    setState(() {
      _convUsed = convUsed;
      _seatsUsed = seatsUsed;
      _storageUsedGb = (storageBytes / (1024 * 1024 * 1024)).ceil();
      print('storage size: $_storageUsedGb');
    });
  }

  Future<void> _bootstrap() async {
    setState(() => _busy = true);
    try {
      final orgId = await _resolveOrgId();
      _orgId = orgId;

      _pubRef = FirebaseFirestore.instance.doc('orgs/$orgId/billing/public');
      _selRef = FirebaseFirestore.instance.doc('orgs/$orgId/billing/selection');

      // Authoritative subscription snapshot
      _subPub = _pubRef!.snapshots().listen((snap) {
        final m = snap.data();
        if (m == null) return;

        setState(() {
          _currentPlanId = (m['planId'] as String?) ?? 'free';
          _cycle =
              ((m['cycle'] as String?) == 'yearly')
                  ? _Cycle.yearly
                  : _Cycle.monthly;

          _convLimit =
              (m['conversionsLimit'] ?? _plans[_currentPlanId]!.conversions)
                  as int;
          _seatsIncluded =
              (m['seatsIncluded'] ?? _plans[_currentPlanId]!.seats) as int;
          _storageLimitGb =
              (m['storageLimitGb'] ?? _plans[_currentPlanId]!.storageGb) as int;

          _renewsAt = (m['renewsAt'] as Timestamp?)?.toDate();
          _periodStart = (m['periodStart'] as Timestamp?)?.toDate();
          _periodEnd = (m['periodEnd'] as Timestamp?)?.toDate() ?? _renewsAt;
          _cancelAtPeriodEnd = (m['cancelAtPeriodEnd'] as bool?) ?? false;

          _status = (m['status'] as String?) ?? 'Unknown';

          _stripeSubscriptionId = m['stripeSubscriptionId'] as String?;
          _pmBrand = m['pmBrand'] as String?;
          _pmLast4 = m['pmLast4'] as String?;
        });

        _loadUsageForCurrentPeriod(); // <— compute the "used" part
      });

      // Client-owned selection (remember UI choices)
      _subSel = _selRef!.snapshots().listen((snap) {
        final s = snap.data();
        if (s == null) return;

        setState(() {
          _pendingPlanId = (s['planId'] ?? _pendingPlanId) as String;
          final cyc = (s['cycle'] ?? 'monthly') as String;
          _cycle = cyc == 'yearly' ? _Cycle.yearly : _Cycle.monthly;

          final addons = (s['addons'] ?? {}) as Map;
          _extraSeats = (addons['extraSeats'] ?? _extraSeats) as int;
          _extraJobPacks = (addons['extraJobPacks'] ?? _extraJobPacks) as int;
          _extraGBs = (addons['extraGBs'] ?? _extraGBs) as int;
        });
      });

      // Seed selection if missing
      final sel = await _selRef!.get();
      if (!sel.exists) {
        await _saveSelection(status: 'saved', includeUiTotals: false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _resolveOrgId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in.');

    final token = await user.getIdTokenResult(true);
    final fromClaim = token.claims?['orgId'] as String?;
    if (fromClaim != null && fromClaim.isNotEmpty) return fromClaim;

    final uDoc =
        await FirebaseFirestore.instance.doc('users/${user.uid}').get();
    final fromDoc = uDoc.data()?['orgId'] as String?;
    if (fromDoc != null && fromDoc.isNotEmpty) return fromDoc;

    throw Exception(
      'orgId not found (neither in custom claim nor users/{uid}).',
    );
  }

  // Debounced autosave for selection document
  void _saveSelectionDebounced() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      _saveSelection(status: 'saved');
    });
  }

  Future<void> _saveSelection({
    String status = 'saved',
    bool includeUiTotals = false,
  }) async {
    if (_selRef == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final data = <String, dynamic>{
      'planId': _pendingPlanId,
      'cycle': _cycle == _Cycle.monthly ? 'monthly' : 'yearly',
      'addons': {
        'extraSeats': _extraSeats,
        'extraJobPacks': _extraJobPacks,
        'extraGBs': _extraGBs,
      },
      'status': status, // 'saved' | 'pending' | 'applied'
      'selectedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (includeUiTotals) {
      final amount = _priceFor(_pendingPlanId, _cycle) + _addonsCost(_cycle);
      data['uiTotals'] = {
        'amount': amount.round(),
        'currency': 'usd',
        'interval': _cycle == _Cycle.monthly ? 'month' : 'year',
      };
    }

    await _selRef!.set(data, SetOptions(merge: true));
  }

  // ===================== ACTIONS =====================

  /// Confirm button:
  /// - If there is **no** subscription yet → create Stripe Checkout (new sub)
  /// - If there **is** a subscription → update in place (prorated)
  Future<void> _changePlan() async {
    final user = UserManager.currentUser!;
    if (_orgId == null) return;

    setState(() => _busy = true);
    try {
      // Persist the latest selection immediately
      await _saveSelection(status: 'pending', includeUiTotals: true);

      final apiBase = user.userURL; // e.g. http(s)://localhost:5001

      if (_stripeSubscriptionId == null || _stripeSubscriptionId!.isEmpty) {
        // -------- First-time purchase → Stripe Checkout --------
        final body = {
          "orgId": _orgId,
          "planId": _pendingPlanId,
          "cycle": _cycle == _Cycle.monthly ? "monthly" : "yearly",
          "extraSeats": _extraSeats,
          "extraJobPacks": _extraJobPacks,
          "extraGBs": _extraGBs,
          "successUrl": _appUrl("/account/plan/success"),
          "cancelUrl": _appUrl("/account/plan"),
        };

        final r = await http.post(
          Uri.parse("$apiBase/api/billing/checkout"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        );

        if (r.statusCode != 200) throw Exception(r.body);
        final url = (jsonDecode(r.body) as Map)['url'] as String;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Redirecting to checkout…')),
        );

        final uri = Uri.parse(url);
        final ok = await launchUrl(
          uri,
          mode:
              kIsWeb
                  ? LaunchMode.platformDefault
                  : LaunchMode.externalApplication,
          webOnlyWindowName: '_self',
        );
        if (!ok) {
          if (kIsWeb) {
            final retry = await launchUrl(uri, webOnlyWindowName: '_blank');
            if (!retry) throw Exception('Could not launch checkout URL');
          } else {
            throw Exception('Could not launch checkout URL');
          }
        }
      } else {
        // -------- Subscription exists → change plan in-place (proration in backend) --------
        final body = {
          "orgId": _orgId,
          "planId": _pendingPlanId,
          "cycle": _cycle == _Cycle.monthly ? "monthly" : "yearly",
          "extraSeats": _extraSeats,
          "extraJobPacks": _extraJobPacks,
          "extraGBs": _extraGBs,
        };

        final r = await http.post(
          Uri.parse("$apiBase/api/billing/change-plan"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(body),
        );
        if (r.statusCode != 200) throw Exception(r.body);

        // Optional: mark selection as applied locally (webhook will still do the authoritative update)
        await _saveSelection(status: 'applied');

        if (!mounted) return;

        // Go straight to your confirmation page for “changed” flows.
        // Your existing route is /account/plan/success — pass a mode so the page can render the right message.
        final plan = _pendingPlanId;
        final cyc = _cycle == _Cycle.monthly ? 'monthly' : 'yearly';
        context.go('/account/plan/success?mode=changed&plan=$plan&cycle=$cyc');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Change plan failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updatePaymentMethod() async {
    final user = UserManager.currentUser!;
    if (_orgId == null) return;

    try {
      final r = await http.post(
        Uri.parse("${user.userURL}/api/billing/portal"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"orgId": _orgId, "returnUrl": _appUrl("/account")}),
      );
      if (r.statusCode != 200) throw Exception(r.body);
      final url = (jsonDecode(r.body) as Map)['url'] as String;

      final ok = await launchUrl(
        Uri.parse(url),
        mode:
            kIsWeb
                ? LaunchMode.platformDefault
                : LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
      if (!ok) throw Exception('Could not open billing portal');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Portal error: $e')));
    }
  }

  Future<void> _cancelPlan() async {
    if (_orgId == null || _busy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Cancel subscription?'),
            content: const Text(
              'You’ll keep access until the end of the current billing period.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep plan'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Cancel at period end'),
              ),
            ],
          ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final user = UserManager.currentUser!;
      final res = await http.post(
        Uri.parse("${user.userURL}/api/billing/cancel"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"orgId": _orgId}),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body.isNotEmpty ? res.body : 'Cancel failed');
      }

      // jump straight to the confirmation page (it will watch Firestore)
      if (!mounted) return;
      context.go('/account/plan/cancelled');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resumePlan() async {
    if (_orgId == null) return;
    setState(() => _busy = true);
    try {
      final user = UserManager.currentUser!;
      final r = await http.post(
        Uri.parse("${user.userURL}/api/billing/resume"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"orgId": _orgId}),
      );
      if (r.statusCode != 200) throw Exception(r.body);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Subscription resumed.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Resume failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ===================== BUILD =====================
  @override
  Widget build(BuildContext context) {
    final current = _plans[_currentPlanId] ?? _plans['free']!;
    final cs = Theme.of(context).colorScheme;
    final user = UserManager.currentUser!;

    return MainLayout(
      userModel: UserModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage plan'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/home');
              }
            },
          ),
        ),
        body:
            _orgId == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final twoCol = c.maxWidth >= 1100;

                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ===== Left column: Overview & Usage =====
                              Expanded(
                                flex: 3,
                                child: ListView(
                                  children: [
                                    _PlanSummaryCard(
                                      plan: current,
                                      renewsAt: _renewsAt,
                                      pmBrand: _pmBrand,
                                      pmLast4: _pmLast4,
                                      status: _status,
                                      cancelAtPeriodEnd: _cancelAtPeriodEnd,
                                      onUpdatePm: _updatePaymentMethod,
                                      cycle: _cycle.name,
                                    ),
                                    const SizedBox(height: 12),
                                    _UsageCard(
                                      convUsed: _convUsed,
                                      convLimit: _convLimit,
                                      seatsUsed: _seatsUsed,
                                      seatsLimit: _seatsIncluded,
                                      storageUsedGb: _storageUsedGb,
                                      storageLimitGb: _storageLimitGb,
                                      periodStart: _periodStart,
                                      periodEnd: _periodEnd,
                                      renewsAt: _renewsAt,
                                      cycle:
                                          _cycle == _Cycle.yearly
                                              ? 'yearly'
                                              : 'monthly',
                                      cancelAtPeriodEnd: _cancelAtPeriodEnd,
                                    ),
                                    const SizedBox(height: 12),
                                    if (!twoCol)
                                      _ChangePlanCard(
                                        plans: _plans,
                                        cycle: _cycle,
                                        currentPlanId: _currentPlanId,
                                        pendingPlanId: _pendingPlanId,
                                        onCycle: (v) {
                                          setState(() => _cycle = v);
                                          _saveSelectionDebounced();
                                        },
                                        onSelectPlan: (id) {
                                          setState(() => _pendingPlanId = id);
                                          _saveSelectionDebounced();
                                        },
                                      ),
                                    if (!twoCol) const SizedBox(height: 12),
                                    if (!twoCol) const SizedBox(height: 12),
                                    _InvoicesCard(
                                      orgId: _orgId,
                                      apiBase: user.userURL!,
                                    ),
                                    const SizedBox(height: 12),
                                    _DangerZone(
                                      cancelAtPeriodEnd: _cancelAtPeriodEnd,
                                      onCancel: _cancelPlan,
                                      onResume: _resumePlan,
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              ),

                              if (twoCol) const SizedBox(width: 16),

                              // ===== Right column: Change plan & Add-ons =====
                              if (twoCol)
                                Expanded(
                                  flex: 2,
                                  child: ListView(
                                    children: [
                                      _ChangePlanCard(
                                        plans: _plans,
                                        cycle: _cycle,
                                        currentPlanId: _currentPlanId,
                                        pendingPlanId: _pendingPlanId,
                                        onCycle: (v) {
                                          setState(() => _cycle = v);
                                          _saveSelectionDebounced();
                                        },
                                        onSelectPlan: (id) {
                                          setState(() => _pendingPlanId = id);
                                          _saveSelectionDebounced();
                                        },
                                      ),
                                      const SizedBox(height: 12),

                                      const SizedBox(height: 100),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Sticky footer: totals + confirm
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(
                                context,
                              ).dividerColor.withOpacity(0.2),
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            Builder(
                              builder: (context) {
                                final planPrice = _priceFor(
                                  _pendingPlanId,
                                  _cycle,
                                );
                                final addons = _addonsCost(_cycle);
                                final total = planPrice + addons;
                                return Row(
                                  children: [
                                    Chip(
                                      label: Text(
                                        _cycle == _Cycle.monthly
                                            ? 'Monthly'
                                            : 'Yearly (2 mo free)',
                                      ),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _cycle == _Cycle.monthly
                                          ? '\$${total.toStringAsFixed(0)}/mo'
                                          : '\$${total.toStringAsFixed(0)}/yr',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (_pendingPlanId != _currentPlanId)
                                      Text(
                                        '(${_plans[_pendingPlanId]!.label})',
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _busy ? null : _changePlan,
                              icon:
                                  _busy
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.check),
                              label: const Text('Confirm changes'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_busy)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: true,
                          child: Container(
                            color: Colors.black.withOpacity(0.03),
                          ),
                        ),
                      ),
                  ],
                ),
      ),
    );
  }
}

// ===== Models =====
class _Plan {
  final String id;
  final String label;
  final int monthly; // USD per month
  final int conversions; // conversions per month
  final int minutes; // build minutes per month
  final int seats; // included seats
  final int storageGb;
  final List<String> features;
  final bool highlight;
  const _Plan({
    required this.id,
    required this.label,
    required this.monthly,
    required this.conversions,
    required this.minutes,
    required this.seats,
    required this.storageGb,
    required this.features,
    this.highlight = false,
  });
}

// ===== Widgets =====

class _PlanSummaryCard extends StatelessWidget {
  final _Plan plan;
  final String cycle; // "monthly" | "yearly"
  final String?
  status; // Stripe status: active, trialing, past_due, canceled, ...
  final bool cancelAtPeriodEnd;
  final DateTime? renewsAt; // Stripe current_period_end (renew or end)
  final String? pmBrand;
  final String? pmLast4;

  final VoidCallback onUpdatePm;
  final VoidCallback? onCancel; // show when active & not cancelAtPeriodEnd
  final VoidCallback? onResume; // show when cancelAtPeriodEnd

  const _PlanSummaryCard({
    required this.plan,
    required this.cycle,
    required this.status,
    required this.cancelAtPeriodEnd,
    required this.renewsAt,
    required this.pmBrand,
    required this.pmLast4,
    required this.onUpdatePm,
    this.onCancel,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final s = (status ?? '').toLowerCase();
    final isActiveish = s == 'active' || s == 'trialing' || s == 'past_due';
    final isCanceled = s == 'canceled';
    final showResume = cancelAtPeriodEnd && onResume != null;
    final showCancel = !cancelAtPeriodEnd && !isCanceled && onCancel != null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: title + status chip
            Row(
              children: [
                Text(
                  'Current plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _statusChip(context, s),
              ],
            ),
            const SizedBox(height: 10),

            // Plan + cycle pills
            Row(
              children: [
                _pill(
                  text: plan.label,
                  fg: cs.secondary,
                  bg: cs.secondary.withOpacity(0.12),
                  border: cs.secondary.withOpacity(0.35),
                ),
                const SizedBox(width: 8),
                _pill(
                  text: cycle == 'yearly' ? 'Yearly' : 'Monthly',
                  fg: cs.primary,
                  bg: cs.primary.withOpacity(0.12),
                  border: cs.primary.withOpacity(0.35),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Renew/Ends + payment method
            Builder(
              builder: (_) {
                final label = cancelAtPeriodEnd ? 'Ends on' : 'Renews on';
                final value = renewsAt != null ? fmt(renewsAt!) : '—';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv(context, label, value, warn: cancelAtPeriodEnd),
                  ],
                );
              },
            ),

            const SizedBox(height: 4),

            // Actions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (showResume)
                  TextButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.undo),
                    label: const Text('Resume'),
                  ),
                if (showCancel && isActiveish)
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_schedule_send_rounded),
                    label: const Text('Cancel at period end'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- tiny helpers ---

  Widget _pill({
    required String text,
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {bool warn = false}) {
    final cs = Theme.of(context).colorScheme;
    final color = warn ? cs.error : cs.onSurfaceVariant;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(k, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(color: warn ? cs.error : cs.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(BuildContext context, String s) {
    final cs = Theme.of(context).colorScheme;
    String label = '—';
    Color fg = cs.onSurfaceVariant;
    Color bg = cs.surfaceContainerHighest;

    switch (s) {
      case 'active':
        label = 'Active';
        fg = Colors.green.shade700;
        bg = Colors.green.withOpacity(0.12);
        break;
      case 'trialing':
        label = 'Trialing';
        fg = Colors.blue.shade700;
        bg = Colors.blue.withOpacity(0.12);
        break;
      case 'past_due':
        label = 'Past due';
        fg = Colors.orange.shade800;
        bg = Colors.orange.withOpacity(0.14);
        break;
      case 'incomplete':
      case 'incomplete_expired':
        label = 'Incomplete';
        fg = Colors.orange.shade800;
        bg = Colors.orange.withOpacity(0.14);
        break;
      case 'canceled':
        label = 'Canceled';
        fg = cs.error;
        bg = cs.error.withOpacity(0.12);
        break;
      default:
        label = s.isEmpty ? 'Unknown' : s;
        fg = cs.onSurfaceVariant;
        bg = cs.surfaceContainerHighest;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final int convUsed, convLimit;
  final int seatsUsed, seatsLimit;
  final int storageUsedGb, storageLimitGb;

  // NEW (optional) — pass these if you have them from billing/public
  final DateTime? periodStart; // e.g., current_period_start
  final DateTime? periodEnd; // e.g., current_period_end
  final DateTime? renewsAt; // if you only have renewsAt (same as periodEnd)
  final String? cycle; // 'monthly' | 'yearly'
  final bool cancelAtPeriodEnd; // show "Ends on" instead of "Renews on"

  const _UsageCard({
    required this.convUsed,
    required this.convLimit,
    required this.seatsUsed,
    required this.seatsLimit,
    required this.storageUsedGb,
    required this.storageLimitGb,
    this.periodStart,
    this.periodEnd,
    this.renewsAt,
    this.cycle,
    this.cancelAtPeriodEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final DateTime? start = periodStart;
    final DateTime? end = periodEnd ?? renewsAt;
    final String cycleLabel = (cycle == 'yearly') ? 'Yearly' : 'Monthly';

    // Time progress for the billing period (if we know the window)
    double? timePct;
    int? daysLeft;
    int? daysTotal;
    if (start != null && end != null && end.isAfter(start)) {
      final now = DateTime.now();
      final total = end.difference(start).inSeconds;
      final elapsed = now.difference(start).inSeconds.clamp(0, total);
      timePct = total == 0 ? null : (elapsed / total).clamp(0, 1).toDouble();
      daysLeft = end.difference(now).inDays.clamp(0, 10000);
      daysTotal = end.difference(start).inDays.abs();
    }

    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header + period info
            Row(
              children: [
                Text(
                  'Usage this period',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.secondary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    cycleLabel,
                    style: TextStyle(
                      color: cs.secondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                if (end != null)
                  Text(
                    cancelAtPeriodEnd
                        ? 'Ends on ${fmt(end)}'
                        : 'Renews on ${fmt(end)}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            if (start != null && end != null) ...[
              const SizedBox(height: 8),
              _periodBar(context, start, end, timePct, daysLeft, daysTotal),
            ],

            const SizedBox(height: 12),
            _meter(
              context,
              'Conversions',
              convUsed,
              convLimit,
              icon: Icons.auto_awesome_mosaic_outlined,
            ),
            const SizedBox(height: 8),
            _meter(
              context,
              'Seats',
              seatsUsed,
              seatsLimit,
              icon: Icons.people_outline,
            ),
            const SizedBox(height: 8),
            _meter(
              context,
              'Storage (GB)',
              storageUsedGb,
              storageLimitGb,
              icon: Icons.cloud_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodBar(
    BuildContext context,
    DateTime start,
    DateTime end,
    double? pct,
    int? daysLeft,
    int? daysTotal,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (pct ?? 0).clamp(0, 1),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${_d(start)} → ${_d(end)}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            if (daysLeft != null && daysTotal != null)
              Text(
                '$daysLeft of $daysTotal days left',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _meter(
    BuildContext context,
    String label,
    int used,
    int limit, {
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bool hasLimit = limit > 0;
    final double pct = hasLimit ? (used / limit).clamp(0, 1).toDouble() : 0.0;
    final String rightText =
        hasLimit
            ? '$used / $limit (${_pctStr(used, limit)})'
            : '$used • Unlimited';

    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: cs.primary),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  _PercentChip(
                    pct: hasLimit ? used / limit : null,
                    text: rightText,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: hasLimit ? pct : null, // indeterminate if unlimited
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _pctStr(int used, int limit) {
    if (limit <= 0) return '—';
    final pct = (used / limit) * 100;
    return '${pct.toStringAsFixed(0)}%';
  }
}

class _PercentChip extends StatelessWidget {
  final double? pct; // null -> unlimited
  final String text;
  const _PercentChip({required this.pct, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ChangePlanCard extends StatelessWidget {
  final Map<String, _Plan> plans;
  final _Cycle cycle;
  final String currentPlanId;
  final String pendingPlanId;
  final ValueChanged<_Cycle> onCycle;
  final ValueChanged<String> onSelectPlan;

  const _ChangePlanCard({
    required this.plans,
    required this.cycle,
    required this.currentPlanId,
    required this.pendingPlanId,
    required this.onCycle,
    required this.onSelectPlan,
  });

  double _price(_Plan p, _Cycle c) =>
      c == _Cycle.monthly ? p.monthly.toDouble() : p.monthly * 10.0;

  @override
  Widget build(BuildContext context) {
    final list =
        [
          'free',
          'starter',
          'pro',
          'team',
        ].where(plans.containsKey).map((id) => plans[id]!).toList();
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Change plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                SegmentedButton<_Cycle>(
                  segments: const [
                    ButtonSegment(
                      value: _Cycle.monthly,
                      label: Text('Monthly'),
                    ),
                    ButtonSegment(value: _Cycle.yearly, label: Text('Yearly')),
                  ],
                  selected: {cycle},
                  onSelectionChanged: (s) => onCycle(s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final cols =
                    c.maxWidth > 1100
                        ? 4
                        : c.maxWidth > 820
                        ? 2
                        : 1;
                // Pick a compact, readable height so 2–3 rows fit vertically
                final double tileH = switch (cols) {
                  1 => 280.0, // single-column (narrow)
                  2 => 280.0, // medium
                  _ => 280.0, // wide (3–4 columns)
                };
                return GridView.builder(
                  shrinkWrap: true,
                  physics: PageScrollPhysics(),
                  itemCount: list.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisExtent: tileH,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.88,
                  ),
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final price = _price(p, cycle);
                    final isCurrent = p.id == currentPlanId;
                    final isPending = p.id == pendingPlanId;
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              isPending
                                  ? cs.primary
                                  : cs.outline.withOpacity(0.24),
                          width: isPending ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  p.label,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                if (p.highlight)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.secondary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Recommended',
                                      style: TextStyle(
                                        color: cs.secondary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (p.monthly == 0)
                              Text(
                                '\$0',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              )
                            else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${price.toStringAsFixed(0)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    cycle == _Cycle.monthly ? '/mo' : '/yr',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            _kv('Conversions', '${p.conversions}/mo'),
                            _kv('Seats', '${p.seats} included'),
                            _kv('Storage', '${p.storageGb} GB'),
                            const SizedBox(height: 8),
                            ...p.features.map(
                              (f) => Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('•  '),
                                  Expanded(child: Text(f)),
                                ],
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed:
                                    isCurrent ? null : () => onSelectPlan(p.id),
                                child: Text(
                                  isCurrent
                                      ? 'Current plan'
                                      : (isPending ? 'Selected' : 'Select'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    const style = TextStyle(fontSize: 13);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(k, style: style)),
          Expanded(child: Text(v, style: style)),
        ],
      ),
    );
  }
}

class _AddonsCard extends StatelessWidget {
  final int extraJobPacks;
  final ValueChanged<int> onChangeJobPacks;
  final int extraSeats;
  final ValueChanged<int> onChangeSeats;
  final int extraGBs;
  final ValueChanged<int> onChangeextraGBs;

  const _AddonsCard({
    required this.extraJobPacks,
    required this.onChangeJobPacks,
    required this.extraSeats,
    required this.onChangeSeats,
    required this.extraGBs,
    required this.onChangeextraGBs,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add-ons',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _addonRow(
              context,
              title: 'Extra Conversions',
              subtitle: 'Pack of 3 conversions',
              trailing: _Stepper(
                value: extraJobPacks,
                onChanged: onChangeJobPacks,
                min: 0,
                max: 20,
              ),
              price: '\$10 / pack',
            ),
            const Divider(),
            _addonRow(
              context,
              title: 'Additional seats',
              subtitle: 'Invite more teammates',
              trailing: _Stepper(
                value: extraSeats,
                onChanged: onChangeSeats,
                min: 0,
                max: 50,
              ),
              price: '\$8 / seat',
            ),
            const Divider(),
            _addonRow(
              context,
              title: 'Extra GB',
              subtitle: 'More Storage',
              trailing: _Stepper(
                value: extraGBs,
                onChanged: onChangeextraGBs,
                min: 0,
                max: 50,
              ),
              price: '\$9 / mo',
            ),
            const SizedBox(height: 6),
            Text(
              'Add-ons are billed with your subscription. You can remove them anytime.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addonRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget trailing,
    required String price,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Text(price, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

/// Model we render in the list
class _InvoiceRowData {
  final String id;
  final String? number;
  final String status; // draft, open, paid, uncollectible, void
  final bool paid;
  final int amountPaid; // cents
  final int amountDue; // cents
  final String currency;
  final DateTime created;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String? hostedInvoiceUrl;
  final String? invoicePdf;

  _InvoiceRowData({
    required this.id,
    required this.number,
    required this.status,
    required this.paid,
    required this.amountPaid,
    required this.amountDue,
    required this.currency,
    required this.created,
    required this.periodStart,
    required this.periodEnd,
    required this.hostedInvoiceUrl,
    required this.invoicePdf,
  });

  factory _InvoiceRowData.fromJson(Map<String, dynamic> m) {
    DateTime? ts(int? s) =>
        (s == null)
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
              s * 1000,
              isUtc: true,
            ).toLocal();
    return _InvoiceRowData(
      id: m['id'] as String,
      number: m['number'] as String?,
      status: (m['status'] as String?) ?? 'open',
      paid: (m['paid'] as bool?) ?? false,
      amountPaid: (m['amountPaid'] as num?)?.toInt() ?? 0,
      amountDue: (m['amountDue'] as num?)?.toInt() ?? 0,
      currency: (m['currency'] as String?)?.toUpperCase() ?? 'USD',
      created: ts(m['created']) ?? DateTime.now(),
      periodStart: ts(m['periodStart']),
      periodEnd: ts(m['periodEnd']),
      hostedInvoiceUrl: m['hostedInvoiceUrl'] as String?,
      invoicePdf: m['invoicePdf'] as String?,
    );
  }

  String get displayAmount {
    // Prefer paid amount; fall back to due
    final cents = paid ? amountPaid : amountDue;
    final dollars = cents / 100.0;
    return '\$${dollars.toStringAsFixed(2)} $currency';
  }

  String get displayDate {
    final d = created;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

class _InvoicesCard extends StatefulWidget {
  final String?
  orgId; // allow null initially; we’ll start fetching when it becomes non-null
  final String apiBase; // e.g., http://localhost:5001 or your prod domain

  const _InvoicesCard({required this.orgId, required this.apiBase});

  @override
  State<_InvoicesCard> createState() => _InvoicesCardState();
}

class _InvoicesCardState extends State<_InvoicesCard> {
  Future<List<_InvoiceRow>>? _future;

  @override
  void initState() {
    super.initState();
    _maybeKickoffInitialLoad();
  }

  @override
  void didUpdateWidget(covariant _InvoicesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If orgId changes from null → non-null (or to a different org), start loading.
    if (oldWidget.orgId != widget.orgId) {
      _maybeKickoffInitialLoad();
    }
  }

  void _maybeKickoffInitialLoad() {
    if (widget.orgId == null || widget.orgId!.isEmpty) return;
    final fut = _load(); // start the async work
    setState(() {
      _future = fut;
    }); // synchronously store the Future (no Future returned)
  }

  Future<List<_InvoiceRow>> _load() async {
    final orgId = widget.orgId!;
    final uri = Uri.parse(
      '${widget.apiBase}/api/billing/invoices?orgId=${Uri.encodeComponent(orgId)}',
    );

    final res = await http.get(uri, headers: {'Accept': 'application/json'});
    if (res.statusCode != 200) {
      throw Exception(
        res.body.isNotEmpty ? res.body : 'Failed to load invoices',
      );
    }

    final raw = jsonDecode(res.body);
    if (raw is! List) return const [];

    return raw
        .map<_InvoiceRow>(
          (e) => _InvoiceRow.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  void _refresh() {
    if (widget.orgId == null || widget.orgId!.isEmpty) return;
    final fut = _load();
    setState(() {
      _future = fut;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Invoices',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (widget.orgId == null || widget.orgId!.isEmpty)
              _InfoBox(
                icon: Icons.info_outline,
                text: 'Preparing your account…',
              )
            else
              FutureBuilder<List<_InvoiceRow>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const _LoadingList();
                  }
                  if (snap.hasError) {
                    return _ErrorBoxSmall(
                      msg: '${snap.error}',
                      onRetry: _refresh,
                    );
                  }
                  final invoices = snap.data ?? const <_InvoiceRow>[];
                  if (invoices.isEmpty) {
                    return _InfoBox(
                      icon: Icons.receipt_long_outlined,
                      text: 'No invoices yet.',
                    );
                  }

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outline.withOpacity(0.24)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: invoices.length,
                      separatorBuilder:
                          (_, __) => Divider(
                            height: 1,
                            color: cs.outline.withOpacity(0.24),
                          ),
                      itemBuilder: (_, i) {
                        final row = invoices[i];
                        return ListTile(
                          dense: true,
                          title: Text(row.dateString),
                          subtitle: Text('Invoice ${row.id}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.secondary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  row.statusLabel,
                                  style: TextStyle(
                                    color: cs.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(row.amountFormatted),
                              IconButton(
                                tooltip: 'View invoice',
                                icon: const Icon(Icons.open_in_new),
                                onPressed: () async {
                                  final url =
                                      row.hostedInvoiceUrl ?? row.invoicePdf;
                                  if (url == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Invoice URL unavailable',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final ok = await launchUrl(
                                    Uri.parse(url),
                                    mode:
                                        kIsWeb
                                            ? LaunchMode.platformDefault
                                            : LaunchMode.externalApplication,
                                  );
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Could not open invoice'),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceRow {
  final String id;
  final DateTime created;
  final int amountPaid; // in cents
  final String currency; // e.g. "usd"
  final String status; // e.g. "paid", "open", "void", "uncollectible"
  final String? hostedInvoiceUrl;
  final String? invoicePdf;

  _InvoiceRow({
    required this.id,
    required this.created,
    required this.amountPaid,
    required this.currency,
    required this.status,
    required this.hostedInvoiceUrl,
    required this.invoicePdf,
  });

  factory _InvoiceRow.fromJson(Map<String, dynamic> m) {
    DateTime created;
    final c = m['created'];
    if (c is int) {
      created =
          DateTime.fromMillisecondsSinceEpoch(c * 1000, isUtc: true).toLocal();
    } else if (c is String) {
      created = DateTime.tryParse(c)?.toLocal() ?? DateTime.now();
    } else {
      created = DateTime.now();
    }

    return _InvoiceRow(
      id: (m['id'] as String?) ?? '—',
      created: created,
      amountPaid: (m['amountPaid'] as num?)?.toInt() ?? 0,
      currency: ((m['currency'] as String?) ?? 'usd').toLowerCase(),
      status: (m['status'] as String?) ?? 'open',
      hostedInvoiceUrl: m['hostedInvoiceUrl'] as String?,
      invoicePdf: m['invoicePdf'] as String?,
    );
  }

  String get dateString {
    final y = created.year.toString().padLeft(4, '0');
    final mo = created.month.toString().padLeft(2, '0');
    final d = created.day.toString().padLeft(2, '0');
    return '$y-$mo-$d';
    // Optional: also show time if you want.
  }

  String get statusLabel {
    switch (status) {
      case 'paid':
        return 'Paid';
      case 'open':
        return 'Open';
      case 'void':
        return 'Voided';
      case 'uncollectible':
        return 'Uncollectible';
      default:
        return status;
    }
  }

  String get amountFormatted {
    // Stripe amounts are in the smallest currency unit (cents for USD)
    final major = amountPaid / 100.0;
    return '\$${major.toStringAsFixed(2)}';
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline.withOpacity(0.24)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBoxSmall extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _ErrorBoxSmall({required this.msg, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.error.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  final bool cancelAtPeriodEnd;
  final VoidCallback onCancel;
  final VoidCallback onResume;
  const _DangerZone({
    required this.cancelAtPeriodEnd,
    required this.onCancel,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color:
          cancelAtPeriodEnd
              ? Colors.orange.withOpacity(0.07)
              : cs.error.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              cancelAtPeriodEnd ? Icons.restore : Icons.warning_amber_rounded,
              color: cancelAtPeriodEnd ? Colors.orange : cs.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cancelAtPeriodEnd
                    ? 'Your subscription is set to cancel at the end of the current period.'
                    : 'Cancel subscription — Access remains until the end of the paid period.',
                style: TextStyle(color: cs.onSurface),
              ),
            ),
            if (cancelAtPeriodEnd)
              TextButton(onPressed: onResume, child: const Text('Resume'))
            else
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: const Text('Cancel plan'),
              ),
          ],
        ),
      ),
    );
  }
}

// ===== Tiny helpers =====

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.value,
    this.min = 0,
    this.max = 100,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabledMinus = value > min;
    final enabledPlus = value < max;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: enabledMinus ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: enabledPlus ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
