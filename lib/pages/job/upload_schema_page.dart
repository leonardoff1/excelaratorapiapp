// lib/pages/details/upload_schema_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:go_router/go_router.dart';

class UploadSchemaPage extends StatefulWidget {
  const UploadSchemaPage({super.key});
  @override
  State<UploadSchemaPage> createState() => _UploadSchemaPageState();
}

class _UploadSchemaPageState extends State<UploadSchemaPage> {
  // Wizard
  int _step = 0;
  bool _busy = false;

  // Upload
  String? _fileName;
  String? _contentType;
  Uint8List? _fileBytes;

  // Option (target conversion)
  String _conversion = 'Spring Boot (OpenAPI + CRUD)';

  final userModel = UserModel();

  void _next() {
    if (_step < 1) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  String? get _orgId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return 'org-$uid';
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'sql', 'ddl', 'zip'],
      withData: true,
      allowMultiple: false,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    if (f.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read file bytes.')),
      );
      return;
    }
    setState(() {
      _fileName = f.name;
      _fileBytes = f.bytes!;
      _contentType = _guessContentType(f.name);
    });
  }

  String _guessContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.sql') || lower.endsWith('.ddl')) return 'text/sql';
    if (lower.endsWith('.zip')) return 'application/zip';
    return 'application/octet-stream';
  }

  String _jobTypeFromUi(String v) {
    switch (v) {
      case 'Spring Boot (OpenAPI + CRUD)':
        return 'schemaToSpring';
      case 'Database + Admin UI':
        return 'schemaToDbAdmin';
      case 'Postgres DDL (schema.sql)':
        return 'schemaToPostgresSchema';
      case 'Data Model + ORM + Migrations':
        return 'schemaToOrm';
      case 'ETL / Workflow package':
        return 'schemaToEtl';
      case 'Analytics package (dashboards)':
        return 'schemaToAnalytics';
      default:
        return 'schemaToSpring';
    }
  }

  Future<String> _uploadToStorage({
    required String orgId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'orgs/$orgId/uploads/$stamp-$safe';
    final ref = storage.FirebaseStorage.instance.ref().child(path);
    await ref.putData(
      bytes,
      storage.SettableMetadata(
        contentType: contentType,
        cacheControl: 'private',
      ),
    );
    return path;
  }

  Future<void> _submit() async {
    if (_fileBytes == null || _fileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a schema file first.')),
      );
      setState(() => _step = 0);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final orgId = _orgId;
    if (user == null || orgId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in.')));
      return;
    }

    setState(() => _busy = true);
    try {
      // 1) Upload file
      final storagePath = await _uploadToStorage(
        orgId: orgId,
        fileName: _fileName!,
        bytes: _fileBytes!,
        contentType: _contentType ?? 'application/octet-stream',
      );

      // 2) Create conversion
      final now = FieldValue.serverTimestamp();
      final convRef = await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('conversions')
          .add({
            'name': 'Schema: ${_fileName!}',
            'description': 'Uploaded schema for conversion ($_conversion)',
            'type': _jobTypeFromUi(_conversion),
            'createdBy': user.uid,
            'orgId': orgId,
            'createdAt': now,
            'updatedAt': now,
            'schema': {
              'fileName': _fileName!,
              'storagePath': storagePath,
              'contentType': _contentType ?? 'application/octet-stream',
            },
            'package': {'target': 'ZIP Source', 'docker': true, 'cicd': true},
          });

      // 3) Create job
      final jobRef = await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('jobs')
          .add({
            'name': 'Build from schema: ${_fileName!}',
            'type': _jobTypeFromUi(_conversion),
            'status': 'pending',
            'progress': 0.0,
            'conversionId': convRef.id,
            'userId': user.uid,
            'orgId': orgId,
            'createdAt': now,
            'updatedAt': now,
          });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Queued! Job ${jobRef.id}')));
      // Go to Job Detail
      context.go('/jobs/${jobRef.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to queue: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      userModel: userModel,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Upload DB Schema'),
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
                // Main
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
                          onStepContinue: _step == 1 ? _submit : _next,
                          onStepCancel: _back,
                          controlsBuilder: (context, details) {
                            return Row(
                              children: [
                                FilledButton.icon(
                                  onPressed:
                                      _busy ? null : details.onStepContinue,
                                  icon:
                                      _step == 1
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
                                  label: Text(_step == 1 ? 'Generate' : 'Next'),
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
                              title: const Text('Schema file'),
                              isActive: _step >= 0,
                              state:
                                  _fileBytes != null
                                      ? StepState.complete
                                      : StepState.indexed,
                              content: _SchemaSourceStep(
                                fileName: _fileName,
                                size: _fileBytes?.length,
                                onPick: _pickFile,
                              ),
                            ),
                            Step(
                              title: const Text('Conversion'),
                              isActive: _step >= 1,
                              state:
                                  _busy ? StepState.editing : StepState.indexed,
                              content: _SchemaConversionStep(
                                selected: _conversion,
                                onChanged:
                                    (v) => setState(() => _conversion = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                if (showSide) const SizedBox(width: 8),

                // Summary
                if (showSide)
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
                      child: _SummaryCard(
                        fileName: _fileName,
                        size: _fileBytes?.length,
                        conversion: _conversion,
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

// ========== Step widgets ==========

class _SchemaSourceStep extends StatelessWidget {
  final String? fileName;
  final int? size;
  final VoidCallback onPick;
  const _SchemaSourceStep({
    required this.fileName,
    required this.size,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upload schema (.json / .sql / .zip)',
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
                    fileName ?? 'Choose schema file…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (size != null)
                  Text(
                    '${(size! / (1024 * 1024)).toStringAsFixed(2)} MB',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No direct DB access is required. Export your schema from your DB as SQL (recommended) or JSON and upload it here.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('How do I export my schema?'),
            onPressed:
                () => showModalBottomSheet(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => const _SchemaTipsSheet(),
                ),
          ),
        ),
      ],
    );
  }
}

class _SchemaConversionStep extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _SchemaConversionStep({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = const [
      'Spring Boot (OpenAPI + CRUD)',
      'Database + Admin UI',
      'Postgres DDL (schema.sql)',
      'Data Model + ORM + Migrations',
      'ETL / Workflow package',
      'Analytics package (dashboards)',
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children:
          items.map((label) {
            final chosen = label == selected;
            return InkWell(
              onTap: () => onChanged(label),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 330,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        chosen
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.24),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _iconFor(label),
                      color:
                          chosen
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color:
                              chosen
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                        ),
                      ),
                    ),
                    if (chosen)
                      const Icon(Icons.check_circle, color: Colors.green),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }

  IconData _iconFor(String label) {
    switch (label) {
      case 'Spring Boot (OpenAPI + CRUD)':
        return Icons.api_outlined;
      case 'Database + Admin UI':
        return Icons.table_view_outlined;
      case 'Postgres DDL (schema.sql)':
        return Icons.storage_outlined;
      case 'Data Model + ORM + Migrations':
        return Icons.model_training_outlined;
      case 'ETL / Workflow package':
        return Icons.merge_type_outlined;
      case 'Analytics package (dashboards)':
        return Icons.analytics_outlined;
      default:
        return Icons.extension_outlined;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final String? fileName;
  final int? size;
  final String conversion;
  const _SummaryCard({
    required this.fileName,
    required this.size,
    required this.conversion,
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
              'Summary',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _kv('File', fileName ?? '—'),
            _kv(
              'Size',
              size != null
                  ? '${(size! / (1024 * 1024)).toStringAsFixed(2)} MB'
                  : '—',
            ),
            _kv('Conversion', conversion),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.secondary.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: cs.secondary, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Files kept for 24h. Private by default.'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
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
}

// ---------- Help bottom sheet ----------

class _SchemaTipsSheet extends StatelessWidget {
  const _SchemaTipsSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ListView(
            controller: controller,
            children: [
              Text(
                'Export your database schema',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Generate a schema-only dump as SQL (recommended) or JSON, then upload it here.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),

              _DbTipCard(
                title: 'PostgreSQL',
                bullets: const [
                  'Install: `brew install postgresql@16` or use your OS package manager.',
                  'Schema-only dump (includes types, tables, views, FKs; excludes data):',
                ],
                commands: const [
                  'pg_dump -h <HOST> -U <USER> -d <DATABASE> --schema-only --no-owner --no-privileges -f schema.sql',
                ],
              ),
              _DbTipCard(
                title: 'MySQL / MariaDB',
                bullets: const [
                  'Install: `brew install mysql` or `brew install mariadb`.',
                  'Schema-only dump (no data), include routines/events if you use them:',
                ],
                commands: const [
                  'mysqldump -h <HOST> -u <USER> -p <DATABASE> --no-data --routines --events > schema.sql',
                ],
              ),
              _DbTipCard(
                title: 'SQL Server',
                bullets: const [
                  'Option A (SSMS/Azure Data Studio): Right-click database → Generate Scripts → choose "Schema only" → Save to file.',
                  'Option B (sqlpackage CLI: cross-platform):',
                ],
                commands: const [
                  'sqlpackage /Action:Export /SourceServerName:<HOST> /SourceDatabaseName:<DB> /TargetFile:db.dacpac',
                  'sqlpackage /Action:Script /SourceFile:db.dacpac /TargetFile:schema.sql /p:ExtractAllTableData=False',
                ],
              ),
              _DbTipCard(
                title: 'Oracle',
                bullets: const [
                  'Option A (DBMS_METADATA via SQL*Plus):',
                  'This will spool CREATE statements for all user tables.',
                ],
                commands: const [
                  'sqlplus <USER>/<PASS>@<HOST>/<SERVICE>',
                  'SET LONG 1000000 LONGCHUNKSIZE 100000 LINESIZE 200 PAGESIZE 0',
                  'SPOOL schema.sql',
                  "SELECT DBMS_METADATA.GET_DDL('TABLE', table_name, USER) FROM user_tables;",
                  'SPOOL OFF',
                ],
              ),
              _DbTipCard(
                title: 'SQLite',
                bullets: const ['Generate the DDL from your local file:'],
                commands: const [
                  'sqlite3 ./mydb.sqlite ".schema" > schema.sql',
                ],
              ),
              _DbTipCard(
                title: 'Zip (optional)',
                bullets: const ['If your dump is large, zip it before upload:'],
                commands: const ['zip schema.zip schema.sql'],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: cs.onSurface),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Security: We only need structure. Avoid including table data. Files are private in your bucket and purged automatically per your retention.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DbTipCard extends StatelessWidget {
  final String title;
  final List<String> bullets;
  final List<String> commands;

  const _DbTipCard({
    required this.title,
    required this.bullets,
    required this.commands,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $b',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ...commands.map((c) => _CodeTile(command: c)),
          ],
        ),
      ),
    );
  }
}

class _CodeTile extends StatelessWidget {
  final String command;
  const _CodeTile({required this.command});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outline.withOpacity(0.24)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: const TextStyle(fontFamily: 'monospace', height: 1.3),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: command));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied')));
            },
          ),
        ],
      ),
    );
  }
}
