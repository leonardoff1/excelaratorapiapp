// jobs_detail_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class JobDetailPage extends StatefulWidget {
  final String jobId;
  const JobDetailPage({super.key, required this.jobId});
  @override
  State<JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<JobDetailPage> {
  String? _orgId;
  DocumentReference<Map<String, dynamic>>? _jobRef;

  @override
  void initState() {
    super.initState();
    _resolveOrg();
  }

  bool _busy = false;

  Future<void> _resolveOrg() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Try claim
    final token = await user.getIdTokenResult(true);
    final fromClaim = token.claims?['orgId'] as String?;
    if (fromClaim != null && fromClaim.isNotEmpty) {
      setState(() {
        _orgId = fromClaim;
        _jobRef = FirebaseFirestore.instance.doc(
          'orgs/$fromClaim/jobs/${widget.jobId}',
        );
      });
      return;
    }

    // Try users/{uid}.orgId
    final uDoc =
        await FirebaseFirestore.instance.doc('users/${user.uid}').get();
    final fromDoc = uDoc.data()?['orgId'] as String?;
    if (fromDoc != null && fromDoc.isNotEmpty) {
      setState(() {
        _orgId = fromDoc;
        _jobRef = FirebaseFirestore.instance.doc(
          'orgs/$fromDoc/jobs/${widget.jobId}',
        );
      });
      return;
    }

    // Fallback to personal-{uid} if that’s what you use elsewhere
    setState(() {
      _orgId = 'org-${user.uid}';
      _jobRef = FirebaseFirestore.instance.doc(
        'orgs/$_orgId/jobs/${widget.jobId}',
      );
    });
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Refreshed')));
  }

  // Opens a GCS object whether given gs:// URL, HTTPS URL, or storage path
  Future<void> _openObject({String? storagePath, String? directUrl}) async {
    try {
      if (directUrl != null && directUrl.isNotEmpty) {
        final ok = await launchUrl(
          Uri.parse(directUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!ok) throw Exception('Could not open URL');
        return;
      }

      if (storagePath == null || storagePath.isEmpty) {
        throw Exception('No storage path');
      }

      String downloadUrl;
      if (storagePath.startsWith('gs://') || storagePath.startsWith('http')) {
        final ref = storage.FirebaseStorage.instance.refFromURL(storagePath);
        downloadUrl = await ref.getDownloadURL();
      } else {
        final ref = storage.FirebaseStorage.instance.ref(storagePath);
        downloadUrl = await ref.getDownloadURL();
      }

      final ok = await launchUrl(
        Uri.parse(downloadUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception('Could not open file');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Open failed: $e')));
    }
  }

  // --- Normalize artifacts regardless of backend shape ---
  // Accepts:
  //  - artifacts: [ { name/fileName, storagePath, size/sizeBytes, contentType, downloadUrl/publicUrl } ]
  //  - artifact:  { ...single map... }
  List<_Artifact> _readArtifacts(Map<String, dynamic> m) {
    final List<_Artifact> out = [];

    // plural list
    final list = m['artifacts'];
    if (list is List) {
      for (final e in list) {
        if (e is Map) out.add(_Artifact.fromMap(e.cast<String, dynamic>()));
      }
    }

    // singular
    final single = m['artifact'];
    if (single is Map) {
      out.add(_Artifact.fromMap(single.cast<String, dynamic>()));
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_jobRef == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Detail'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(
                '/jobs',
              ); // fallback when this page is the root of a nested navigator
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
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _jobRef!.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final m = snap.data!.data();
          if (m == null) return const Center(child: Text('Job not found.'));

          final status = (m['status'] as String?) ?? 'pending';
          final progress = (m['progress'] as num?)?.toDouble() ?? 0.0;
          final name = (m['name'] as String?) ?? widget.jobId;
          final createdAt = (m['createdAt'] as Timestamp?)?.toDate();
          final updatedAt = (m['updatedAt'] as Timestamp?)?.toDate();

          final source = (m['source'] as Map?) ?? {};
          final srcPath = (source['storagePath'] as String?) ?? '';

          final aiRun = (m['aiRun'] as Map?)?.cast<String, dynamic>();
          final artifacts = _readArtifacts(m);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // ===== Header
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            _statusChip(status),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value:
                              (status == 'succeeded' || status == 'failed')
                                  ? 1.0
                                  : progress.clamp(0, 1),
                          minHeight: 6,
                        ),
                        const SizedBox(height: 10),
                        _kv('Status', status),
                        _kv(
                          'Progress',
                          '${(progress * 100).toStringAsFixed(0)}%',
                        ),
                        if (createdAt != null)
                          _kv('Created', createdAt.toLocal().toString()),
                        if (updatedAt != null)
                          _kv('Updated', updatedAt.toLocal().toString()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Metadata
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Metadata',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 120, child: Text('Source')),
                            Expanded(
                              child: Text(
                                srcPath.isEmpty ? '—' : srcPath,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (srcPath.isNotEmpty)
                              TextButton.icon(
                                onPressed:
                                    () => _openObject(storagePath: srcPath),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Download'),
                              ),
                          ],
                        ),
                        if (aiRun != null) ...[
                          const SizedBox(height: 8),
                          _kv('AI status', (aiRun['status'] ?? '—').toString()),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Artifacts
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Artifacts',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (artifacts.isEmpty)
                          Text(
                            'No artifacts yet.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          )
                        else
                          Column(
                            children:
                                artifacts.map((a) {
                                  return ListTile(
                                    title: Text(a.displayName),
                                    subtitle: Text(a.contentType ?? 'file'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (a.sizeBytes != null)
                                          Text(
                                            '${(a.sizeBytes! / (1024 * 1024)).toStringAsFixed(2)} MB',
                                          ),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          tooltip: 'Download',
                                          icon: const Icon(
                                            Icons.download_outlined,
                                          ),
                                          onPressed:
                                              () => _openObject(
                                                storagePath: a.storagePath,
                                                directUrl: a.directUrl,
                                              ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ===== Logs (subcollection) + AI run message/debug fallback
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      _jobRef!
                          .collection('logs')
                          .orderBy('ts', descending: true)
                          .limit(200)
                          .snapshots(),
                  builder: (context, logSnap) {
                    final docs = logSnap.data?.docs ?? const [];
                    final hasLogs = docs.isNotEmpty;
                    final aiMessage = (aiRun?['message'] as String?)?.trim();
                    final aiDebug = aiRun?['debug'];

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Logs',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),

                            if (!hasLogs && aiMessage == null)
                              Text(
                                'No logs yet.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),

                            if (hasLogs)
                              ...docs.map((d) {
                                final m = d.data();
                                final lvl = (m['level'] as String?) ?? 'info';
                                final msg = (m['message'] as String?) ?? '';
                                final ts = (m['ts'] as Timestamp?)?.toDate();
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 170,
                                        child: Text(
                                          ts?.toLocal().toIso8601String() ?? '',
                                          style: const TextStyle(
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 64,
                                        child: Text(lvl.toUpperCase()),
                                      ),
                                      Expanded(child: Text(msg)),
                                    ],
                                  ),
                                );
                              }),

                            if (aiMessage != null) ...[
                              if (hasLogs) const Divider(),
                              Text(
                                'AI run message',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest.withOpacity(
                                    0.35,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(aiMessage),
                              ),
                            ],

                            if (aiDebug != null) ...[
                              const SizedBox(height: 8),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text('Debug details'),
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest
                                          .withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(aiDebug.toString()),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusChip(String s) {
    final cs = Theme.of(context).colorScheme;
    Color bg, fg;
    switch (s) {
      case 'pending':
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
        break;
      case 'running':
        bg = Colors.blue.withOpacity(0.12);
        fg = Colors.blue.shade700;
        break;
      case 'succeeded':
        bg = Colors.green.withOpacity(0.12);
        fg = Colors.green.shade700;
        break;
      case 'failed':
        bg = cs.error.withOpacity(0.12);
        fg = cs.error;
        break;
      default:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s[0].toUpperCase() + s.substring(1),
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _kv(String k, String v) => Row(
    children: [
      const SizedBox(width: 120, child: Text('')),
      Expanded(
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(
                k,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(v, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    ],
  );
}

// ---- Artifact model/normalizer ----
class _Artifact {
  final String? name;
  final String? fileName;
  final String? storagePath; // gs:// or relative
  final String? contentType;
  final int? sizeBytes;
  final String? directUrl; // downloadUrl/publicUrl

  _Artifact({
    this.name,
    this.fileName,
    this.storagePath,
    this.contentType,
    this.sizeBytes,
    this.directUrl,
  });

  String get displayName =>
      (name?.isNotEmpty == true)
          ? name!
          : (fileName?.isNotEmpty == true)
          ? fileName!
          : (storagePath ?? 'artifact');

  factory _Artifact.fromMap(Map<String, dynamic> m) {
    // accept various key spellings
    final size = (m['sizeBytes'] ?? m['size'] ?? m['bytes']) as num?;
    final url = (m['downloadUrl'] ?? m['publicUrl'] ?? m['url']) as String?;
    final path = (m['storagePath'] ?? m['path'] ?? m['gsPath']) as String?;
    return _Artifact(
      name: m['name'] as String?,
      fileName: m['fileName'] as String?,
      storagePath: path,
      contentType: m['contentType'] as String?,
      sizeBytes: size?.toInt(),
      directUrl: url,
    );
  }
}
