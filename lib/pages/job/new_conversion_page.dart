// new_conversion_page.dart  — simplified: 3 steps + ZIP output always
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/model/models.dart';
import 'package:excelaratorapi/service/firestore_dao.dart';
import 'package:excelaratorapi/service/user_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/material.dart';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:go_router/go_router.dart';

class NewConversionPage extends StatefulWidget {
  const NewConversionPage({super.key});
  @override
  State<NewConversionPage> createState() => _NewConversionPageState();
}

/// Six generation tracks
enum _Track {
  springBootOpenApi,
  dbAndAdmin,
  postgresSchema,
  dataModelOrm,
  etlWorkflow,
  analyticsDashboard,
}

class _TrackInfo {
  final String label;
  final String shortDesc;
  final String templateKey;
  const _TrackInfo(this.label, this.shortDesc, this.templateKey);
}

const Map<_Track, _TrackInfo> _tracks = {
  _Track.springBootOpenApi: _TrackInfo(
    'Spring Boot + OpenAPI',
    'Generate REST API with entities, repos, Flyway/Liquibase and Swagger.',
    'excel_to_springboot_openapi',
  ),
  _Track.dbAndAdmin: _TrackInfo(
    'Database + Admin',
    'Create Postgres schema + admin panel scaffolding.',
    'excel_to_database_and_admin',
  ),
  _Track.postgresSchema: _TrackInfo(
    'Postgres Schema (DDL)',
    'Tables, FKs, indexes, enums and comments.',
    'excel_to_postgres_schema',
  ),
  _Track.dataModelOrm: _TrackInfo(
    'Data Model + ORM + Migrations',
    'Prisma/TypeORM models and migrations (+ seed).',
    'excel_to_data_model_orm_migrations',
  ),
  _Track.etlWorkflow: _TrackInfo(
    'ETL / Workflow (Airflow)',
    'Airflow DAG: extract → validate → transform → load → QA.',
    'excel_to_etl_airflow',
  ),
  _Track.analyticsDashboard: _TrackInfo(
    'Analytics Dashboard',
    'Model SQL views + importable Metabase/Superset assets.',
    'excel_to_analytics_dashboard',
  ),
};

class _NewConversionPageState extends State<NewConversionPage> {
  int _step = 0;
  bool _busy = false;

  // Upload
  String? _fileName;
  int? _fileBytes;
  Uint8List? _fileData;

  // Track selection
  _Track _track = _Track.springBootOpenApi;

  // Repos
  final _jobsRepo = JobsRepository();
  final _convRepo = ConversionsRepository();
  final userModel = UserModel();

  // Logs
  bool kClientLogs = true;
  Future<void> _clientLog(
    String orgId,
    String stage,
    Map<String, dynamic> data,
  ) async {
    if (!kClientLogs) return;
    try {
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('client_logs')
          .add({
            'stage': stage,
            'data': data,
            'ts': FieldValue.serverTimestamp(),
            'uid': FirebaseAuth.instance.currentUser?.uid,
          });
    } catch (_) {}
  }

