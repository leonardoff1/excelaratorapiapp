import 'dart:ui';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/service/user_manager.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class DocsPage extends StatefulWidget {
  const DocsPage({super.key});

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  final _scroll = ScrollController();

  // Section anchors
  final _kIntro = GlobalKey();
  final _kConversions = GlobalKey();
  final _kSchemaConversions = GlobalKey();
  final _kSchemaFormat = GlobalKey();
  final _kDbExport = GlobalKey();
  final _kHowItWorks = GlobalKey();
  final _kUsing = GlobalKey();
  final _kArtifacts = GlobalKey();
  final _kJobs = GlobalKey();
  final _kSecurity = GlobalKey();
  final _kLimits = GlobalKey();
  final _kTroubleshoot = GlobalKey();
  final _kFAQ = GlobalKey();
  final _kSupport = GlobalKey();

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1100;

    final user = UserManager.currentUser;

    final isAdmin = (user?.isAdmin == true) || (user?.admin == true);

    return MainLayout(
      userModel: UserModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Documentation'),
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
              onPressed: () => context.go('/convert'),
              icon: const Icon(Icons.auto_awesome_motion_outlined),
              label: const Text('New Conversion'),
            ),
            TextButton.icon(
              onPressed: () => context.go('/jobs'),
              icon: const Icon(Icons.history_outlined),
              label: const Text('Jobs'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          children: [
            if (wide)
              _SideToc(
                onTap: (k) {
                  switch (k) {
                    case 'Intro':
                      _jumpTo(_kIntro);
                      break;
                    case 'Spreadsheet conversions':
                      _jumpTo(_kConversions);
                      break;
                    case 'Schema conversions':
                      _jumpTo(_kSchemaConversions);
                      break;
                    case 'Schema JSON (v1)':
                      _jumpTo(_kSchemaFormat);
                      break;
                    case 'DB export tips':
                      _jumpTo(_kDbExport);
                      break;
                    case 'How it works':
                      _jumpTo(_kHowItWorks);
                      break;
                    case 'Using Excelarator':
                      _jumpTo(_kUsing);
                      break;
                    case 'Artifacts':
                      _jumpTo(_kArtifacts);
                      break;
                    case 'Jobs':
                      _jumpTo(_kJobs);
                      break;
                    case 'Security':
                      _jumpTo(_kSecurity);
                      break;
                    case 'Limits':
                      _jumpTo(_kLimits);
                      break;
                    case 'Troubleshooting':
                      _jumpTo(_kTroubleshoot);
                      break;
                    case 'FAQ':
                      _jumpTo(_kFAQ);
                      break;
                    case 'Support':
                      _jumpTo(_kSupport);
                      break;
                  }
                },
              ),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeroHeader(
                            onTemplates: () => context.go('/templates'),
                          ),
                          const SizedBox(height: 16),

                          // Intro
                          _Section(
                            key: _kIntro,
                            title: 'What is Excelarator?',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Excelarator turns spreadsheets or schema JSON into production-ready assets '
                                  '(apps, schemas, data pipelines, and analytics packages). '
                                  'Upload an Excel/CSV or a Schema JSON (v1), choose a conversion, and receive a ZIP artifact.',
                                ),
                                SizedBox(height: 12),
                                _ImagePlaceholder(
                                  caption: 'Product overview diagram',
                                  aspect: 16 / 9,
                                  assetPath: 'assets/docs/overview_image.png',
                                ),
                              ],
                            ),
                          ),

                          // Spreadsheet conversions
                          _Section(
                            key: _kConversions,
                            title: 'Supported conversions (from spreadsheets)',
                            child: Column(
                              children: const [
                                _ConversionRow(
                                  icon: Icons.developer_board_outlined,
                                  title: 'Excel → Spring Boot + OpenAPI',
                                  bullets: [
                                    'Entities from sheets; fields from headers',
                                    'CRUD controllers, OpenAPI, tests, Dockerfile',
                                    'Flyway migrations and DB import included',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.table_chart_outlined,
                                  title: 'Excel → Database + Admin',
                                  bullets: [
                                    'DDL + optional seed data',
                                    'Ready-to-run admin UI (e.g., Postgres + AdminJS)',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.storage_outlined,
                                  title: 'Excel → Postgres Schema',
                                  bullets: [
                                    'High-quality Postgres DDL, constraints & indexes',
                                    'Optional seed / sample data loader',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.data_object_outlined,
                                  title:
                                      'Excel → Data Model + ORM + Migrations',
                                  bullets: [
                                    'ORM models, migrations, and README',
                                    'Popular stacks: Prisma, SQLAlchemy, JPA',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.swap_horiz_outlined,
                                  title: 'Excel → ETL / Workflow',
                                  bullets: [
                                    'Airflow / Temporal / GitHub Actions pipelines',
                                    'Idempotent ingestion and validations',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.analytics_outlined,
                                  title: 'Excel → Analytics Dashboard',
                                  bullets: [
                                    'Metabase / Superset / Looker Studio definitions',
                                    'Dashboards, dimensions, and metrics',
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Schema conversions
                          _Section(
                            key: _kSchemaConversions,
                            title:
                                'Supported conversions (from Schema JSON v1)',
                            child: Column(
                              children: const [
                                _ConversionRow(
                                  icon: Icons.developer_mode_outlined,
                                  title: 'Schema → Spring Boot + OpenAPI',
                                  bullets: [
                                    'Generates entities/controllers directly from the schema',
                                    'Flyway migration from JSON definition',
                                    'OpenAPI + README + Dockerfile',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.admin_panel_settings_outlined,
                                  title: 'Schema → Database + Admin',
                                  bullets: [
                                    'DDL from schema JSON',
                                    'AdminJS app pre-wired with relations and filters',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.schema_outlined,
                                  title: 'Schema → Postgres DDL',
                                  bullets: [
                                    'Tables, PK/FK, uniques, checks, enums',
                                    'Comments and useful indexes',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.polyline_outlined,
                                  title: 'Schema → ORM + Migrations',
                                  bullets: [
                                    'Prisma (default) or SQLAlchemy/JPA by template',
                                    'Idempotent seed + example queries',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.repeat_on_outlined,
                                  title: 'Schema → ETL / Workflow',
                                  bullets: [
                                    'Targets already-typed destination tables',
                                    'Validation & quality checks from schema constraints',
                                  ],
                                ),
                                _ConversionRow(
                                  icon: Icons.query_stats_outlined,
                                  title: 'Schema → Analytics Package',
                                  bullets: [
                                    'Modeled views (dim_*, fact_*) consistent with schema',
                                    'Metabase & Superset exports',
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Schema JSON v1 format
                          _Section(
                            key: _kSchemaFormat,
                            title:
                                'Excelarator Schema JSON (v1) – minimal shape',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Provide one JSON file describing your database: schemas, tables, columns, constraints, and indexes.',
                                ),
                                SizedBox(height: 8),
                                _CodeBlock(
                                  title: 'schema.json (excerpt)',
                                  code: '''{
        "version": "1",
        "schemas": [
      {
        "name": "public",
        "tables": [
          {
            "name": "customers",
            "columns": [
              {"name":"id","type":"uuid","nullable":false,"default":"uuid_generate_v4()"},
              {"name":"email","type":"varchar(255)","nullable":false, "unique": true},
              {"name":"created_at","type":"timestamptz","nullable":false,"default":"now()"}
            ],
            "primaryKey": ["id"],
            "foreignKeys": [],
            "checks": [],
            "indexes": [
              {"name":"idx_customers_email","columns":["email"],"unique":true}
            ],
            "comments": {"table":"Customer master","columns":{"email":"Login email"}}
          }
        ]
      }
        ],
        "enums": [
      {"name":"order_status","values":["NEW","PAID","SHIPPED","CANCELLED"],"schema":"public"}
        ]
      }''',
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Notes: types follow Postgres notation by default. Use snake_case for DB, camelCase can be generated in code. '
                                  'Unknowns can be omitted; generators will pick sensible defaults (e.g., FK indexes).',
                                ),
                              ],
                            ),
                          ),

                          // DB export tips
                          _Section(
                            key: _kDbExport,
                            title: 'Exporting your DB schema to JSON (tips)',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Run these locally (desktop) against your database and upload the resulting JSON on the “Upload Schema” screen.',
                                ),
                                SizedBox(height: 8),
                                _CodeBlock(
                                  title: 'PostgreSQL',
                                  code: '''# Requires psql + jq
      # Exports tables, columns, PK/FK, indexes, enums for the current DB
      psql '<DATABASE_URL>' -f scripts/pg_schema_dump.sql -At -F '\\t' | 
        node scripts/pg_to_excelarator.js > schema.json
      # (Replace with your own exporter; keep the JSON shape as in v1.)''',
                                ),
                                SizedBox(height: 8),
                                _CodeBlock(
                                  title: 'MySQL / MariaDB',
                                  code:
                                      '''# Requires mysql + a small Node/Python exporter
      mysqldump --no-data --routines --events <DATABASE_URL> > ddl.sql
      node scripts/mysql_to_excelarator.js ddl.sql > schema.json''',
                                ),
                                SizedBox(height: 8),
                                _CodeBlock(
                                  title:
                                      'SQL Server (sqlcmd) & Oracle (sqlplus)',
                                  code:
                                      '''# Extract metadata to CSV/JSON, then normalize:
      sqlcmd -S <SERVER> -d <DB> -i scripts/mssql_introspection.sql -s "," -W -o mssql_meta.csv
      python scripts/mssql_to_excelarator.py mssql_meta.csv > schema.json
      
      sqlplus <CONN_STR> @scripts/oracle_introspection.sql
      python scripts/oracle_to_excelarator.py oracle_meta.csv > schema.json''',
                                ),
                                SizedBox(height: 8),
                                _BulletList(
                                  items: [
                                    'Only metadata is needed (no data).',
                                    'Include schema name(s) for multi-tenant or namespaced DBs.',
                                    'Enums: use database enums or constrained lookups; both are supported.',
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // How it works
                          _Section(
                            key: _kHowItWorks,
                            title: 'How it works (high level)',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _NumberedText(
                                  items: [
                                    'Upload a spreadsheet (xlsx/csv) or a Schema JSON (v1).',
                                    'Queue job. Your backend prompt tells the model what to generate.',
                                    'Build artifact. The worker stores logs and a ZIP in Firebase Storage.',
                                    'Download & use. Jobs page provides status, logs, and the artifact.',
                                  ],
                                ),
                                SizedBox(height: 12),
                                _ImagePlaceholder(
                                  caption: 'Architecture diagram',
                                  aspect: 16 / 9,
                                  assetPath:
                                      'assets/docs/architecture_diagram.png',
                                ),
                              ],
                            ),
                          ),

                          // Using
                          _Section(
                            key: _kUsing,
                            title: 'Using Excelarator',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _StepCard(
                                  index: 1,
                                  title: 'Start a new conversion',
                                  body:
                                      'Go to New Conversion and upload an .xlsx/.csv (spreadsheets) or a schema.json (Schema v1). Then pick the desired conversion.',
                                  ctaText: 'Open New Conversion',
                                  route: '/convert',
                                ),
                                const SizedBox(height: 12),
                                const _StepCard(
                                  index: 2,
                                  title: 'Wait for the job to complete',
                                  body:
                                      'Track progress on the Jobs page. You can cancel or retry if needed.',
                                  ctaText: 'View Jobs',
                                  route: '/jobs',
                                ),
                                const SizedBox(height: 12),
                                const _StepCard(
                                  index: 3,
                                  title: 'Download the artifact',
                                  body:
                                      'Open the job detail, review logs if necessary, and download the ZIP (contains the full project or DDL files).',
                                ),
                                const SizedBox(height: 16),
                                const _CodeBlock(
                                  title:
                                      'Example: minimal backend prompt (Schema → Spring Boot)',
                                  code:
                                      '''ROLE: Generate a Spring Boot 3.x REST API from the attached Schema JSON (v1).
      INPUT: "schema.json" with schemas, tables, columns (types/nullability/defaults), PK/FK/unique/checks, indexes, enums.
      DELIVER: JPA entities, repositories, DTOs (+ validation), controllers, OpenAPI, Flyway V1__init.sql, application.yaml, README, Dockerfile. Return a single .zip.
      RULES: Respect PK/FK/unique/indexes. Prefer uuid PK if missing. Use timestamptz for datetime. Add indexes to all FKs.
      OUTPUT FORMAT: Start with FILE_TREE, then each file as a fenced code block, and include one ZIP with all artifacts.''',
                                ),
                              ],
                            ),
                          ),

                          // Artifacts
                          _Section(
                            key: _kArtifacts,
                            title:
                                'Artifacts & file trees (what you get in the ZIP)',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _ArtifactBlock(
                                  icon: Icons.developer_board_outlined,
                                  title:
                                      'Spring Boot + OpenAPI (from Excel or Schema)',
                                  bullets: [
                                    'Maven/Gradle project with entities/controllers',
                                    'Flyway migration V1__init.sql from your input',
                                    'OpenAPI via springdoc + Swagger UI',
                                  ],
                                  fileTree: '''spring-app/
        pom.xml
        src/main/java/... (entities, repos, controllers, mappers)
        src/main/resources/
      application.yaml
      db/migration/
        V1__init.sql
        Dockerfile
        README.md''',
                                ),
                                SizedBox(height: 8),
                                _ArtifactBlock(
                                  icon: Icons.admin_panel_settings_outlined,
                                  title:
                                      'Database + Admin (Postgres + AdminJS)',
                                  bullets: [
                                    'docker-compose.yml with Postgres + Admin',
                                    'DDL and optional seed',
                                    'AdminJS app wired with relations',
                                  ],
                                  fileTree: '''db-admin/
        docker-compose.yml
        db/
      init/
        01_schema.sql
        02_seed.sql
        admin/
      package.json
      src/index.ts
        README.md''',
                                ),
                                SizedBox(height: 8),
                                _ArtifactBlock(
                                  icon: Icons.schema_outlined,
                                  title: 'Postgres Schema (DDL-only)',
                                  bullets: [
                                    'High-quality DDL with checks, comments, indexes',
                                    'Optional 00_drop.sql guard',
                                  ],
                                  fileTree: '''ddl/
        00_drop.sql          # optional
        schema.sql
        README.md''',
                                ),
                                SizedBox(height: 8),
                                _ArtifactBlock(
                                  icon: Icons.data_object_outlined,
                                  title: 'ORM + Migrations (Prisma default)',
                                  bullets: [
                                    'schema.prisma + initial migration',
                                    'Seed script and example queries',
                                  ],
                                  fileTree: '''prisma-kit/
        package.json
        prisma/
      schema.prisma
      migrations/
        2025xxxx_init/
          migration.sql
      seed.ts
        src/examples.ts
        .env.example
        README.md''',
                                ),
                                SizedBox(height: 8),
                                _ArtifactBlock(
                                  icon: Icons.autorenew_outlined,
                                  title: 'ETL / Workflow (Airflow)',
                                  bullets: [
                                    'Docker Compose for Airflow + Postgres (local dev)',
                                    'DAG with extract→validate→transform→load→checks→notify',
                                  ],
                                  fileTree: '''airflow/
        docker-compose.yml
        dags/ingest_excelarator.py
        sql/
      ddl.sql
      quality_checks.sql
        README.md''',
                                ),
                                SizedBox(height: 8),
                                _ArtifactBlock(
                                  icon: Icons.query_stats_outlined,
                                  title:
                                      'Analytics Package (Metabase + Superset)',
                                  bullets: [
                                    'Portable SQL modeling views (dim_*, fact_*, v_*)',
                                    'Metabase export & Superset import bundle',
                                  ],
                                  fileTree: '''analytics/
        sql/modeling/
      dim_date.sql
      fact_orders.sql
      v_orders_enriched.sql
        metabase_export.json
        superset/
      datasets.yaml
      dashboard.json
        metrics.md
        README.md''',
                                ),
                              ],
                            ),
                          ),

                          // Jobs
                          _Section(
                            key: _kJobs,
                            title: 'Jobs, statuses & artifacts',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Statuses: Pending → Running → Succeeded | Failed | Canceled.',
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Artifacts: A single ZIP is produced and stored; the job detail page exposes a download button.',
                                ),
                                SizedBox(height: 12),
                                _ImagePlaceholder(
                                  caption: 'Job detail screen',
                                  aspect: 16 / 9,
                                  assetPath: 'assets/docs/job_details_page.png',
                                ),
                              ],
                            ),
                          ),

                          // Security
                          _Section(
                            key: _kSecurity,
                            title: 'Security & privacy',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _BulletList(
                                  items: [
                                    'Files are private by default.',
                                    'Artifacts & logs are retained briefly.',
                                    'Credentials (if any) are not kept in our database.',
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Limits
                          _Section(
                            key: _kLimits,
                            title: 'Limits & performance',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _BulletList(
                                  items: [
                                    'Recommended: ≤ 50 MB per spreadsheet or schema upload for best latency.',
                                    'Very large schemas may be split across multiple jobs.',
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Troubleshooting
                          _Section(
                            key: _kTroubleshoot,
                            title: 'Troubleshooting',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _FAQ(
                                  q: 'My job is stuck in Pending.',
                                  a: 'Make sure the worker is running and watching for pending jobs. Verify System Status, if the system in down retry some minutes later.',
                                ),
                                _FAQ(
                                  q: 'Artifact says “No artifact available”.',
                                  a: 'Open the job detail and inspect logs. If failed, click Retry, some jobs can take several minutes, and in some cases hours.',
                                ),
                                _FAQ(
                                  q: 'Schema types were interpreted incorrectly.',
                                  a: 'Verify your Schema JSON (v1) column types and nullability. You can force exact SQL types in the JSON and the generators will honor them.',
                                ),
                              ],
                            ),
                          ),

                          // FAQ
                          _Section(
                            key: _kFAQ,
                            title: 'FAQ',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                _FAQ(
                                  q: 'Which analytics tools are supported?',
                                  a: 'Metabase, Apache Superset, and Looker Studio are supported out-of-the-box. Others can be added via custom prompt templates.',
                                ),
                                _FAQ(
                                  q: 'Can I bring my own model?',
                                  a: 'Not at this moment.',
                                ),
                              ],
                            ),
                          ),

                          // Support
                          _Section(
                            key: _kSupport,
                            title: 'Support & resources',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => context.go('/templates'),
                                  icon: const Icon(
                                    Icons.download_done_outlined,
                                  ),
                                  label: const Text('Sample templates'),
                                ),
                                if (isAdmin)
                                  OutlinedButton.icon(
                                    onPressed:
                                        () => context.go('/account/plan'),
                                    icon: const Icon(
                                      Icons.credit_card_outlined,
                                    ),
                                    label: const Text('Manage plan'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => context.go('/jobs'),
                                  icon: const Icon(Icons.history_outlined),
                                  label: const Text('Jobs'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Small building blocks ---

class _SideToc extends StatelessWidget {
  final void Function(String) onTap;
  const _SideToc({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = const [
      'Intro',
      'Spreadsheet conversions',
      'Schema conversions',
      'Schema JSON (v1)',
      'DB export tips',
      'How it works',
      'Using Excelarator',
      'Artifacts',
      'Jobs',
      'Security',
      'Limits',
      'Troubleshooting',
      'FAQ',
      'Support',
    ];
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: cs.outline.withOpacity(0.2))),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder:
            (_, i) => ListTile(
              dense: true,
              title: Text(items[i]),
              leading: const Icon(Icons.chevron_right),
              onTap: () => onTap(items[i]),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final VoidCallback onTemplates;
  const _HeroHeader({required this.onTemplates});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Excelarator Docs',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Everything you need to go from spreadsheets or schema JSON to running systems.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => context.go('/convert'),
                icon: const Icon(Icons.auto_awesome_motion_outlined),
                label: const Text('Start converting'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/jobs'),
                icon: const Icon(Icons.history),
                label: const Text('View my jobs'),
              ),
              OutlinedButton.icon(
                onPressed: onTemplates,
                icon: const Icon(Icons.download_done_outlined),
                label: const Text('Sample templates'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final String caption;
  final double aspect;
  final String? assetPath; // NEW

  const _ImagePlaceholder({
    required this.caption,
    required this.aspect,
    this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget framed(Widget child) => Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        border: Border.all(color: cs.outline.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: aspect,
          child:
              assetPath == null
                  ? framed(
                    const Center(child: Icon(Icons.image_outlined, size: 48)),
                  )
                  : framed(
                    Image.asset(
                      assetPath!,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined, size: 40),
                          ),
                    ),
                  ),
        ),
        const SizedBox(height: 6),
        Text(caption, style: TextStyle(color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _ConversionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> bullets;
  const _ConversionRow({
    required this.icon,
    required this.title,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: bullets.map((b) => Text('• $b')).toList(),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
    );
  }
}

class _NumberedText extends StatelessWidget {
  final List<String> items;
  const _NumberedText({required this.items});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}. ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Expanded(child: Text(items[i])),
              ],
            ),
          ),
      ],
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList({required this.items});
  @override
  Widget build(BuildContext context) {
    return Column(
      children:
          items
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [const Text('• '), Expanded(child: Text(e))],
                  ),
                ),
              )
              .toList(),
    );
  }
}

class _FAQ extends StatelessWidget {
  final String q, a;
  const _FAQ({required this.q, required this.a});
  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700)),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(alignment: Alignment.centerLeft, child: Text(a)),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  final int index;
  final String title;
  final String body;
  final String? ctaText;
  final String? route;
  const _StepCard({
    required this.index,
    required this.title,
    required this.body,
    this.ctaText,
    this.route,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primary.withOpacity(0.2),
            child: Text(
              '$index',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(body),
                if (ctaText != null && route != null) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => context.go(route!),
                    child: Text(ctaText!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String title;
  final String code;
  const _CodeBlock({required this.title, required this.code});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outline.withOpacity(0.25)),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(fontFamily: 'monospace', height: 1.3),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filledTonal(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_all),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ArtifactBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> bullets;
  final String fileTree;
  const _ArtifactBlock({
    required this.icon,
    required this.title,
    required this.bullets,
    required this.fileTree,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...bullets.map((b) => Text('• $b')),
          const SizedBox(height: 8),
          _CodeBlock(title: 'FILE_TREE (excerpt)', code: fileTree),
        ],
      ),
    );
  }
}
