import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum BillingConfirmationKind { success, changed, cancelled }

class BillingConfirmationPage extends StatefulWidget {
  final BillingConfirmationKind kind;
  const BillingConfirmationPage({super.key, required this.kind});

  static BillingConfirmationPage fromPath(String path) {
    final last = Uri.parse(path).pathSegments.last.toLowerCase();
    switch (last) {
      case 'success':
        return const BillingConfirmationPage(
          kind: BillingConfirmationKind.success,
        );
      case 'changed':
        return const BillingConfirmationPage(
          kind: BillingConfirmationKind.changed,
        );
      case 'cancelled':
        return const BillingConfirmationPage(
          kind: BillingConfirmationKind.cancelled,
        );
      default:
        return const BillingConfirmationPage(
          kind: BillingConfirmationKind.success,
        );
    }
  }

  @override
  State<BillingConfirmationPage> createState() =>
      _BillingConfirmationPageState();
}

class _BillingConfirmationPageState extends State<BillingConfirmationPage> {
  String? _orgId;
  DocumentReference<Map<String, dynamic>>? _pubRef;
  DocumentReference<Map<String, dynamic>>? _selRef;

  StreamSubscription? _subPub;
  StreamSubscription? _subSel;

  Map<String, dynamic>? _pub;
  Map<String, dynamic>? _sel;

  bool _appliedOnce = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _subPub?.cancel();
    _subSel?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orgId = await _resolveOrgId();
      _orgId = orgId;
      _pubRef = FirebaseFirestore.instance.doc('orgs/$orgId/billing/public');
      _selRef = FirebaseFirestore.instance.doc('orgs/$orgId/billing/selection');

      _subPub = _pubRef!.snapshots().listen((snap) {
        _pub = snap.data();
        _maybeApplyAndFinish();
      });

      _subSel = _selRef!.snapshots().listen((snap) {
        _sel = snap.data();
        _maybeApplyAndFinish();
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
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
    final fromDoc = (uDoc.data()?['orgId'] as String?);
    if (fromDoc != null && fromDoc.isNotEmpty) return fromDoc;

    throw Exception('orgId not found.');
  }

  void _maybeApplyAndFinish() async {
    if (!mounted) return;

    final pub = _pub ?? {};
    final sel = _sel ?? {};
    final kind = widget.kind;

    final status = (pub['status'] as String?) ?? '';
    final planId = (pub['planId'] as String?) ?? 'free';
    final cycle = (pub['cycle'] as String?) ?? 'monthly';
    final subId = (pub['stripeSubscriptionId'] as String?) ?? '';
    final cancelAtPeriodEnd = (pub['cancelAtPeriodEnd'] as bool?) ?? false;

    bool satisfied = false;

    if (kind == BillingConfirmationKind.success) {
      satisfied =
          subId.isNotEmpty && (status == 'active' || status == 'trialing');
    } else if (kind == BillingConfirmationKind.changed) {
      final selPlan = (sel['planId'] as String?) ?? '';
      final selCycle = (sel['cycle'] as String?) ?? '';
      satisfied =
          selPlan.isNotEmpty &&
          selCycle.isNotEmpty &&
          selPlan == planId &&
          selCycle == cycle &&
          (status == 'active' || status == 'trialing' || status == 'past_due');
    } else if (kind == BillingConfirmationKind.cancelled) {
      satisfied = cancelAtPeriodEnd || status == 'canceled';
    }

    if (satisfied) {
      if (!_appliedOnce &&
          (kind == BillingConfirmationKind.success ||
              kind == BillingConfirmationKind.changed) &&
          _selRef != null) {
        _appliedOnce = true;
        await _selRef!.set({
          'status': 'applied',
          'confirmedAt': FieldValue.serverTimestamp(),
          'lastApplied': {
            'planId': planId,
            'cycle': cycle,
            'at': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pub = _pub ?? {};
    final title = switch (widget.kind) {
      BillingConfirmationKind.success => 'Subscription confirmed',
      BillingConfirmationKind.changed => 'Plan updated',
      BillingConfirmationKind.cancelled => 'Cancellation scheduled',
    };

    final subtitle = switch (widget.kind) {
      BillingConfirmationKind.success =>
        'Thanks! Your subscription is active. You can manage it anytime.',
      BillingConfirmationKind.changed =>
        'Your plan change has been applied. Proration will be reflected by Stripe.',
      BillingConfirmationKind.cancelled =>
        'You’ll keep access until the end of the current period.',
    };

    final icon = switch (widget.kind) {
      BillingConfirmationKind.success => Icons.check_circle_rounded,
      BillingConfirmationKind.changed => Icons.swap_horiz_rounded,
      BillingConfirmationKind.cancelled => Icons.cancel_rounded,
    };

    final cs = Theme.of(context).colorScheme;
    final renewsAtTs = pub['renewsAt'];
    DateTime? renewsAt;
    if (renewsAtTs is Timestamp) renewsAt = renewsAtTs.toDate();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                _error != null
                    ? _ErrorBox(msg: _error!)
                    : _loading
                    ? const _LoadingBox()
                    : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 72, color: cs.primary),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 20),
                        _Summary(pub: pub, renewsAt: renewsAt),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => context.go('/account/plan'),
                          child: const Text('Back to Manage Plan'),
                        ),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final Map<String, dynamic> pub;
  final DateTime? renewsAt;
  const _Summary({required this.pub, required this.renewsAt});

  @override
  Widget build(BuildContext context) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final plan = (pub['planId'] as String?) ?? 'free';
    final cycle = (pub['cycle'] as String?) ?? 'monthly';
    final status = (pub['status'] as String?) ?? '—';
    final pmBrand = pub['pmBrand'] as String?;
    final pmLast4 = pub['pmLast4'] as String?;
    final cancelAtPeriodEnd = (pub['cancelAtPeriodEnd'] as bool?) ?? false;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Plan', '$plan (${cycle == 'yearly' ? 'yearly' : 'monthly'})'),
            const SizedBox(height: 6),
            _row('Status', status),
            const SizedBox(height: 6),
            _row(
              'Payment method',
              (pmBrand != null && pmLast4 != null)
                  ? '$pmBrand •••• $pmLast4'
                  : '—',
            ),
            const SizedBox(height: 6),
            _row(
              cancelAtPeriodEnd ? 'Ends on' : 'Renews on',
              renewsAt != null ? fmt(renewsAt!) : '—',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    const style = TextStyle(fontSize: 14);
    return Row(
      children: [
        SizedBox(width: 140, child: Text(k, style: style)),
        Expanded(child: Text(v, style: style)),
      ],
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: cs.primary),
        const SizedBox(height: 12),
        Text(
          'Waiting for Stripe confirmation…',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          'This can take a few seconds after checkout completes.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String msg;
  const _ErrorBox({required this.msg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, color: cs.error, size: 56),
        const SizedBox(height: 8),
        Text(
          'Something went wrong',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: cs.error),
        ),
        const SizedBox(height: 6),
        Text(msg, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.go('/account/plan'),
          child: const Text('Back to Manage Plan'),
        ),
      ],
    );
  }
}
