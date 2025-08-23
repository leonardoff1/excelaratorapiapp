// reverse_engineer_db_page.dart
// Client-side DB connection + discovery (PostgreSQL MVP), schema JSON -> Firebase Storage,
// then Conversion + Job like the spreadsheet flow (always ZIP).
//
// Add to pubspec.yaml:
//   postgres: ^2.6.3
//   firebase_storage: ^12.3.1
//
// Notes:
// - Works on mobile/desktop. On web, raw DB sockets are not available; we show a hint.
// - PostgreSQL only for MVP. The UI warns for other vendors.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as storage;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:postgres/postgres.dart';

class ReverseEngineerDbPage extends StatefulWidget {
  const ReverseEngineerDbPage({super.key});

  @override
  State<ReverseEngineerDbPage> createState() => _ReverseEngineerDbPageState();
}

class _ReverseEngineerDbPageState extends State<ReverseEngineerDbPage> {
  // Wizard (0=Conn, 1=Discovery, 2=Package/Output, 3=Review & Submit)
  int _step = 0;
  bool _busy = false;

  // Connection
  String _dbType = 'PostgreSQL'; // MVP
  final _jdbcCtrl = TextEditingController(
    text: 'jdbc:postgresql://localhost:5432/mydb',
  );
  final _userCtrl = TextEditingController(text: 'postgres');
  final _pwdCtrl = TextEditingController();
  String? _connStatus; // success/error message
  String? _connHint; // platform hints (e.g., Android emulator 10.0.2.2)

  // Discovery
  bool _discovered = false;
  final Map<String, List<_TableItem>> _schemas = {}; // schema -> tables
  final Set<_TableRef> _selected = {}; // selected tables
  String _tableSearch = '';

  // Upload result
  String? _uploadedPath; // storage path (fullPath)
  String? _uploadedFileName; // schema-<ts>.json
  int? _uploadedSize;

  // Package / Output (always ZIP; just toggles like spreadsheet)
  String _output = 'spring'; // spring | schema | orm | etl | analytics | erd
  bool _includeDocker = true;
  bool _includeCICD = true;

