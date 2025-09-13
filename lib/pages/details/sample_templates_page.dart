// lib/pages/details/sample_templates_page.dart
import 'package:archive/archive.dart';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class SampleTemplatesPage extends StatelessWidget {
  const SampleTemplatesPage({super.key});

  static const _items = <_TemplateItem>[
    _TemplateItem(
      keyId: 'springboot',
      title: 'Excel → Spring Boot + OpenAPI',
      description:
          'Entities from sheets; headers as fields. CRUD controllers, OpenAPI, Liquibase, tests, Dockerfile.',
      assetPath: 'assets/templates/excel_to_springboot.xlsx',
      fileName: 'excel_to_springboot.xlsx',
      imageAsset: 'assets/templates/excel_spring_openapi.png',
      prompt: '''
Generate a Spring Boot app from the provided spreadsheet:
- Each sheet = entity, first row = field names, infer types.
- Create JPA entities, repositories, CRUD controllers, OpenAPI.
- Include Liquibase migrations, unit tests, Dockerfile.
- Return a single .zip with project root.
''',
      chips: ['CRUD', 'OpenAPI', 'Liquibase', 'Docker'],
    ),
    _TemplateItem(
      keyId: 'dbadmin',
      title: 'Excel → Database + Admin',
      description:
          'Create DB schema, seed data, and a ready-to-run admin UI. Prefer Postgres.',
      assetPath: 'assets/templates/excel_to_db_admin.xlsx',
      imageAsset: 'assets/templates/excel_db_admin.png',
      fileName: 'excel_to_db_admin.xlsx',
      prompt: '''
Generate a Postgres database + ready-to-run admin UI from the provided Excel workbook.
- Produce DDL with constraints & indexes, plus seed data.
- Include a quick admin UI scaffold to browse/edit tables.
- Return a single .zip with instructions.
''',
      chips: ['Postgres', 'DDL', 'Admin UI'],
    ),
    _TemplateItem(
      keyId: 'pgschema',
      title: 'Excel → Postgres Schema',
      description:
          'High-quality Postgres DDL, constraints, indexes, and import scripts.',
      assetPath: 'assets/templates/excel_to_postgres_schema.xlsx',
      imageAsset: 'assets/templates/excel_postgres_schema.png',
      fileName: 'excel_to_postgres_schema.xlsx',
      prompt: '''
Produce high-quality Postgres DDL from the provided Excel workbook:
- Robust types, constraints, FKs, and useful indexes.
- Include a data import script (psql or COPY).
- Return a single .zip.
''',
      chips: ['Postgres DDL', 'Indexes', 'COPY'],
    ),
    _TemplateItem(
      keyId: 'orm',
      title: 'Excel → Data Model + ORM + Migrations',
      description:
          'From sheets to ORM models, migrations, and a README. Choose JPA/Prisma/Sequelize based on context.',
      assetPath: 'assets/templates/excel_to_orm.xlsx',
      imageAsset: 'assets/templates/excel_ORM_migrations.png',
      fileName: 'excel_to_orm.xlsx',
      prompt: '''
Convert the Excel workbook into a complete ORM project with migrations:
- Infer entities & relations; add sensible naming & IDs.
- Provide migrations and a README to run locally.
- Return a single .zip.
''',
      chips: ['ORM', 'Migrations', 'README'],
    ),
    _TemplateItem(
      keyId: 'etl',
      title: 'Excel → ETL / Workflow',
      description:
          'Generate Airflow / Temporal / GitHub Actions to ingest and validate data idempotently.',
      assetPath: 'assets/templates/excel_to_etl.xlsx',
      imageAsset: 'assets/templates/excel_etl_workflow.png',
      fileName: 'excel_to_etl.xlsx',
      prompt: '''
Create a robust, idempotent workflow to ingest data from Excel:
- Pick Airflow/Temporal/GitHub Actions and justify.
- Implement validations and failure notifications.
- Return a single .zip with deploy/run instructions.
''',
      chips: ['Airflow', 'Temporal', 'GitHub Actions'],
    ),
    _TemplateItem(
      keyId: 'analytics',
      title: 'Excel → Analytics Dashboard',
      description:
          'Produce dashboards and datasets for Metabase / Superset / Looker Studio.',
      assetPath: 'assets/templates/excel_to_analytics.xlsx',
      imageAsset: 'assets/templates/excel_analytics.png',
      fileName: 'excel_to_analytics.xlsx',
      prompt: '''
Generate an importable analytics package from the Excel workbook:
- Define datasets, fields, metrics, and 2–3 sample dashboards.
- Support Metabase/Superset/Looker Studio.
- Return a single .zip with a quickstart.
''',
      chips: ['Metabase', 'Superset', 'Looker Studio'],
    ),
  ];

  // --- Helpers: save a single asset, or zip all assets and save ---

  Future<void> _saveAsset(
    BuildContext context, {
    required String assetPath,
    required String fileName,
    String ext = 'xlsx',
  }) async {
    try {
      final bd = await rootBundle.load(assetPath);
      final bytes = bd.buffer.asUint8List();

      // file_saver works across Web / Desktop / Mobile
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: ext,
        // If your FileSaver version prefers MIME string, use:
        // mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        mimeType: MimeType.other,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved $fileName')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _saveAllAsZip(BuildContext context) async {
    try {
      final archive = Archive();
      for (final t in _items) {
        final bd = await rootBundle.load(t.assetPath);
        final bytes = bd.buffer.asUint8List();
        archive.addFile(ArchiveFile(t.fileName, bytes.length, bytes));
      }
      final zipped = ZipEncoder().encode(archive)!;
      final out = Uint8List.fromList(zipped);

      await FileSaver.instance.saveFile(
        name: 'excelarator-templates',
        bytes: out,
        ext: 'zip',
        mimeType: MimeType.other, // or 'application/zip' if string is required
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved excelarator-templates.zip')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Zip save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1100;
    final cs = Theme.of(context).colorScheme;

    return MainLayout(
      userModel: UserModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sample Templates'),
          leading: IconButton(
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
            TextButton.icon(
              onPressed: () => _saveAllAsZip(context),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Download all (.zip)'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroBar(onConvert: () => context.go('/convert')),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final t in _items)
                        SizedBox(
                          width: wide ? 550 : double.infinity,
                          child: _TemplateCard(
                            item: t,
                            onDownload:
                                () => _saveAsset(
                                  context,
                                  assetPath: t.assetPath,
                                  fileName: t.fileName,
                                ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBar extends StatelessWidget {
  final VoidCallback onConvert;
  const _HeroBar({required this.onConvert});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kickstart with ready-made Excel templates',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Kickstart your build with these templates for better first-pass conversions. Prefer your own sheet? Upload it—our engine will infer the model and generate the artifacts.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onConvert,
            icon: const Icon(Icons.auto_awesome_motion_outlined),
            label: const Text('Start converting'),
          ),
        ],
      ),
    );
  }
}

class _TemplateItem {
  final String keyId;
  final String title;
  final String description;
  final String assetPath; // asset path in pubspec
  final String fileName; // default name to save as
  final String imageAsset;
  final String prompt;
  final List<String> chips;
  const _TemplateItem({
    required this.keyId,
    required this.title,
    required this.description,
    required this.assetPath,
    required this.imageAsset,
    required this.fileName,
    required this.prompt,
    required this.chips,
  });
}

class _TemplateCard extends StatelessWidget {
  final _TemplateItem item;
  final VoidCallback onDownload;
  const _TemplateCard({required this.item, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(_iconFor(item.keyId), color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children:
                      item.chips
                          .map(
                            (c) => Chip(
                              label: Text(c),
                              labelStyle: const TextStyle(
                                fontSize: 12,
                                color: Colors.black,
                              ),
                              side: BorderSide(
                                color: cs.outline.withOpacity(0.4),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.description),
            const SizedBox(height: 12),

            // Preview placeholder
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.35),
                border: Border.all(color: cs.outline.withOpacity(0.35)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Image.asset(
                  item.imageAsset,
                  fit: BoxFit.cover,
                  height: 200, // or whatever your card uses
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Actions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Download .xlsx'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String key) {
    switch (key) {
      case 'springboot':
        return Icons.developer_board_outlined;
      case 'dbadmin':
        return Icons.table_chart_outlined;
      case 'pgschema':
        return Icons.storage_outlined;
      case 'orm':
        return Icons.data_object_outlined;
      case 'etl':
        return Icons.swap_horiz_outlined;
      case 'analytics':
        return Icons.analytics_outlined;
      default:
        return Icons.extension_outlined;
    }
  }
}
