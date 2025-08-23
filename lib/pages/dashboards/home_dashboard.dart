// home_dashboard.dart
import 'dart:math';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/service/org_resolver.dart';
import 'package:excelaratorapi/service/user_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({super.key});
  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<HomeDashboardPage> {
  String? _orgId;
  bool _busy = false;

  // Stats window (you can swap to 7 or 90 if you like)
  final DateTime _since = DateTime.now().subtract(const Duration(days: 30));

  // KPIs
  double _successRate = 0.0; // 0..1
  int _conversions = 0; // succeeded jobs
  double _generatedMb = 0.0; // sum of artifact sizes from succeeded jobs

  @override
  void initState() {
    super.initState();
    _resolveOrg();
  }

  Future<void> _resolveOrg() async {
    final orgId = await OrgResolver.resolveForCurrentUser(
      createIfNone: false, // important: don't auto-create here
    );
    if (!mounted) return;
    setState(() => _orgId = orgId);

    // Only ensure admin flags if we truly are the owner of THAT org
    if (orgId != null) {
      await _ensureAdminIfOwner(orgId);
      await _loadStats();
    }
  }

  Future<void> _ensureAdminIfOwner(String orgId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final fs = FirebaseFirestore.instance;
    final orgRef = fs.collection('orgs').doc(orgId);
    final memberRef = orgRef.collection('members').doc(user.uid);
    final userRef = fs.collection('users').doc(user.uid);

    // --- Detect ownership via org doc or membership roles ---
    final orgSnap = await orgRef.get();
    final orgData = orgSnap.data() ?? <String, dynamic>{};
    final ownerUid =
        (orgData['ownerUid'] ?? orgData['ownerId'] ?? orgData['createdBy'])
            as String?;
    final isOwnerByOrgDoc = ownerUid == user.uid;

    final memberSnap = await memberRef.get();
    final m = memberSnap.data() ?? {};

    final role =
        (m['role'] ?? m['userRole'] ?? m['type'] ?? '')
            .toString()
            .toLowerCase();
    final roles =
        (m['roles'] is List)
            ? (List.from(
              m['roles'],
            ).map((e) => e.toString().toLowerCase()).toList())
            : <String>[];
    final isOwnerByMembership = role == 'owner' || roles.contains('owner');

    final isOwner = isOwnerByOrgDoc || isOwnerByMembership;
    if (!isOwner) return;

    // Already admin in membership?
    final isAlreadyAdmin =
        (m['admin'] == true) || role == 'admin' || roles.contains('admin');
    if (isAlreadyAdmin && memberSnap.exists) {
      // Still ensure /users has admin=true
      final uSnap = await userRef.get();
      final u = uSnap.data() ?? <String, dynamic>{};
      if (u['admin'] == true &&
          (u['adminOrgs'] is List &&
              (u['adminOrgs'] as List).contains(orgId))) {
        return;
      }
    }

    // --- Build batched writes: membership + users/{uid} ---
    final batch = fs.batch();

    // Upsert/merge membership
    final memberPayload = <String, dynamic>{
      'admin': true,
      'roles': FieldValue.arrayUnion(['admin']),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!memberSnap.exists && isOwnerByOrgDoc) {
      memberPayload['role'] = 'owner';
      memberPayload['joinedAt'] = FieldValue.serverTimestamp();
      memberPayload['uid'] = user.uid;
      if (user.email != null) memberPayload['email'] = user.email;
    }
    batch.set(memberRef, memberPayload, SetOptions(merge: true));

    // Upsert/merge users/{uid}: admin flag + track orgs where admin
    final userPayload = <String, dynamic>{
      'admin': true,
      'adminOrgs': FieldValue.arrayUnion([orgId]),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Optionally keep a primary org if missing (safe merge)
    if ((await userRef.get()).data()?['orgId'] == null) {
      userPayload['orgId'] = orgId;
    }
    // Preserve email if helpful
    if (user.email != null) userPayload['email'] = user.email;

    batch.set(userRef, userPayload, SetOptions(merge: true));

    try {
      await batch.commit();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not set admin flags: $e')));
    }
  }

  // ---------- Stats loader (robust, single fetch, no composite index required) ----------
  Future<void> _loadStats() async {
    if (_orgId == null) return;
    setState(() => _busy = true);

    try {
      final col = FirebaseFirestore.instance
          .collection('orgs')
          .doc(_orgId)
          .collection('jobs');

      final startTs = Timestamp.fromDate(_since);

      // Pull up to 1000 recent jobs within window; do all math client-side
      final snap =
          await col
              .where('createdAt', isGreaterThanOrEqualTo: startTs)
              .orderBy('createdAt', descending: true)
              .limit(1000)
              .get();

      final docs = snap.docs;
      final total = docs.length;

      // Filter successes (normalize status)
      bool isSuccess(Map<String, dynamic> m) {
        final s = (m['status'] ?? '').toString().toLowerCase();
        return s == 'success' || s == 'succeeded';
      }

      final succDocs = docs.where((d) => isSuccess(d.data())).toList();
      final succ = succDocs.length;

      // Sum artifact bytes on successes
      int totalBytes = 0;
      for (final d in succDocs) {
        final m = d.data();

        // singular: artifact: { size | sizeBytes | bytes, storagePath | path | gsPath, ... }
        final single = m['artifact'];
        if (single is Map) {
          final b = (single['size'] ?? single['sizeBytes'] ?? single['bytes']);
          if (b is num) totalBytes += b.toInt();
        }

        // plural: artifacts: [ { size | sizeBytes | bytes, ... } ]
        final list = m['artifacts'];
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              final b = (e['sizeBytes'] ?? e['size'] ?? e['bytes']);
              if (b is num) totalBytes += b.toInt();
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _conversions = succ;
        _successRate = (total == 0) ? 0.0 : succ / total;
        _generatedMb = (totalBytes / (1024 * 1024)).ceil() as double;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load stats: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Download helpers ----------
  Future<void> _openArtifactFromJob(Map<String, dynamic> job) async {
    // Prefer direct URL if present
    String? url;
    String? path;

    // singular
    final single = job['artifact'];
    if (single is Map) {
      url =
          (single['downloadUrl'] ?? single['publicUrl'] ?? single['url'])
              as String?;
      path =
          (single['storagePath'] ?? single['path'] ?? single['gsPath'])
              as String?;
    }

    // fallback plural
    if (url == null && path == null) {
      final list = job['artifacts'];
      if (list is List && list.isNotEmpty && list.first is Map) {
        final m = (list.first as Map).cast<String, dynamic>();
        url = (m['downloadUrl'] ?? m['publicUrl'] ?? m['url']) as String?;
        path = (m['storagePath'] ?? m['path'] ?? m['gsPath']) as String?;
      }
    }

    if (url != null) {
      await _openUrl(url);
    } else if (path != null) {
      await _openFromStorage(path);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No artifact available')));
    }
  }

  Future<void> _openUrl(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
    }
  }

  Future<void> _openFromStorage(String pathOrUrl) async {
    try {
      final ref =
          pathOrUrl.startsWith('gs://') || pathOrUrl.startsWith('http')
              ? storage.FirebaseStorage.instance.refFromURL(pathOrUrl)
              : storage.FirebaseStorage.instance.ref(pathOrUrl);
      final url = await ref.getDownloadURL();
      await _openUrl(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Open failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _loadStats,
            icon:
                _busy
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body:
          _orgId == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: () async => _loadStats(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ================= KPI Row =================
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _KpiCard(
                            title: 'Success rate',
                            valueBig:
                                '${(_successRate * 100).clamp(0, 100).toStringAsFixed(0)}%',
                            helper: 'Last 30 days',
                            icon: Icons.check_circle_outline,
                            fg: Colors.green.shade700,
                          ),
                          _KpiCard(
                            title: 'Conversions',
                            valueBig: _conversions.toString(),
                            helper: 'Succeeded last 30 days',
                            icon: Icons.auto_awesome_motion_outlined,
                            fg: cs.primary,
                          ),
                          _KpiCard(
                            title: 'Generated MB',
                            valueBig: _generatedMb.toStringAsFixed(
                              _generatedMb >= 10 ? 0 : 1,
                            ),
                            helper: 'Artifacts last 30 days',
                            icon: Icons.archive_outlined,
                            fg: Colors.blueGrey.shade700,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ================= Recent Jobs =================
                      _RecentJobsCard(
                        orgId: _orgId!,
                        onOpen: (id) => context.go('/jobs/$id'),
                        onDownload: (m) => _openArtifactFromJob(m),
                      ),
                      const SizedBox(height: 16),

                      // ================= Getting Started =================
                      _GettingStarted(
                        onNewConversion: () => context.go('/convert'),
                        onJobs: () => context.go('/jobs'),
                        onPlan: () => context.go('/account/plan'),
                        onTemplates: () => context.go('/templates'),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}

// =============== Widgets ===============

class _KpiCard extends StatelessWidget {
  final String title;
  final String valueBig;
  final String helper;
  final IconData icon;
  final Color fg;

  const _KpiCard({
    required this.title,
    required this.valueBig,
    required this.helper,
    required this.icon,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260),
      child: SizedBox(
        width: min(MediaQuery.of(context).size.width, 460),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: fg.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: fg.withOpacity(0.28)),
                  ),
                  child: Icon(icon, color: fg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        valueBig,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        helper,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentJobsCard extends StatelessWidget {
  final String orgId;
  final void Function(String jobId) onOpen;
  final void Function(Map<String, dynamic> jobMap) onDownload;

  const _RecentJobsCard({
    required this.orgId,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = FirebaseFirestore.instance
        .collection('orgs')
        .doc(orgId)
        .collection('jobs')
        .orderBy('createdAt', descending: true)
        .limit(10);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Recent jobs',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.go('/jobs'),
                  icon: const Icon(Icons.list_alt_outlined, size: 18),
                  label: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: col.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: LinearProgressIndicator(minHeight: 3),
                  );
                }
                if (snap.hasError) {
                  return Text('Error loading jobs: ${snap.error}');
                }
                final docs = snap.data?.docs ?? const [];

                if (docs.isEmpty) {
                  return Text(
                    'No recent jobs.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  );
                }

                bool hasArtifact(Map<String, dynamic> m) {
                  if (m['artifact'] is Map) return true;
                  if (m['artifacts'] is List &&
                      (m['artifacts'] as List).isNotEmpty) {
                    return true;
                  }
                  return false;
                }

                String fmt(DateTime dt) {
                  String two(int x) => x.toString().padLeft(2, '0');
                  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
                }

                int listSize = 5;
                if (docs.length < 5) {
                  listSize = docs.length;
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: listSize,
                  separatorBuilder:
                      (_, __) => Divider(
                        height: 1,
                        color: cs.outline.withOpacity(0.20),
                      ),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final m = d.data();
                    final status =
                        (m['status'] as String? ?? 'pending').toLowerCase();
                    final name = (m['name'] as String?) ?? d.id;
                    final createdAt = (m['createdAt'] as Timestamp?)?.toDate();
                    final progress = (m['progress'] as num?)?.toDouble() ?? 0.0;

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          d.id,
                          if (createdAt != null) fmt(createdAt),
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: _StatusDot(status: status, progress: progress),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => onOpen(d.id),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open'),
                          ),
                          if (hasArtifact(m))
                            OutlinedButton.icon(
                              onPressed: () => onDownload(m),
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 18,
                              ),
                              label: const Text('Download'),
                            ),
                        ],
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
}

class _StatusDot extends StatelessWidget {
  final String status;
  final double progress;
  const _StatusDot({required this.status, required this.progress});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (status) {
      case 'running':
        color = Theme.of(context).colorScheme.primary;
        icon = Icons.autorenew;
        break;
      case 'success':
      case 'succeeded':
        color = Colors.green.shade700;
        icon = Icons.check_circle;
        break;
      case 'failed':
      case 'error':
        color = Theme.of(context).colorScheme.error;
        icon = Icons.error;
        break;
      case 'canceled':
      case 'cancelled':
        color = Theme.of(context).colorScheme.outline;
        icon = Icons.cancel;
        break;
      default:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        icon = Icons.schedule;
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        CircleAvatar(radius: 14, backgroundColor: color.withOpacity(0.12)),
        Icon(icon, color: color, size: 18),
      ],
    );
  }
}

class _GettingStarted extends StatelessWidget {
  final VoidCallback onNewConversion;
  final VoidCallback onJobs;
  final VoidCallback onPlan;
  final VoidCallback onTemplates;

  const _GettingStarted({
    required this.onNewConversion,
    required this.onJobs,
    required this.onPlan,
    required this.onTemplates,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final user = UserManager.currentUser;

    final isAdmin = (user?.isAdmin == true) || (user?.admin == true);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Getting started',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              runSpacing: 10,
              spacing: 10,
              children: [
                _StartTile(
                  icon: Icons.auto_awesome_motion_outlined,
                  title: 'New conversion',
                  subtitle:
                      'Upload Excel → generate code / DB / ETL / analytics',
                  onTap: onNewConversion,
                ),
                _StartTile(
                  icon: Icons.history_outlined,
                  title: 'See jobs',
                  subtitle:
                      'Monitor progress, download artifacts, retry failures',
                  onTap: onJobs,
                ),
                if (isAdmin)
                  _StartTile(
                    icon: Icons.credit_card_outlined,
                    title: 'Choose a plan',
                    subtitle: 'Unlock higher limits for bigger workbooks',
                    onTap: onPlan,
                  ),
                _StartTile(
                  icon: Icons.file_download_outlined,
                  title: 'Sample templates',
                  subtitle: 'Try example workbooks that follow best practices',
                  onTap: onTemplates,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: cs.outline.withOpacity(0.25)),
            const SizedBox(height: 12),
            Text('Tips', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _tip('One sheet = one entity. First row are headers.'),
            _tip('Prefer normalized tabs over a single wide sheet.'),
            _tip('Include 3–10 sample rows for better type inference.'),
            _tip('Use consistent date/number formats across sheets.'),
          ],
        ),
      ),
    );
  }

  Widget _tip(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        const Icon(Icons.lightbulb_outline, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(t)),
      ],
    ),
  );
}

class _StartTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _StartTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 300,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.surface,
            border: Border.all(color: cs.outline.withOpacity(0.24)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
