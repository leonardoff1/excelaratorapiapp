import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _form = GlobalKey<FormState>();
  bool _saving = false;

  // Prefills
  final _emailCtrl = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.email ?? '',
  );
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _attachUrlCtrl =
      TextEditingController(); // paste a link/screenshot if needed

  // Pickers
  String _category = 'Question';
  String _priority = 'Normal';
  String? _relatedJobId;
  List<Map<String, String>> _recentJobs = [];

  // Org resolution
  String? _orgId;
  bool _loadingOrg = true;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _orgId = await _resolveOrgId();
      await _loadRecentJobs();
    } finally {
      if (mounted) setState(() => _loadingOrg = false);
    }
  }

  /// Resolve the active org for the current user.
  /// 1) custom claim orgId
  /// 2) users/{uid}.orgId
  /// 3) any org where /orgs/{orgId}/members/{uid} exists (by 'uid' field or docId)
  /// 4) fallback to personal owner org (org-{uid}) if they are the owner there
  Future<String?> _resolveOrgId() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;

    // 1) custom claim
    try {
      final token = await u.getIdTokenResult(true);
      final fromClaim = token.claims?['orgId'] as String?;
      if (fromClaim != null && fromClaim.isNotEmpty) return fromClaim;
    } catch (_) {}

    // 2) users/{uid}.orgId
    try {
      final uDoc =
          await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final fromDoc = uDoc.data()?['orgId'] as String?;
      if (fromDoc != null && fromDoc.isNotEmpty) return fromDoc;
    } catch (_) {}

    // 3) find any membership (prefer first match)
    try {
      final fs = FirebaseFirestore.instance;

      // a) by uid field
      final cgByField =
          await fs
              .collectionGroup('members')
              .where('uid', isEqualTo: u.uid)
              .limit(1)
              .get();
      if (cgByField.docs.isNotEmpty) {
        final parentOrg = cgByField.docs.first.reference.parent.parent;
        if (parentOrg != null) return parentOrg.id;
      }

      // b) by documentId == uid (if you key member doc by uid)
      final cgById =
          await fs
              .collectionGroup('members')
              .where(FieldPath.documentId, isEqualTo: u.uid)
              .limit(1)
              .get();
      if (cgById.docs.isNotEmpty) {
        final parentOrg = cgById.docs.first.reference.parent.parent;
        if (parentOrg != null) return parentOrg.id;
      }
    } catch (_) {}

    // 4) fallback: personal org only if they're the owner/member there
    try {
      final personal = 'org-${u.uid}';
      final ownerSnap =
          await FirebaseFirestore.instance
              .collection('orgs')
              .doc(personal)
              .collection('members')
              .doc(u.uid)
              .get();
      if (ownerSnap.exists) return personal;
    } catch (_) {}

    return null;
  }

  Future<void> _loadRecentJobs() async {
    final orgId = _orgId;
    if (orgId == null) {
      if (mounted) setState(() => _recentJobs = []);
      return;
    }

    final qs =
        await FirebaseFirestore.instance
            .collection('orgs')
            .doc(orgId)
            .collection('jobs')
            .orderBy('createdAt', descending: true)
            .limit(15)
            .get();

    if (!mounted) return;
    setState(() {
      _recentJobs =
          qs.docs
              .map(
                (d) => {
                  'id': d.id,
                  'name': (d.data()['name'] ?? 'Job').toString(),
                  'status': (d.data()['status'] ?? '').toString(),
                },
              )
              .toList();
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    final uid = _uid;
    final orgId = _orgId;
    if (uid == null || orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in and in an org.')),
      );
      return;
    }

    setState(() => _saving = true);
    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();

    try {
      // Create ticket
      final ticketRef = await db
          .collection('orgs')
          .doc(orgId)
          .collection('tickets')
          .add({
            'subject': _subjectCtrl.text.trim(),
            'description': _descCtrl.text.trim(), // keep a copy
            'requesterEmail': _emailCtrl.text.trim(),
            'category':
                _category, // Question | Bug | Feature | Billing | Account
            'priority': _priority, // Low | Normal | High
            'status':
                'open', // open | investigating | waiting_customer | resolved | closed
            'relatedJobId': _relatedJobId,
            'createdBy': uid,
            'orgId': orgId,
            'attachmentUrl':
                _attachUrlCtrl.text.trim().isEmpty
                    ? null
                    : _attachUrlCtrl.text.trim(),
            'createdAt': now,
            'updatedAt': now,
            'lastMessageAt': now,
            'lastMessageBy': uid,
          });

      // First message = description (immutable message thread)
      await ticketRef.collection('messages').add({
        'authorUid': uid,
        'authorType': 'user',
        'body': _descCtrl.text.trim(),
        'attachments':
            _attachUrlCtrl.text.trim().isEmpty
                ? <String>[]
                : <String>[_attachUrlCtrl.text.trim()],
        'createdAt': now,
      });

      // Optional user index for "My requests"
      await db
          .collection('users')
          .doc(uid)
          .collection('tickets')
          .doc(ticketRef.id)
          .set({'orgId': orgId, 'createdAt': now}, SetOptions(merge: true));

      // OPTIONAL: call your backend to send email notifications
      // (Uncomment and implement endpoint; remember to add http package)
      /*
      try {
        final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();
        final resp = await http.post(
          Uri.parse('https://YOUR_API_DOMAIN/api/support/notify-new'),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'orgId': orgId, 'ticketId': ticketRef.id}),
        );
        // ignore resp for now
      } catch (_) {}
      */

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request submitted (#${ticketRef.id.substring(0, 6)})'),
        ),
      );

      // Navigate wherever you want (jobs, or a ticket detail route if you have one)
      context.go('/jobs');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submit failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    _attachUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingOrg) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If no org could be resolved, show a friendly message
    if (_orgId == null) {
      return MainLayout(
        userModel: UserModel(),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Support'),
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
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'We couldn’t determine your organization.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ask your admin to assign you to an organization, then try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _bootstrap(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MainLayout(
      userModel: UserModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Support'),
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
              onPressed: _saving ? null : _submit,
              icon:
                  _saving
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.send_outlined),
              label: const Text('Submit'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                children: [
                  // Quick links
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick help',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => context.go('/docs'),
                                icon: const Icon(Icons.menu_book_outlined),
                                label: const Text('Documentation'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => context.go('/templates'),
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Sample templates'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => context.go('/status'),
                                icon: const Icon(Icons.wifi_tethering_outlined),
                                label: const Text('System status'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Contact form
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contact support',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _emailCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Contact email',
                                prefixIcon: Icon(Icons.alternate_email),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                final s = v.trim();
                                if (!s.contains('@') || !s.contains('.')) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _category,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Question',
                                        child: Text('Question'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Bug',
                                        child: Text('Bug'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Feature',
                                        child: Text('Feature request'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Billing',
                                        child: Text('Billing'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Account',
                                        child: Text('Account'),
                                      ),
                                    ],
                                    onChanged:
                                        (v) => setState(
                                          () => _category = v ?? 'Question',
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Category',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _priority,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Low',
                                        child: Text('Low'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Normal',
                                        child: Text('Normal'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'High',
                                        child: Text('High'),
                                      ),
                                    ],
                                    onChanged:
                                        (v) => setState(
                                          () => _priority = v ?? 'Normal',
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Priority',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _subjectCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Subject',
                                prefixIcon: Icon(Icons.subject_outlined),
                              ),
                              validator:
                                  (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Required'
                                          : null,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _descCtrl,
                              minLines: 4,
                              maxLines: 12,
                              decoration: const InputDecoration(
                                labelText: 'Describe the issue or request',
                                alignLabelWithHint: true,
                                prefixIcon: Icon(Icons.chat_outlined),
                              ),
                              validator:
                                  (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Required'
                                          : null,
                            ),
                            const SizedBox(height: 8),

                            // Related job selector
                            DropdownButtonFormField<String?>(
                              value: _relatedJobId,
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('— None —'),
                                ),
                                ..._recentJobs.map(
                                  (j) => DropdownMenuItem<String?>(
                                    value: j['id'],
                                    child: Text(
                                      '${j['name']} (${j['status']}) — ${j['id']!.substring(0, 6)}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged:
                                  (v) => setState(() => _relatedJobId = v),
                              decoration: const InputDecoration(
                                labelText: 'Related job (optional)',
                                prefixIcon: Icon(Icons.history_outlined),
                              ),
                            ),
                            if (_recentJobs.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 6),
                                child: Text(
                                  'No recent jobs found for this organization.',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              ),

                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _attachUrlCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Attachment URL (optional)',
                                helperText:
                                    'Paste a link to a screenshot or file (Drive, GitHub gist, etc.).',
                                prefixIcon: Icon(Icons.link_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _submit,
                                icon:
                                    _saving
                                        ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Icon(Icons.send),
                                label: const Text('Submit request'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // FAQ
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: _FaqList(),
                    ),
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

class _FaqList extends StatelessWidget {
  const _FaqList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _FaqItem(
          q: 'Where do I find generated artifacts?',
          a: 'Open the Jobs page, click any job, and use the Download button. Artifacts are stored in Firebase Storage with limited retention.',
        ),
        _FaqItem(
          q: 'How do I report a schema problem?',
          a: 'Attach the Schema JSON you used and describe the unexpected output. Include the job id if possible.',
        ),
        _FaqItem(
          q: 'Can I request a new conversion?',
          a: 'Yes—choose “Feature request”, describe the input→output flow, and we’ll follow up.',
        ),
      ],
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String q, a;
  const _FaqItem({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700)),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(alignment: Alignment.centerLeft, child: Text(a)),
        ),
      ],
    );
  }
}