  void _next() {
    if (_step < 2) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read file bytes.')),
      );
      return;
    }
    setState(() {
      _fileName = file.name;
      _fileData = file.bytes!;
      _fileBytes = _fileData!.length;
    });
  }

  Future<void> _submitJob() async {
    if (_fileData == null || _fileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a spreadsheet first.')),
      );
      setState(() => _step = 0);
      return;
    }
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in.')));
      return;
    }

    final orgId = 'org-${authUser.uid}';
    setState(() => _busy = true);

    UserModel userModel = UserManager.currentUser!;
    try {
      // Ensure org (idempotent)
      await FirebaseFirestore.instance.collection('orgs').doc(orgId).set({
        'name': 'Personal Workspace',
        'owners': FieldValue.arrayUnion([authUser.uid]),
        'members': FieldValue.arrayUnion([authUser.uid]),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Upload source file to Storage
      final safe = _fileName!.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'orgs/$orgId/uploads/$stamp-$safe';
      final ref = storage.FirebaseStorage.instance.ref().child(path);
      await ref.putData(
        _fileData!,
        storage.SettableMetadata(
          contentType: _contentTypeFor(_fileName!),
          cacheControl: 'private',
        ),
      );

      // Create conversion + job
      final conv = Conversion(
        id: '',
        orgId: orgId,
        createdBy: authUser.uid,
        name: 'From ${_fileName!}',
        description: 'Excelarator conversion (${_tracks[_track]!.label})',
        type: _jobTypeFor(_track),
        spreadsheet: SpreadsheetSource(
          fileName: _fileName!,
          storagePath: path,
          sheets: const [],
          headerRow: true,
        ),
        database: null, // no DB step anymore
        schema: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final convId = await _convRepo.createConversion(orgId, conv);

      final job = Job(
        id: '',
        orgId: orgId,
        userId: authUser.uid,
        name: '${_tracks[_track]!.label}: ${_fileName!}',
        type: _jobTypeFor(_track),
        status: JobStatus.pending,
        progress: 0.0,
        createdAt: DateTime.now(),
        conversionId: convId,
        artifacts: const [],
      );
      final jobId = await _jobsRepo.createJob(orgId, job);

      // Backend routing metadata
      final info = _tracks[_track]!;
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('jobs')
          .doc(jobId)
          .set({
            'track': _track.name,
            'templateKey': info.templateKey,
            'packageTarget': 'zip',
            'source': {'fileName': _fileName, 'storagePath': path},
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Build queued!')));
      // Go to Job Detail
      context.go('/jobs/$jobId');
    } catch (e, st) {
      // ignore: avoid_print
      print(st);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start build: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  JobType _jobTypeFor(_Track t) {
    // Map to your model’s enum values
    switch (t) {
      case _Track.springBootOpenApi:
        return JobType.spreadsheetToSpring;
      case _Track.dbAndAdmin:
        return JobType.spreadsheetToDbAdmin;
      case _Track.postgresSchema:
        return JobType.spreadsheetToPostgresSchema;
      case _Track.dataModelOrm:
        return JobType.spreadsheetToOrm;
      case _Track.etlWorkflow:
        return JobType.spreadsheetToEtl;
      case _Track.analyticsDashboard:
        return JobType.spreadsheetToAnalytics;
    }
  }

  String _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.csv')) return 'text/csv';
    return 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      userModel: userModel,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Conversion'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go(
                  '/home',
                ); // fallback when this page is the root of a nested navigator
              }
            },
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final showSide = constraints.maxWidth >= 980;
            return Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        child: Stepper(
                          type: StepperType.vertical,
                          currentStep: _step,
                          onStepContinue: _step == 2 ? _submitJob : _next,
                          onStepCancel: _back,
                          controlsBuilder: (context, details) {
                            return Row(
                              children: [
                                FilledButton.icon(
                                  onPressed:
                                      _busy ? null : details.onStepContinue,
                                  icon:
                                      _step == 2
                                          ? (_busy
                                              ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                              : const Icon(
                                                Icons.build_outlined,
                                              ))
                                          : const Icon(Icons.arrow_forward),
                                  label: Text(_step == 2 ? 'Generate' : 'Next'),
                                ),
                                const SizedBox(width: 8),
                                if (_step > 0)
                                  OutlinedButton.icon(
                                    onPressed:
                                        _busy ? null : details.onStepCancel,
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Back'),
                                  ),
                              ],
                            );
                          },
                          steps: [
                            Step(
                              title: const Text('Source'),
                              isActive: _step >= 0,
                              state:
                                  _step > 0
                                      ? StepState.complete
                                      : StepState.indexed,
                              content: _SourceStep(
                                fileName: _fileName,
                                fileBytes: _fileBytes,
                                onPick: _pickFile,
                              ),
                            ),
                            Step(
                              title: const Text('What to generate'),
                              isActive: _step >= 1,
                              state:
                                  _step > 1
                                      ? StepState.complete
                                      : StepState.indexed,
                              content: _TrackStep(
                                selected: _track,
                                onChanged: (t) => setState(() => _track = t),
                              ),
                            ),
                            Step(
                              title: const Text('Review & Generate'),
                              isActive: _step >= 2,
                              state:
                                  _step == 2 && _busy
                                      ? StepState.editing
                                      : StepState.indexed,
                              content: _ReviewStep(
                                fileName: _fileName,
                                fileBytes: _fileBytes,
                                track: _track,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (showSide) const SizedBox(width: 8),
                if (showSide)
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
                      child: _SummaryCard(
                        fileName: _fileName,
                        fileBytes: _fileBytes,
                        track: _track,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ====== Step content widgets ======
class _SourceStep extends StatelessWidget {
  final String? fileName;
  final int? fileBytes;
  final VoidCallback onPick;
  const _SourceStep({
    required this.fileName,
    required this.fileBytes,
    required this.onPick,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload an Excel/CSV file',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.surface,
              border: Border.all(color: cs.outline.withOpacity(0.24)),
            ),
            child: Row(
              children: [
                Icon(Icons.upload_file_outlined, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileName ?? 'Choose file (.xlsx, .csv)…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (fileBytes != null)
                  Text(
                    '${(fileBytes! / (1024 * 1024)).toStringAsFixed(2)} MB',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We’ll detect sheets, headers and basic types automatically.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _TrackStep extends StatelessWidget {
  final _Track selected;
  final ValueChanged<_Track> onChanged;
  const _TrackStep({required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final options = [
      (_Track.springBootOpenApi, Icons.api_outlined),
      (_Track.dbAndAdmin, Icons.storage_outlined),
      (_Track.postgresSchema, Icons.account_tree_outlined),
      (_Track.dataModelOrm, Icons.device_hub_outlined),
      (_Track.etlWorkflow, Icons.workspaces_outlined),
      (_Track.analyticsDashboard, Icons.monitor_heart_outlined),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 1100 ? 3 : (c.maxWidth > 760 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: options.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 132,
          ),
          itemBuilder: (_, i) {
            final (track, icon) = options[i];
            final info = _tracks[track]!;
            final bool isSel = track == selected;
            return InkWell(
              onTap: () => onChanged(track),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSel ? cs.primary : cs.outline.withOpacity(0.24),
                    width: isSel ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.label,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            info.shortDesc,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const Spacer(),
                          Row(
                            children: [
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
                                  _tracks[track]!.templateKey,
                                  style: TextStyle(
                                    color: cs.secondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (isSel)
                                Icon(
                                  Icons.check_circle,
                                  color: cs.primary,
                                  size: 18,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReviewStep extends StatelessWidget {
  final String? fileName;
  final int? fileBytes;
  final _Track track;
  const _ReviewStep({
    required this.fileName,
    required this.fileBytes,
    required this.track,
  });
  @override
  Widget build(BuildContext context) {
    final info = _tracks[track]!;
    final size =
        fileBytes != null
            ? '${(fileBytes! / (1024 * 1024)).toStringAsFixed(2)} MB'
            : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv('Track', info.label),
        _kv('Template key', info.templateKey),
        _kv('Source file', fileName ?? '—'),
        _kv('Size', size),
        _kv('Output', 'ZIP archive (source + assets)'),
        const SizedBox(height: 8),
        Text(
          'Tip: When Excel follows the recommended template you will get better results.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(v, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  final String? fileName;
  final int? fileBytes;
  final _Track track;
  const _SummaryCard({
    required this.fileName,
    required this.fileBytes,
    required this.track,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = _tracks[track]!;
    final size =
        fileBytes != null
            ? '${(fileBytes! / (1024 * 1024)).toStringAsFixed(2)} MB'
            : '—';
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Summary',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _kv('Track', info.label),
            _kv('Template key', info.templateKey),
            _kv('Source file', fileName ?? '—'),
            _kv('Size', size),
            _kv('Output', 'ZIP archive'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(v, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