  // Helpers
  String? get _orgId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return 'org-$uid';
  }

  void _next() {
    if (_step < 3) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  String _mapVendor(String ui) {
    switch (ui) {
      case 'PostgreSQL':
        return 'postgresql';
      default:
        return ui.toLowerCase();
    }
  }

  // ----- CLIENT-SIDE CONNECTION & DISCOVERY (PostgreSQL MVP) -----

  Future<void> _testConnectionLocal() async {
    if (kIsWeb) {
      setState(() {
        _connStatus =
            'Web platform can’t open DB sockets. Try mobile/desktop or expose DB via HTTPS tunnel.';
        _connHint = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _connStatus = null;
      _connHint = null;
    });

    try {
      if (_dbType != 'PostgreSQL') {
        setState(() {
          _connStatus = 'Only PostgreSQL supported in MVP (local client).';
          _connHint = 'Choose PostgreSQL, or wait for other vendors.';
        });
        return;
      }

      final pg = _parsePostgresJdbc(_jdbcCtrl.text.trim());
      final conn = PostgreSQLConnection(
        pg.host,
        pg.port,
        pg.db,
        username: _userCtrl.text.trim(),
        password: _pwdCtrl.text,
        useSSL: false,
        timeoutInSeconds: 6,
      );
      await conn.open();
      await conn.close();

      setState(() {
        _connStatus = 'Connection OK';
        _connHint = _platformHint();
      });
    } catch (e) {
      setState(() {
        _connStatus = 'Connection failed: $e';
        _connHint = _platformHint();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discoverLocal() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Web platform can’t open DB sockets. Use mobile/desktop.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _discovered = false;
      _schemas.clear();
      _selected.clear();
      _uploadedPath = null;
      _uploadedFileName = null;
      _uploadedSize = null;
    });

    try {
      if (_dbType != 'PostgreSQL') {
        throw Exception('Only PostgreSQL supported in MVP (local client).');
      }

      final pg = _parsePostgresJdbc(_jdbcCtrl.text.trim());
      final conn = PostgreSQLConnection(
        pg.host,
        pg.port,
        pg.db,
        username: _userCtrl.text.trim(),
        password: _pwdCtrl.text,
        useSSL: false,
        timeoutInSeconds: 10,
      );
      await conn.open();

      // 1) list tables by schema (exclude system)
      final rows = await conn.mappedResultsQuery('''
        SELECT t.table_schema, t.table_name
        FROM information_schema.tables t
        WHERE t.table_type='BASE TABLE'
          AND t.table_schema NOT IN ('pg_catalog','information_schema')
        ORDER BY t.table_schema, t.table_name;
      ''');

      final parsed = <String, List<_TableItem>>{};
      for (final r in rows) {
        final s = (r['t']!['table_schema'] as String).trim();
        final tn = (r['t']!['table_name'] as String).trim();

        // quick counts for UX chips
        final pkRows = await conn.mappedResultsQuery(
          '''
          SELECT kc.column_name
          FROM information_schema.table_constraints tc
          JOIN information_schema.key_column_usage kc
            ON kc.constraint_name = tc.constraint_name
           AND kc.constraint_schema = tc.constraint_schema
          WHERE tc.table_schema = @s
            AND tc.table_name   = @t
            AND tc.constraint_type = 'PRIMARY KEY'
          ORDER BY kc.ordinal_position;
        ''',
          substitutionValues: {'s': s, 't': tn},
        );

        final fkRows = await conn.mappedResultsQuery(
          '''
          SELECT kcu.column_name
          FROM information_schema.table_constraints AS tc
          JOIN information_schema.key_column_usage AS kcu
            ON kcu.constraint_name = tc.constraint_name
           AND kcu.constraint_schema = tc.constraint_schema
          WHERE tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_schema = @s
            AND tc.table_name   = @t;
        ''',
          substitutionValues: {'s': s, 't': tn},
        );

        final colRows = await conn.mappedResultsQuery(
          '''
          SELECT count(*) AS c
          FROM information_schema.columns
          WHERE table_schema = @s AND table_name = @t;
        ''',
          substitutionValues: {'s': s, 't': tn},
        );

        final item = _TableItem(
          tn,
          pk:
              pkRows
                  .map((e) => (e['kc']!['column_name'] as String).trim())
                  .toList(),
          fks: fkRows.length,
          cols: (colRows.first['']!['c'] as int),
        );

        parsed.putIfAbsent(s, () => <_TableItem>[]).add(item);
      }

      await conn.close();

      setState(() {
        _schemas.addAll(parsed);
        _discovered = true;
        _step = 1; // jump to Discovery
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Discovery failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extractAndUploadSchemaJson() async {
    final orgId = _orgId;
    if (orgId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in.')));
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one table.')),
      );
      return;
    }
    if (_dbType != 'PostgreSQL') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only PostgreSQL supported in MVP.')),
      );
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Web platform can’t open DB sockets. Use mobile/desktop.',
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final pg = _parsePostgresJdbc(_jdbcCtrl.text.trim());
      final conn = PostgreSQLConnection(
        pg.host,
        pg.port,
        pg.db,
        username: _userCtrl.text.trim(),
        password: _pwdCtrl.text,
        useSSL: false,
        timeoutInSeconds: 15,
      );
      await conn.open();

      // Build rich JSON for selected tables
      final Map<String, dynamic> root = {
        'vendor': _mapVendor(_dbType),
        'database': pg.db,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'schemas': <Map<String, dynamic>>[],
      };

      final bySchema = <String, List<_TableRef>>{};
      for (final ref in _selected) {
        bySchema.putIfAbsent(ref.schema, () => []).add(ref);
      }

      for (final entry in bySchema.entries) {
        final schemaName = entry.key;
        final tablesOut = <Map<String, dynamic>>[];

        for (final ref in entry.value) {
          final cols = await conn.mappedResultsQuery(
            '''
            SELECT column_name, data_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = @s AND table_name = @t
            ORDER BY ordinal_position;
          ''',
            substitutionValues: {'s': schemaName, 't': ref.table},
          );

          final pk = await conn.mappedResultsQuery(
            '''
            SELECT kc.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kc
              ON kc.constraint_name = tc.constraint_name
             AND kc.constraint_schema = tc.constraint_schema
            WHERE tc.table_schema = @s
              AND tc.table_name   = @t
              AND tc.constraint_type = 'PRIMARY KEY'
            ORDER BY kc.ordinal_position;
          ''',
            substitutionValues: {'s': schemaName, 't': ref.table},
          );

          final fks = await conn.mappedResultsQuery(
            '''
            SELECT
              kcu.column_name,
              ccu.table_schema  AS ref_schema,
              ccu.table_name    AS ref_table,
              ccu.column_name   AS ref_column
            FROM information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
              ON kcu.constraint_name = tc.constraint_name
             AND kcu.constraint_schema = tc.constraint_schema
            JOIN information_schema.constraint_column_usage AS ccu
              ON ccu.constraint_name = tc.constraint_name
             AND ccu.constraint_schema = tc.constraint_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND tc.table_schema = @s
              AND tc.table_name   = @t;
          ''',
            substitutionValues: {'s': schemaName, 't': ref.table},
          );

          final idx = await conn.mappedResultsQuery(
            '''
            SELECT i.indexname, i.indexdef
            FROM pg_indexes i
            WHERE i.schemaname = @s AND i.tablename = @t;
          ''',
            substitutionValues: {'s': schemaName, 't': ref.table},
          );

          tablesOut.add({
            'name': ref.table,
            'columns':
                cols
                    .map(
                      (r) => {
                        'name': (r['']!['column_name'] as String).trim(),
                        'type': (r['']!['data_type'] as String).trim(),
                        'nullable':
                            ((r['']!['is_nullable'] as String).toUpperCase() ==
                                'YES'),
                        'default': r['']!['column_default'],
                      },
                    )
                    .toList(),
            'primaryKey':
                pk
                    .map((r) => (r['kc']!['column_name'] as String).trim())
                    .toList(),
            'foreignKeys':
                fks
                    .map(
                      (r) => {
                        'column': (r['kcu']!['column_name'] as String).trim(),
                        'references': {
                          'schema': (r['ccu']!['ref_schema'] as String).trim(),
                          'table': (r['ccu']!['ref_table'] as String).trim(),
                          'column': (r['ccu']!['ref_column'] as String).trim(),
                        },
                      },
                    )
                    .toList(),
            'indexes':
                idx
                    .map(
                      (r) => {
                        'name': r['i']!['indexname'],
                        'definition': r['i']!['indexdef'],
                      },
                    )
                    .toList(),
          });
        }

        root['schemas'].add({'name': schemaName, 'tables': tablesOut});
      }

      await conn.close();

      // Upload JSON to Firebase Storage
      final jsonStr = const JsonEncoder.withIndent('  ').convert(root);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final fileName = 'schema-${DateTime.now().millisecondsSinceEpoch}.json';
      final path = 'orgs/$orgId/schemas/$fileName';

      final ref = storage.FirebaseStorage.instance.ref(path);
      await ref.putData(
        bytes,
        storage.SettableMetadata(contentType: 'application/json'),
      );

      setState(() {
        _uploadedPath = ref.fullPath; // relative path in bucket
        _uploadedFileName = fileName;
        _uploadedSize = bytes.length;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Schema JSON uploaded.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Extract/upload failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitJob() async {
    if (_uploadedPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload the schema JSON first (Extract & Upload).'),
        ),
      );
      return;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    final orgId = _orgId;
    if (authUser == null || orgId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You must be logged in.')));
      return;
    }

    setState(() => _busy = true);

    try {
      final now = FieldValue.serverTimestamp();
      final vendor = _mapVendor(_dbType);
      final def = _outputs.firstWhere((o) => o.id == _output);

      // Conversion (mirrors spreadsheet flow; source is JSON)
      final convRef = await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('conversions')
          .add({
            'name': 'Reverse $_dbType → ${def.title}',
            'description': 'Reverse-engineered via wizard (client-side)',
            'type': def.jobType,
            'templateKey': def.templateKey,
            'createdBy': authUser.uid,
            'orgId': orgId,
            'createdAt': now,
            'updatedAt': now,
            'database': {
              'connection': {
                'kind': vendor,
                'jdbc': _jdbcCtrl.text.trim(),
                'username': _userCtrl.text.trim(),
                'ssl': false,
              },
            },
            'selection': {
              'tables':
                  _selected
                      .map((e) => {'schema': e.schema, 'table': e.table})
                      .toList(),
            },
            // Keep "source" for parity with spreadsheet UI/worker expectations:
            'source': {
              'storagePath': _uploadedPath, // relative path in bucket
              'fileName': _uploadedFileName ?? 'schema.json',
              'sizeBytes': _uploadedSize,
              'contentType': 'application/json',
            },
            'package': {
              'target': 'ZIP Source',
              'docker': _includeDocker,
              'cicd': _includeCICD,
            },
          });

      // Job
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('jobs')
          .add({
            'name': 'Reverse $_dbType: ${def.title}',
            'type': def.jobType,
            'status': 'pending',
            'progress': 0.0,
            'conversionId': convRef.id,
            'userId': authUser.uid,
            'orgId': orgId,
            'createdAt': now,
            'updatedAt': now,
            'source': {
              'storagePath': _uploadedPath,
              'fileName': _uploadedFileName ?? 'schema.json',
              'contentType': 'application/json',
            },
          });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reverse-engineering started!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ----- UI -----

  @override
  void dispose() {
    _jdbcCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notPg = _dbType != 'PostgreSQL';

    return Scaffold(
      appBar: AppBar(title: const Text('Reverse-engineer database')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSide = constraints.maxWidth >= 1100;

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
                        onStepContinue: () async {
                          if (_step == 0) {
                            await _testConnectionLocal();
                            if (_connStatus?.contains('OK') == true) _next();
                          } else if (_step == 1) {
                            if (!_discovered) {
                              await _discoverLocal();
                            } else if (_uploadedPath == null) {
                              await _extractAndUploadSchemaJson();
                            } else {
                              _next();
                            }
                          } else if (_step == 2) {
                            _next();
                          } else if (_step == 3) {
                            await _submitJob();
                          }
                        },
                        onStepCancel: _back,
                        controlsBuilder: (context, details) {
                          final isLast = _step == 3;
                          return Row(
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    _busy ? null : details.onStepContinue,
                                icon:
                                    _busy
                                        ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : Icon(
                                          isLast
                                              ? Icons.build_outlined
                                              : Icons.arrow_forward,
                                        ),
                                label: Text(isLast ? 'Generate' : 'Next'),
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
                          // Step 0: Connection
                          Step(
                            title: const Text('Connection'),
                            state:
                                _connStatus == 'Connection OK'
                                    ? StepState.complete
                                    : StepState.indexed,
                            isActive: _step >= 0,
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _DbTypePicker(
                                  value: _dbType,
                                  onChanged: (v) => setState(() => _dbType = v),
                                ),
                                if (notPg)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 6,
                                      bottom: 6,
                                    ),
                                    child: _WarnBanner(
                                      text:
                                          'Local discovery supports PostgreSQL in this MVP. Choose PostgreSQL or continue at your own risk.',
                                    ),
                                  ),
                                TextFormField(
                                  controller: _jdbcCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'JDBC URL',
                                    prefixIcon: Icon(Icons.link),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _userCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'User',
                                          prefixIcon: Icon(Icons.person),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _pwdCtrl,
                                        obscureText: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Password',
                                          prefixIcon: Icon(Icons.lock),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed:
                                          _busy ? null : _testConnectionLocal,
                                      icon: const Icon(Icons.bolt),
                                      label: const Text('Test connection'),
                                    ),
                                    const SizedBox(width: 12),
                                    if (_connStatus != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (_connStatus!.contains('OK')
                                                  ? Colors.green
                                                  : Colors.red)
                                              .withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: (_connStatus!.contains('OK')
                                                    ? Colors.green
                                                    : Colors.red)
                                                .withOpacity(0.30),
                                          ),
                                        ),
                                        child: Text(
                                          _connStatus!,
                                          style: TextStyle(
                                            color:
                                                _connStatus!.contains('OK')
                                                    ? Colors.green.shade700
                                                    : Colors.red.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (_connHint != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _connHint!,
                                    style: TextStyle(
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Step 1: Discovery (and upload)
                          Step(
                            title: const Text('Discovery'),
                            isActive: _step >= 1,
                            state:
                                (_uploadedPath != null)
                                    ? StepState.complete
                                    : (_discovered
                                        ? StepState.editing
                                        : StepState.indexed),
                            content: _DiscoveryStep(
                              schemas: _schemas,
                              discovered: _discovered,
                              busy: _busy,
                              selected: _selected,
                              tableSearch: _tableSearch,
                              onSearch: (s) => setState(() => _tableSearch = s),
                              onToggle: (schema, item, checked) {
                                setState(() {
                                  final ref = _TableRef(schema, item.name);
                                  if (checked) {
                                    _selected.add(ref);
                                  } else {
                                    _selected.remove(ref);
                                  }
                                });
                              },
                              onToggleAllSchema: (schema, checked) {
                                setState(() {
                                  for (final t
                                      in _schemas[schema] ?? const []) {
                                    final ref = _TableRef(schema, t.name);
                                    if (checked) {
                                      _selected.add(ref);
                                    } else {
                                      _selected.remove(ref);
                                    }
                                  }
                                });
                              },
                              onDiscover: _discoverLocal,
                              onUpload: _extractAndUploadSchemaJson,
                              uploadedPath: _uploadedPath,
                              uploadedFileName: _uploadedFileName,
                              dbType: _dbType,
                            ),
                          ),

                          // Step 2: Package / Output (like spreadsheet)
                          Step(
                            title: const Text('Package & Output'),
                            isActive: _step >= 2,
                            state: StepState.indexed,
                            content: _PackageStep(
                              output: _output,
                              includeDocker: _includeDocker,
                              includeCICD: _includeCICD,
                              onChanged:
                                  (o, d, c) => setState(() {
                                    _output = o;
                                    _includeDocker = d;
                                    _includeCICD = c;
                                  }),
                            ),
                          ),

                          // Step 3: Review & Submit
                          Step(
                            title: const Text('Review & Submit'),
                            isActive: _step >= 3,
                            state:
                                _busy ? StepState.editing : StepState.indexed,
                            content: _ReviewCard(
                              dbType: _dbType,
                              jdbc: _jdbcCtrl.text,
                              selectedCount: _selected.length,
                              uploadedPath: _uploadedPath,
                              output:
                                  _outputs
                                      .firstWhere((o) => o.id == _output)
                                      .title,
                              includeDocker: _includeDocker,
                              includeCICD: _includeCICD,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              if (showSide) const SizedBox(width: 8),

              // Side Summary
              if (showSide)
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
                    child: _SummaryCard(
                      dbType: _dbType,
                      jdbc: _jdbcCtrl.text,
                      selectedCount: _selected.length,
                      schemas: _schemas,
                      chosen: _selected,
                      output: _outputs.firstWhere((o) => o.id == _output).title,
                      options: [
                        'ZIP',
                        if (_includeDocker) 'Dockerfile',
                        if (_includeCICD) 'CI/CD',
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // Platform hint for localhost nuances
  String _platformHint() {
    return '''
Tips:
• Android emulator: use 10.0.2.2 instead of localhost for host machine DB.
• iOS simulator: localhost works but ensure port is exposed.
• Desktop: localhost connects to local OS normally.
'''.trim();
  }

  // JDBC parser (PostgreSQL)
  _PgParts _parsePostgresJdbc(String jdbc) {
    // Accept jdbc:postgresql://host:port/db?...  → strip "jdbc:"
    final uri = Uri.parse(jdbc.replaceFirst(RegExp('^jdbc:'), ''));
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = (uri.port > 0) ? uri.port : 5432;
    final db = (uri.pathSegments.isNotEmpty) ? uri.pathSegments.first : '';
    return _PgParts(host: host, port: port, db: db);
  }
}

class _PgParts {
  final String host;
  final int port;
  final String db;
  _PgParts({required this.host, required this.port, required this.db});
}

// ====== Small pieces ======

class _DbTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _DbTypePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = const [
      'PostgreSQL',
      'MySQL',
      'SQL Server',
      'Oracle',
      'SQLite',
    ];
    return DropdownButtonFormField<String>(
      value: value,
      items:
          items.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
      onChanged: (v) => onChanged(v ?? 'PostgreSQL'),
      decoration: const InputDecoration(labelText: 'Database'),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  final String text;
  const _WarnBanner({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.error.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.error),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: cs.error))),
        ],
      ),
    );
  }
}

// ===== Models =====
class _TableItem {
  final String name;
  final List<String> pk;
  final int fks;
  final int cols;
  _TableItem(this.name, {this.pk = const [], this.fks = 0, this.cols = 0});
}

class _TableRef {
  final String schema;
  final String table;
  const _TableRef(this.schema, this.table);
  @override
  bool operator ==(Object other) =>
      other is _TableRef && other.schema == schema && other.table == table;
  @override
  int get hashCode => Object.hash(schema, table);
}

class _OutputDef {
  final String id; // spring|schema|orm|etl|analytics|erd
  final String title;
  final String subtitle;
  final IconData icon;
  final String jobType;
  final String templateKey;
  const _OutputDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.jobType,
    required this.templateKey,
  });
}

const List<_OutputDef> _outputs = [
  _OutputDef(
    id: 'spring',
    title: 'Spring Boot + OpenAPI',
    subtitle: 'Entities, Repos, CRUD, OpenAPI, tests',
    icon: Icons.api_outlined,
    jobType: 'reverseDbToSpring',
    templateKey: 'reverse-db/springboot',
  ),
  _OutputDef(
    id: 'schema',
    title: 'Postgres DDL',
    subtitle: 'Portable DDL (tables, constraints, indexes)',
    icon: Icons.dataset_linked_outlined,
    jobType: 'reverseDbToPostgresSchema',
    templateKey: 'reverse-db/postgres-ddl',
  ),
  _OutputDef(
    id: 'orm',
    title: 'ORM + Migrations',
    subtitle: 'JPA/Prisma/SQLAlchemy project',
    icon: Icons.data_object,
    jobType: 'reverseDbToOrm',
    templateKey: 'reverse-db/orm',
  ),
  _OutputDef(
    id: 'etl',
    title: 'ETL / Workflow',
    subtitle: 'Airflow/Temporal pipelines',
    icon: Icons.swap_horiz,
    jobType: 'reverseDbToEtl',
    templateKey: 'reverse-db/etl',
  ),
  _OutputDef(
    id: 'analytics',
    title: 'Analytics Package',
    subtitle: 'Metabase/Superset starter',
    icon: Icons.analytics_outlined,
    jobType: 'reverseDbToAnalytics',
    templateKey: 'reverse-db/analytics',
  ),
  _OutputDef(
    id: 'erd',
    title: 'ERD / DBML',
    subtitle: 'DBML + Mermaid diagrams',
    icon: Icons.account_tree_outlined,
    jobType: 'reverseDbToErd',
    templateKey: 'reverse-db/erd',
  ),
];

// ===== Discovery UI =====
class _DiscoveryStep extends StatelessWidget {
  final Map<String, List<_TableItem>> schemas;
  final bool discovered;
  final bool busy;
  final Set<_TableRef> selected;
  final String tableSearch;
  final ValueChanged<String> onSearch;
  final void Function(String schema, _TableItem table, bool checked) onToggle;
  final void Function(String schema, bool checked) onToggleAllSchema;
  final VoidCallback onDiscover;
  final VoidCallback onUpload;
  final String? uploadedPath;
  final String? uploadedFileName;
  final String dbType;

  const _DiscoveryStep({
    required this.schemas,
    required this.discovered,
    required this.busy,
    required this.selected,
    required this.tableSearch,
    required this.onSearch,
    required this.onToggle,
    required this.onToggleAllSchema,
    required this.onDiscover,
    required this.onUpload,
    required this.uploadedPath,
    required this.uploadedFileName,
    required this.dbType,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onDiscover,
              icon: const Icon(Icons.search),
              label: const Text('Discover tables'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed:
                  busy || !discovered || selected.isEmpty ? null : onUpload,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Extract & Upload schema JSON'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (uploadedPath != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.secondary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.secondary.withOpacity(0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: cs.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Uploaded: ${uploadedFileName ?? 'schema.json'}\n$uploadedPath',
                  ),
                ),
              ],
            ),
          ),
        if (!discovered) ...[
          const SizedBox(height: 10),
          Text(
            'Click "Discover tables" to fetch schemas and tables from $dbType.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
        if (discovered) ...[
          const SizedBox(height: 12),
          TextField(
            onChanged: onSearch,
            decoration: const InputDecoration(
              labelText: 'Search tables',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          ..._renderSchemas(context),
        ],
      ],
    );
  }

  List<Widget> _renderSchemas(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final schemaNames = schemas.keys.toList()..sort();
    return schemaNames.map((schema) {
      final tables = schemas[schema]!;
      final visible = tables.where((t) => _match(t.name, tableSearch)).toList();
      final allSelected =
          visible.isNotEmpty &&
          visible.every((t) => selected.contains(_TableRef(schema, t.name)));
      final anySelected = visible.any(
        (t) => selected.contains(_TableRef(schema, t.name)),
      );

      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: allSelected,
                    tristate: !allSelected && anySelected,
                    onChanged:
                        (v) => onToggleAllSchema(
                          schema,
                          !(allSelected && !anySelected),
                        ),
                  ),
                  Text(
                    schema,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${visible.length} tables',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...visible.map((t) {
                final ref = _TableRef(schema, t.name);
                final checked = selected.contains(ref);
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: checked,
                    onChanged: (v) => onToggle(schema, t, v ?? false),
                  ),
                  title: Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'PK: ${t.pk.isEmpty ? '—' : t.pk.join(', ')} · FKs: ${t.fks} · Cols: ${t.cols}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    }).toList();
  }

  bool _match(String name, String q) {
    if (q.trim().isEmpty) return true;
    return name.toLowerCase().contains(q.toLowerCase());
  }
}

// ===== Package/Output (like spreadsheet) =====
class _PackageStep extends StatelessWidget {
  final String output;
  final bool includeDocker;
  final bool includeCICD;
  final void Function(String output, bool docker, bool cicd) onChanged;

  const _PackageStep({
    required this.output,
    required this.includeDocker,
    required this.includeCICD,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose what to generate',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              _outputs.map((o) {
                final selected = o.id == output;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(o.id, includeDocker, includeCICD),
                  child: Container(
                    width: min(MediaQuery.of(context).size.width - 64, 320),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? cs.primaryContainer.withOpacity(0.45)
                              : cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (selected ? cs.primary : cs.outline).withOpacity(
                          selected ? 0.6 : 0.35,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          o.icon,
                          color: selected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color:
                                      selected ? cs.onPrimaryContainer : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                o.subtitle,
                                style: TextStyle(color: cs.onSurfaceVariant),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 12),
        const Divider(),
        Text('Packaging', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'ZIP file (always).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SwitchListTile(
          value: includeDocker,
          onChanged: (v) => onChanged(output, v, includeCICD),
          title: const Text('Include Dockerfile'),
        ),
        SwitchListTile(
          value: includeCICD,
          onChanged: (v) => onChanged(output, includeDocker, v),
          title: const Text('Include GitHub Action (CI/CD)'),
        ),
      ],
    );
  }
}

// ===== Review card =====
class _ReviewCard extends StatelessWidget {
  final String dbType, jdbc, output;
  final int selectedCount;
  final String? uploadedPath;
  final bool includeDocker, includeCICD;

  const _ReviewCard({
    required this.dbType,
    required this.jdbc,
    required this.selectedCount,
    required this.uploadedPath,
    required this.output,
    required this.includeDocker,
    required this.includeCICD,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Database', dbType),
            _kv('JDBC', jdbc),
            _kv('Tables', '$selectedCount selected'),
            _kv('Schema JSON', uploadedPath ?? '— (extract & upload first)'),
            _kv('Output', output),
            _kv(
              'Packaging',
              'ZIP · ${includeDocker ? "Dockerfile" : "no Docker"} · ${includeCICD ? "CI/CD" : "no CI/CD"}',
            ),
            const SizedBox(height: 8),
            if (uploadedPath == null)
              Text(
                'Tip: Click "Extract & Upload schema JSON" in Discovery step.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(v, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

// ===== Summary side =====
class _SummaryCard extends StatelessWidget {
  final String dbType, jdbc, output;
  final int selectedCount;
  final Map<String, List<_TableItem>> schemas;
  final Set<_TableRef> chosen;
  final List<String> options;

  const _SummaryCard({
    required this.dbType,
    required this.jdbc,
    required this.selectedCount,
    required this.schemas,
    required this.chosen,
    required this.output,
    required this.options,
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
            _kv('Database', dbType),
            _kv('JDBC', jdbc.isEmpty ? '—' : jdbc),
            _kv('Tables', '$selectedCount selected'),
            _kv('Output', output),
            _kv('Package', options.join(' · ')),
            const SizedBox(height: 12),
            Text('Selection', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline.withOpacity(0.24)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      schemas.entries.map((e) {
                        final chosenInSchema =
                            e.value
                                .where(
                                  (t) =>
                                      chosen.contains(_TableRef(e.key, t.name)),
                                )
                                .toList();
                        if (chosenInSchema.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Text(
                                '${e.key}:',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              ...chosenInSchema.map(
                                (t) => Chip(
                                  label: Text(t.name),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                ),
              ),
            ),
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
