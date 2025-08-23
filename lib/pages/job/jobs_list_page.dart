// jobs_list_page.dart
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/service/org_resolver.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class JobsListPage extends StatefulWidget {
  const JobsListPage({super.key});

  @override
  State<JobsListPage> createState() => _JobsListPageState();
}

// ---------- Models ----------

class _Job {
  final String id;
  final String name;
  final String type; // Spreadsheet | Database
  final DateTime createdAt;
  final String status; // Pending | Running | Success | Failed | Canceled
  final int? durationSecs; // null while running
  final String? resultUrl; // direct http(s) URL if present
  final String? artifactPath; // storagePath or gs:// URL fallback
  final double progress; // 0..1

  _Job({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.status,
    required this.durationSecs,
    required this.resultUrl,
    required this.artifactPath,
    required this.progress,
  });
}

class _ArtifactRef {
  final String? url; // direct http(s) link if present
  final String? path; // Firebase Storage path or gs:// URL
  const _ArtifactRef({this.url, this.path});
}

// ---------- Page ----------

class _JobsListPageState extends State<JobsListPage> {
  final Set<String> _selected = {};
  String _query = '';
  String _status = 'All';
  String _range = 'Last 7 days';
  bool _busy = false;

  // REPLACE the getter with a real field:
  String? _orgId;
  bool _loadingOrg = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // resolve orgId WITHOUT auto-creating a personal org for members
    final resolved = await OrgResolver.resolveForCurrentUser(
      createIfNone: false,
    );
    if (!mounted) return;
    setState(() {
      _orgId = resolved;
      _loadingOrg = false;
    });
  }

  Query<Map<String, dynamic>>? _baseQuery() {
    final orgId = _orgId;
    if (orgId == null) return null;
    return FirebaseFirestore.instance
        .collection('orgs')
        .doc(orgId)
        .collection('jobs')
        .orderBy('createdAt', descending: true);
  }
  // ---------- Artifact normalizer ----------

  _ArtifactRef _artifactRefFromJobMap(Map<String, dynamic> m) {
    // singular
    final single = m['artifact'];
    if (single is Map) {
      final sm = single.cast<String, dynamic>();
      final url =
          (sm['downloadUrl'] ?? sm['publicUrl'] ?? sm['url']) as String?;
      final path = (sm['storagePath'] ?? sm['path'] ?? sm['gsPath']) as String?;
      if (url != null || path != null) {
        return _ArtifactRef(url: url, path: path);
      }
    }
    // list
    final list = m['artifacts'];
    if (list is List && list.isNotEmpty && list.first is Map) {
      final fm = (list.first as Map).cast<String, dynamic>();
      final url =
          (fm['downloadUrl'] ?? fm['publicUrl'] ?? fm['url']) as String?;
      final path = (fm['storagePath'] ?? fm['path'] ?? fm['gsPath']) as String?;
      if (url != null || path != null) {
        return _ArtifactRef(url: url, path: path);
      }
    }
    return const _ArtifactRef();
  }

  // ---------- Model mapping ----------

  _Job _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final createdTs = d['createdAt'];
    final startedTs = d['startedAt'];
    final finishedTs = d['finishedAt'];

    DateTime toDate(dynamic ts) {
      if (ts is Timestamp) return ts.toDate();
      if (ts is DateTime) return ts;
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final createdAt = toDate(createdTs);
    final startedAt = startedTs == null ? null : toDate(startedTs);
    final finishedAt = finishedTs == null ? null : toDate(finishedTs);

    int? durationSecs;
    if (startedAt != null && finishedAt != null) {
      durationSecs = finishedAt
          .difference(startedAt)
          .inSeconds
          .clamp(0, 24 * 3600);
    } else if (d['durationSecs'] is num) {
      durationSecs = (d['durationSecs'] as num).toInt();
    }

    String mapType(String raw) {
      raw = (raw).toString().toLowerCase();
      if (raw.contains('spreadsheet')) return 'Spreadsheet';
      if (raw.contains('reverse') ||
          raw.contains('db') ||
          raw.contains('database') ||
          raw.contains('schema')) {
        return 'Database';
      }
      return 'Unknown';
    }

    String mapStatus(String raw) {
      switch ((raw).toString().toLowerCase()) {
        case 'pending':
          return 'Pending';
        case 'running':
          return 'Running';
        case 'success':
        case 'succeeded':
          return 'Success';
        case 'failed':
        case 'error':
          return 'Failed';
        case 'canceled':
        case 'cancelled':
          return 'Canceled';
        default:
          return 'Pending';
      }
    }

    final art = _artifactRefFromJobMap(d);

    return _Job(
      id: doc.id,
      name: (d['name'] ?? doc.id).toString(),
      type: mapType(d['type'] ?? ''),
      createdAt: createdAt,
      status: mapStatus((d['status'] ?? 'pending').toString()),
      durationSecs: durationSecs,
      resultUrl: art.url,
      artifactPath: art.path,
      progress:
          (d['progress'] is num)
              ? (d['progress'] as num).toDouble().clamp(0.0, 1.0)
              : 0.0,
    );
  }

  List<_Job> _applyFilters(List<_Job> all) {
    final q = _query.trim().toLowerCase();
    final until = DateTime.now();
    DateTime? since;
    switch (_range) {
      case 'Last 24 hours':
        since = until.subtract(const Duration(hours: 24));
        break;
      case 'Last 7 days':
        since = until.subtract(const Duration(days: 7));
        break;
      case 'Last 30 days':
        since = until.subtract(const Duration(days: 30));
        break;
      case 'All time':
        since = null;
        break;
    }
    return all.where((j) {
        final m1 =
            q.isEmpty ||
            j.name.toLowerCase().contains(q) ||
            j.id.toLowerCase().contains(q) ||
            j.type.toLowerCase().contains(q);
        final m2 = (_status == 'All') || j.status == _status;
        final m3 = since == null || j.createdAt.isAfter(since);
        return m1 && m2 && m3;
      }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // ---------- Actions ----------

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Refreshed')));
  }

  Future<void> _retry(_Job j) async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('jobs')
          .doc(j.id)
          .update({
            'status': 'pending',
            'progress': 0.0,
            'finishedAt': FieldValue.delete(),
            'artifacts': [],
            'error': FieldValue.delete(),
            'retryCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Re-queued ${j.id}')));
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Retry failed: ${e.message}')));
    }
  }

  Future<void> _cancel(_Job j) async {
    if (j.status != 'Pending' && j.status != 'Running') return;
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('jobs')
          .doc(j.id)
          .update({
            'status': 'canceled',
            'progress': 1.0,
            'finishedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel requested for ${j.id}')));
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel failed: ${e.message}')));
    }
  }

  Future<void> _bulkCancel(List<_Job> jobs) async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final j in jobs) {
        if (j.status == 'Pending' || j.status == 'Running') {
          final ref = FirebaseFirestore.instance
              .collection('orgs')
              .doc(orgId)
              .collection('jobs')
              .doc(j.id);
          batch.update(ref, {
            'status': 'canceled',
            'progress': 1.0,
            'finishedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cancel requested for selection')),
      );
      setState(() => _selected.clear());
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk cancel failed: ${e.message}')),
      );
    }
  }

  Future<void> _bulkRetry(List<_Job> jobs) async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final j in jobs) {
        if (j.status == 'Failed') {
          final ref = FirebaseFirestore.instance
              .collection('orgs')
              .doc(orgId)
              .collection('jobs')
              .doc(j.id);
          batch.update(ref, {
            'status': 'pending',
            'progress': 0.0,
            'finishedAt': FieldValue.delete(),
            'artifacts': [],
            'error': FieldValue.delete(),
            'retryCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Re-queued selected failed jobs')),
      );
      setState(() => _selected.clear());
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk retry failed: ${e.message}')),
      );
    }
  }

  void _openDetail(_Job j) => context.go('/jobs/${j.id}');

  Future<void> _download(_Job j) async {
    if (j.resultUrl != null && j.resultUrl!.isNotEmpty) {
      final ok = await launchUrl(
        Uri.parse(j.resultUrl!),
        mode:
            Theme.of(context).platform == TargetPlatform.android ||
                    Theme.of(context).platform == TargetPlatform.iOS
                ? LaunchMode.externalApplication
                : LaunchMode.platformDefault,
      );
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
      }
      return;
    }

    final path = j.artifactPath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No artifact available')));
      return;
    }

    try {
      if (path.startsWith('http')) {
        final ok = await launchUrl(
          Uri.parse(path),
          mode:
              Theme.of(context).platform == TargetPlatform.android ||
                      Theme.of(context).platform == TargetPlatform.iOS
                  ? LaunchMode.externalApplication
                  : LaunchMode.platformDefault,
        );
        if (!ok) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
        }
        return;
      }

      final ref =
          (path.startsWith('gs://') || path.startsWith('http'))
              ? storage.FirebaseStorage.instance.refFromURL(path)
              : storage.FirebaseStorage.instance.ref(path);
      final url = await ref.getDownloadURL();

      final ok = await launchUrl(
        Uri.parse(url),
        mode:
            Theme.of(context).platform == TargetPlatform.android ||
                    Theme.of(context).platform == TargetPlatform.iOS
                ? LaunchMode.externalApplication
                : LaunchMode.platformDefault,
      );
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open file')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final q = _baseQuery();
    if (q == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    if (_loadingOrg) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return MainLayout(
      userModel: UserModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Jobs'),
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
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : _refresh,
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
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: q.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error loading jobs: ${snap.error}'));
            }

            final all =
                snap.data?.docs.map(_fromDoc).toList() ?? const <_Job>[];
            final data = _applyFilters(all);

            return Column(
              children: [
                // Top filters / search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: min(
                              MediaQuery.of(context).size.width - 64,
                              460,
                            ),
                            child: TextField(
                              decoration: const InputDecoration(
                                isDense: true,
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Search by name, id, or type…',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                          DropdownButtonFormField<String>(
                            value: _status,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Status',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                const [
                                      'All',
                                      'Pending',
                                      'Running',
                                      'Success',
                                      'Failed',
                                      'Canceled',
                                    ]
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (v) => setState(() => _status = v ?? 'All'),
                          ),
                          DropdownButtonFormField<String>(
                            value: _range,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Range',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                const [
                                      'Last 24 hours',
                                      'Last 7 days',
                                      'Last 30 days',
                                      'All time',
                                    ]
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (v) =>
                                    setState(() => _range = v ?? 'Last 7 days'),
                          ),
                          const SizedBox(width: 8),
                          if (_selected.isNotEmpty)
                            _SelectionBar(
                              count: _selected.length,
                              onCancel: () {
                                final chosen =
                                    data
                                        .where((j) => _selected.contains(j.id))
                                        .toList();
                                _bulkCancel(chosen);
                              },
                              onRetry: () {
                                final chosen =
                                    data
                                        .where((j) => _selected.contains(j.id))
                                        .toList();
                                _bulkRetry(chosen);
                              },
                              onClear: () => setState(() => _selected.clear()),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Content
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final wide = c.maxWidth >= 980;

                      if (data.isEmpty) {
                        return _EmptyJobs(onRefresh: _refresh);
                      }

                      if (wide) {
                        // TABLE (desktop)
                        final cs = Theme.of(context).colorScheme;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 980,
                                  ),
                                  child: DataTable(
                                    showCheckboxColumn: false,
                                    headingRowHeight: 44,
                                    dataRowMinHeight: 54,
                                    dataRowMaxHeight: 64,
                                    headingRowColor: WidgetStatePropertyAll(
                                      cs.surfaceContainerHighest.withOpacity(
                                        0.4,
                                      ),
                                    ),
                                    columns: [
                                      DataColumn(
                                        label: Row(
                                          children: [
                                            Checkbox(
                                              value:
                                                  _selected.length ==
                                                      data.length &&
                                                  data.isNotEmpty,
                                              tristate:
                                                  data.isNotEmpty &&
                                                  _selected.isNotEmpty &&
                                                  _selected.length !=
                                                      data.length,
                                              onChanged: (v) {
                                                setState(() {
                                                  if (v == true) {
                                                    _selected.addAll(
                                                      data.map((e) => e.id),
                                                    );
                                                  } else {
                                                    _selected.clear();
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const DataColumn(label: Text('Job')),
                                      const DataColumn(label: Text('Type')),
                                      const DataColumn(label: Text('Status')),
                                      const DataColumn(label: Text('Actions')),
                                      const DataColumn(label: Text('Duration')),
                                      const DataColumn(label: Text('Created')),
                                    ],
                                    rows:
                                        data.map((j) {
                                          final sel = _selected.contains(j.id);
                                          return DataRow(
                                            selected: sel,
                                            onLongPress: () => _openDetail(j),
                                            onSelectChanged: (v) {
                                              setState(() {
                                                if (v == true) {
                                                  _selected.add(j.id);
                                                } else {
                                                  _selected.remove(j.id);
                                                }
                                              });
                                            },
                                            cells: [
                                              DataCell(
                                                Checkbox(
                                                  value: sel,
                                                  onChanged: (v) {
                                                    setState(() {
                                                      if (v == true) {
                                                        _selected.add(j.id);
                                                      } else {
                                                        _selected.remove(j.id);
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                              DataCell(
                                                _JobCellTitle(
                                                  id: j.id,
                                                  name: j.name,
                                                  onOpen: () => _openDetail(j),
                                                ),
                                              ),
                                              DataCell(_TypePill(j.type)),
                                              DataCell(
                                                _StatusChip(
                                                  status: j.status,
                                                  progress: j.progress,
                                                ),
                                              ),
                                              DataCell(
                                                _RowActions(
                                                  job: j,
                                                  onViewDetail: _openDetail,
                                                  onDownload: _download,
                                                  onRetry: _retry,
                                                  onCancel: _cancel,
                                                ),
                                              ),

                                              DataCell(
                                                Text(_dur(j.durationSecs)),
                                              ),
                                              DataCell(Text(_fmt(j.createdAt))),
                                            ],
                                          );
                                        }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      // CARDS (mobile/tablet)
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: data.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final j = data[i];
                          final sel = _selected.contains(j.id);
                          final cs = Theme.of(context).colorScheme;
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: sel,
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selected.add(j.id);
                                            } else {
                                              _selected.remove(j.id);
                                            }
                                          });
                                        },
                                      ),
                                      Expanded(
                                        child: _JobTitleInline(
                                          id: j.id,
                                          name: j.name,
                                          onOpen: () => _openDetail(j),
                                        ),
                                      ),
                                      _StatusChip(
                                        status: j.status,
                                        progress: j.progress,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      _TypePill(j.type),
                                      const Spacer(),
                                      Text(
                                        'Created: ${_fmt(j.createdAt)}',
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Duration: ${_dur(j.durationSecs)}'),
                                      _RowActions(
                                        job: j,
                                        onViewDetail: _openDetail,
                                        onDownload: _download,
                                        onRetry: _retry,
                                        onCancel: _cancel,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _dur(int? secs) {
    if (secs == null) return '—';
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m}m ${s}s';
  }
}

// ---------- Widgets ----------

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onClear;
  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onRetry,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$count selected',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry failed'),
          ),
          IconButton(
            onPressed: onClear,
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
          ),
        ],
      ),
    );
  }
}

class _JobCellTitle extends StatelessWidget {
  final String id;
  final String name;
  final VoidCallback? onOpen;
  const _JobCellTitle({required this.id, required this.name, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MouseRegion(cursor: SystemMouseCursors.click, child: text),
            const SizedBox(height: 2),
            Text(
              id,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// Mobile-friendly title with small chevron
class _JobTitleInline extends StatelessWidget {
  final String id;
  final String name;
  final VoidCallback? onOpen;
  const _JobTitleInline({required this.id, required this.name, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  id,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String type;
  const _TypePill(this.type);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = switch (type) {
      'Spreadsheet' => Icons.grid_on,
      'Database' => Icons.storage_rounded,
      _ => Icons.extension,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            type,
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final double progress;
  const _StatusChip({required this.status, required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color color;
    switch (status) {
      case 'Pending':
        color = cs.onSurfaceVariant;
        break;
      case 'Running':
        color = cs.primary;
        break;
      case 'Success':
        color = Colors.green.shade700;
        break;
      case 'Failed':
        color = cs.error;
        break;
      case 'Canceled':
        color = cs.outline;
        break;
      default:
        color = cs.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          if (status == 'Running') ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 70,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  final _Job job;
  final void Function(_Job) onViewDetail;
  final void Function(_Job) onDownload;
  final void Function(_Job) onRetry;
  final void Function(_Job) onCancel;

  const _RowActions({
    required this.job,
    required this.onViewDetail,
    required this.onDownload,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final hasArtifact =
        (job.resultUrl != null && job.resultUrl!.isNotEmpty) ||
        (job.artifactPath != null && job.artifactPath!.isNotEmpty);

    final canCancel = job.status == 'Pending' || job.status == 'Running';
    final canRetry = job.status == 'Failed';
    final canDownload = hasArtifact && job.status == 'Success';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Open Job',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_red_eye),
              onPressed: () => onViewDetail(job),
            ),
          ),
          if (canDownload)
            Tooltip(
              message: 'Download artifact',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.download_outlined),
                onPressed: () => onDownload(job),
              ),
            ),
          if (canRetry)
            Tooltip(
              message: 'Retry job',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh),
                onPressed: () => onRetry(job),
              ),
            ),
          if (canCancel)
            Tooltip(
              message: 'Cancel job',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                color: cs.error,
                onPressed: () => onCancel(job),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyJobs extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _EmptyJobs({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_outlined, size: 48, color: cs.primary),
              const SizedBox(height: 8),
              Text(
                'No jobs found',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Try a different filter or create a new conversion.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
