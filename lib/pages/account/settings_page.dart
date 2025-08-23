import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  bool _saving = false;

  // ---------- Derived ids ----------
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  String? get _orgId {
    final u = _uid;
    if (u == null) return null;
    return 'org-$u';
  }

  // ---------- User settings (users/{uid}/settings) ----------
  String _theme = 'system'; // system | light | dark
  bool _compact = false;
  bool _reduceMotion = false;

  String _defaultInput = 'excel'; // excel | schema
  String _defaultConversion = 'excel_spring'; // see drop-down list below
  String _defaultGptAlias = 'excelToSpring'; // example
  String _defaultPackaging = 'zip'; // zip | docker | cdk

  bool _notifJobStarted = false;
  bool _notifJobSucceeded = true;
  bool _notifJobFailed = true;
  bool _notifWeeklyDigest = false;

  bool _verboseLogs = false;
  bool _devControls = false;

  // ---------- Org settings (orgs/{orgId}/settings) ----------
  bool _autoDeleteArtifacts = false;
  int _retentionDays = 7;

  bool _integrationGithub = false;
  String _githubRepo = '';
  String _githubBranch = 'main';
  String _webhookUrl = ''; // generic outbound webhook

  bool _telemetryOptIn = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final uid = _uid;
    final orgId = _orgId;
    if (uid == null || orgId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final fs = FirebaseFirestore.instance;

      final userSet =
          await fs
              .collection('users')
              .doc(uid)
              .collection('meta')
              .doc('settings')
              .get();
      final orgSet =
          await fs
              .collection('orgs')
              .doc(orgId)
              .collection('meta')
              .doc('settings')
              .get();

      if (userSet.exists) {
        final m = userSet.data()!;
        _theme = (m['theme'] ?? _theme).toString();
        _compact = m['compact'] == true;
        _reduceMotion = m['reduceMotion'] == true;

        _defaultInput = (m['defaultInput'] ?? _defaultInput).toString();
        _defaultConversion =
            (m['defaultConversion'] ?? _defaultConversion).toString();
        _defaultGptAlias =
            (m['defaultGptAlias'] ?? _defaultGptAlias).toString();
        _defaultPackaging =
            (m['defaultPackaging'] ?? _defaultPackaging).toString();

        _notifJobStarted = m['notifJobStarted'] == true;
        _notifJobSucceeded = m['notifJobSucceeded'] != false; // default on
        _notifJobFailed = m['notifJobFailed'] != false; // default on
        _notifWeeklyDigest = m['notifWeeklyDigest'] == true;

        _verboseLogs = m['verboseLogs'] == true;
        _devControls = m['devControls'] == true;
      }

      if (orgSet.exists) {
        final m = orgSet.data()!;
        _autoDeleteArtifacts = m['autoDeleteArtifacts'] == true;
        _retentionDays =
            (m['retentionDays'] is num)
                ? (m['retentionDays'] as num).toInt()
                : _retentionDays;

        _integrationGithub = m['integrationGithub'] == true;
        _githubRepo = (m['githubRepo'] ?? '').toString();
        _githubBranch = (m['githubBranch'] ?? 'main').toString();
        _webhookUrl = (m['webhookUrl'] ?? '').toString();

        _telemetryOptIn = m['telemetryOptIn'] == true;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final uid = _uid;
    final orgId = _orgId;
    if (uid == null || orgId == null) return;

    setState(() => _saving = true);
    final now = FieldValue.serverTimestamp();

    try {
      final fs = FirebaseFirestore.instance;

      await fs
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('settings')
          .set({
            'theme': _theme,
            'compact': _compact,
            'reduceMotion': _reduceMotion,
            'defaultInput': _defaultInput,
            'defaultConversion': _defaultConversion,
            'defaultGptAlias': _defaultGptAlias,
            'defaultPackaging': _defaultPackaging,
            'notifJobStarted': _notifJobStarted,
            'notifJobSucceeded': _notifJobSucceeded,
            'notifJobFailed': _notifJobFailed,
            'notifWeeklyDigest': _notifWeeklyDigest,
            'verboseLogs': _verboseLogs,
            'devControls': _devControls,
            'updatedAt': now,
            'createdAt': now,
          }, SetOptions(merge: true));

      await fs
          .collection('orgs')
          .doc(orgId)
          .collection('meta')
          .doc('settings')
          .set({
            'autoDeleteArtifacts': _autoDeleteArtifacts,
            'retentionDays': _retentionDays,
            'integrationGithub': _integrationGithub,
            'githubRepo': _githubRepo.trim(),
            'githubBranch': _githubBranch.trim(),
            'webhookUrl': _webhookUrl.trim(),
            'telemetryOptIn': _telemetryOptIn,
            'updatedAt': now,
            'createdAt': now,
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
            onPressed: _saving ? null : _save,
            icon:
                _saving
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                      children: [
                        _appearanceCard(context),
                        const SizedBox(height: 12),
                        _defaultsCard(context),
                        const SizedBox(height: 12),
                        _notificationsCard(context),
                        const SizedBox(height: 12),
                        _artifactsCard(context),
                        const SizedBox(height: 12),
                        _integrationsCard(context),
                        const SizedBox(height: 12),
                        _privacyCard(context),
                        const SizedBox(height: 12),
                        _advancedCard(context),
                        const SizedBox(height: 12),
                        _dangerCard(context),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  // ===== Sections =====

  Widget _appearanceCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appearance',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _theme,
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System')),
                DropdownMenuItem(value: 'light', child: Text('Light')),
                DropdownMenuItem(value: 'dark', child: Text('Dark')),
              ],
              onChanged: (v) => setState(() => _theme = v ?? 'system'),
              decoration: const InputDecoration(labelText: 'Theme'),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              value: _compact,
              onChanged: (v) => setState(() => _compact = v),
              title: const Text('Compact mode'),
              secondary: Icon(Icons.format_line_spacing, color: cs.primary),
            ),
            SwitchListTile(
              value: _reduceMotion,
              onChanged: (v) => setState(() => _reduceMotion = v),
              title: const Text('Reduce motion'),
              secondary: Icon(
                Icons.motion_photos_off_outlined,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultsCard(BuildContext context) {
    final conversions = const [
      // Excel flows
      DropdownMenuItem(
        value: 'excel_spring',
        child: Text('Excel → Spring Boot + OpenAPI'),
      ),
      DropdownMenuItem(
        value: 'excel_db_admin',
        child: Text('Excel → Database + Admin'),
      ),
      DropdownMenuItem(
        value: 'excel_schema',
        child: Text('Excel → Postgres Schema'),
      ),
      DropdownMenuItem(
        value: 'excel_orm',
        child: Text('Excel → Data Model + ORM + Migrations'),
      ),
      DropdownMenuItem(
        value: 'excel_etl',
        child: Text('Excel → ETL / Workflow'),
      ),
      DropdownMenuItem(
        value: 'excel_analytics',
        child: Text('Excel → Analytics Dashboard'),
      ),
      // Schema flows
      DropdownMenuItem(
        value: 'schema_spring',
        child: Text('Schema → Spring Boot + OpenAPI'),
      ),
      DropdownMenuItem(
        value: 'schema_db_admin',
        child: Text('Schema → Database + Admin'),
      ),
      DropdownMenuItem(
        value: 'schema_schema',
        child: Text('Schema → Postgres Schema'),
      ),
      DropdownMenuItem(
        value: 'schema_orm',
        child: Text('Schema → Data Model + ORM + Migrations'),
      ),
      DropdownMenuItem(
        value: 'schema_etl',
        child: Text('Schema → ETL / Workflow'),
      ),
      DropdownMenuItem(
        value: 'schema_analytics',
        child: Text('Schema → Analytics Dashboard'),
      ),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Defaults',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _defaultInput,
              items: const [
                DropdownMenuItem(value: 'excel', child: Text('Excel / CSV')),
                DropdownMenuItem(value: 'schema', child: Text('Schema JSON')),
              ],
              onChanged: (v) => setState(() => _defaultInput = v ?? 'excel'),
              decoration: const InputDecoration(
                labelText: 'Default input type',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _defaultConversion,
              items: conversions,
              onChanged:
                  (v) => setState(
                    () => _defaultConversion = v ?? _defaultConversion,
                  ),
              decoration: const InputDecoration(
                labelText: 'Default conversion',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _defaultGptAlias,
              onChanged: (v) => _defaultGptAlias = v.trim(),
              decoration: const InputDecoration(
                labelText: 'Default GPT alias (backend)',
                helperText:
                    'Alias resolved server-side (e.g., excelToSpring, schemaToSpring).',
                prefixIcon: Icon(Icons.smart_toy_outlined),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _defaultPackaging,
              items: const [
                DropdownMenuItem(value: 'zip', child: Text('ZIP (default)')),
                DropdownMenuItem(value: 'docker', child: Text('Docker image')),
                DropdownMenuItem(value: 'cdk', child: Text('AWS CDK stack')),
              ],
              onChanged: (v) => setState(() => _defaultPackaging = v ?? 'zip'),
              decoration: const InputDecoration(labelText: 'Default packaging'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _notifJobStarted,
              onChanged: (v) => setState(() => _notifJobStarted = v),
              title: const Text('Job started'),
              secondary: Icon(Icons.play_circle_outline, color: cs.primary),
            ),
            SwitchListTile(
              value: _notifJobSucceeded,
              onChanged: (v) => setState(() => _notifJobSucceeded = v),
              title: const Text('Job succeeded'),
              secondary: Icon(Icons.check_circle_outline, color: cs.primary),
            ),
            SwitchListTile(
              value: _notifJobFailed,
              onChanged: (v) => setState(() => _notifJobFailed = v),
              title: const Text('Job failed'),
              secondary: Icon(Icons.error_outline, color: cs.primary),
            ),
            SwitchListTile(
              value: _notifWeeklyDigest,
              onChanged: (v) => setState(() => _notifWeeklyDigest = v),
              title: const Text('Weekly digest'),
              secondary: Icon(Icons.calendar_month_outlined, color: cs.primary),
            ),
            const SizedBox(height: 6),
            Text(
              'Delivery channel depends on your backend (email, Slack webhook, etc.).',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artifactsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Artifacts & storage (org)',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _autoDeleteArtifacts,
              onChanged: (v) => setState(() => _autoDeleteArtifacts = v),
              title: const Text('Auto-delete artifacts'),
              subtitle: const Text('Deletes ZIPs after retention period'),
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _retentionDays.toDouble(),
                    min: 1,
                    max: 60,
                    divisions: 59,
                    label: '$_retentionDays days',
                    onChanged:
                        (v) => setState(() => _retentionDays = v.round()),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    '$_retentionDays d',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _integrationsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Integrations (org)',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _integrationGithub,
              onChanged: (v) => setState(() => _integrationGithub = v),
              title: const Text('Enable GitHub export'),
              secondary: Icon(Icons.cloud_upload_outlined, color: cs.primary),
            ),
            TextFormField(
              enabled: _integrationGithub,
              initialValue: _githubRepo,
              onChanged: (v) => _githubRepo = v,
              decoration: const InputDecoration(
                labelText: 'Repository (org/repo)',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              enabled: _integrationGithub,
              initialValue: _githubBranch,
              onChanged: (v) => _githubBranch = v,
              decoration: const InputDecoration(
                labelText: 'Branch',
                prefixIcon: Icon(Icons.account_tree_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _webhookUrl,
              onChanged: (v) => _webhookUrl = v,
              decoration: const InputDecoration(
                labelText: 'Webhook URL (optional)',
                helperText: 'Receive job events on your endpoint',
                prefixIcon: Icon(Icons.http_outlined),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Secrets (tokens, API keys) should be stored server-side or in Cloud Functions, not in client Firestore.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _privacyCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacy',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _telemetryOptIn,
              onChanged: (v) => setState(() => _telemetryOptIn = v),
              title: const Text('Share anonymous usage telemetry'),
            ),
            Text(
              'We only collect aggregate usage for quality & performance tuning. No spreadsheets or artifacts are sent.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Advanced',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _verboseLogs,
              onChanged: (v) => setState(() => _verboseLogs = v),
              title: const Text('Verbose logs'),
              secondary: Icon(Icons.bug_report_outlined, color: cs.primary),
            ),
            SwitchListTile(
              value: _devControls,
              onChanged: (v) => setState(() => _devControls = v),
              title: const Text('Show developer controls'),
              secondary: Icon(Icons.developer_mode, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dangerCard(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Danger zone',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Leave organization'),
                  onPressed: () => _confirmLeaveOrg(context),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Request data deletion'),
                  onPressed: () => _confirmRequestDeletion(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLeaveOrg(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Leave organization'),
            content: const Text(
              'This will remove your membership from your personal org. You can rejoin via invite. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    final orgId = _orgId;
    final uid = _uid;
    if (orgId == null || uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('members')
          .doc(uid)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the organization.')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: ${e.message}')));
    }
  }

  Future<void> _confirmRequestDeletion(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Request data deletion'),
            content: const Text(
              'We will queue a backend task to delete your user data and artifacts after a grace period.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Request'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    // Optionally call a callable function here, e.g. deleteAccountData
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deletion request submitted.')),
    );
  }
}
