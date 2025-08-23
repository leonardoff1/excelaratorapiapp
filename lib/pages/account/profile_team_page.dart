import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/service/user_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:http/http.dart' as http;

class ProfileTeamPage extends StatefulWidget {
  const ProfileTeamPage({super.key});

  @override
  State<ProfileTeamPage> createState() => _ProfileTeamPageState();
}

class _ProfileTeamPageState extends State<ProfileTeamPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _nameCtrl = TextEditingController();
  final _photoCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _timezoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  bool _saving = false;

  // Team/invite form
  final _inviteEmailCtrl = TextEditingController();
  String _inviteRole = 'Member'; // Owner | Admin | Member
  bool _inviting = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String? get _orgId {
    final uid = _uid;
    if (uid == null) return null;
    return 'org-$uid';
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _photoCtrl.dispose();
    _companyCtrl.dispose();
    _titleCtrl.dispose();
    _timezoneCtrl.dispose();
    _websiteCtrl.dispose();
    _bioCtrl.dispose();
    _inviteEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Prefill from Auth
    _nameCtrl.text = user.displayName ?? '';
    _photoCtrl.text = user.photoURL ?? '';

    // Prefill from Firestore
    final uref = FirebaseFirestore.instance.collection('users').doc(user.uid);

    final orgref = FirebaseFirestore.instance
        .collection('orgs')
        .doc('org-${user.uid}');

    final snap = await uref.get();
    final orgsnap = await orgref.get();
    if (snap.exists && orgsnap.exists) {
      final d = snap.data()!;
      final dorg = orgsnap.data()!;
      _companyCtrl.text = (dorg['name'] ?? '').toString();
      _titleCtrl.text = (d['title'] ?? '').toString();
      _timezoneCtrl.text = (d['timezone'] ?? '').toString();
      _websiteCtrl.text = (d['website'] ?? '').toString();
      _bioCtrl.text = (d['bio'] ?? '').toString();
    }

    // Ensure the current user shows as Owner member of their org (idempotent)
    final orgId = _orgId;
    if (orgId != null) {
      final ownerRef = FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('members')
          .doc(user.uid);
      final ownerSnap = await ownerRef.get();
      if (!ownerSnap.exists) {
        await ownerRef.set({
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName ?? '',
          'role': 'Owner',
          'status': 'active',
          'addedBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      // Update Auth profile
      await user.updateDisplayName(
        _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      );
      await user.updatePhotoURL(
        _photoCtrl.text.trim().isEmpty ? null : _photoCtrl.text.trim(),
      );
      await user.reload();

      // Persist extended profile
      final uref = FirebaseFirestore.instance.collection('users').doc(user.uid);

      final orgref = FirebaseFirestore.instance
          .collection('orgs')
          .doc('org-${user.uid}');

      await orgref.set({
        'name': _companyCtrl.text.trim(),
      }, SetOptions(merge: true));

      await uref.set({
        'uid': user.uid,
        'email': user.email,
        'name': _nameCtrl.text.trim(),
        'photoURL': _photoCtrl.text.trim(),
        'company': _companyCtrl.text.trim(),
        'title': _titleCtrl.text.trim(),
        'timezone': _timezoneCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved')));
      }
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --- Team helpers ---

  String _randomToken({int bytes = 16}) {
    final r = Random.secure();
    final b = List<int>.generate(bytes, (_) => r.nextInt(256));
    return base64Url.encode(b).replaceAll('=', '');
  }

  Future<void> _addMemberDirect() async {
    final orgId = _orgId;
    final owner = FirebaseAuth.instance.currentUser;
    if (orgId == null || owner == null) return;

    final email = _inviteEmailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid email')));
      return;
    }

    setState(() => _inviting = true);

    UserModel userModel = UserManager.currentUser!;

    String baseUrl = userModel.userURL!;

    try {
      final idToken = await owner.getIdToken(); // bearer for backend
      final uri = Uri.parse('$baseUrl/api/orgs/$orgId/members/direct-invite');
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'role': _inviteRole, // "Admin" | "Member"
          'name': '', // optional
        }),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _inviteEmailCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member added and notified')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Add failed: ${resp.statusCode} ${resp.body}'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _invite() async {
    final orgId = _orgId;
    final owner = FirebaseAuth.instance.currentUser;
    if (orgId == null || owner == null) return;

    final email = _inviteEmailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid email')));
      return;
    }

    setState(() => _inviting = true);
    try {
      final token = _randomToken();
      final invRef =
          FirebaseFirestore.instance
              .collection('orgs')
              .doc(orgId)
              .collection('invites')
              .doc(); // random

      await invRef.set({
        'email': email,
        'role': _inviteRole, // Admin | Member (Owner reserved)
        'status': 'pending',
        'token': token,
        'invitedBy': owner.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _inviteEmailCtrl.clear();

      final link = 'https://app.excelarator.ai/join?org=$orgId&token=$token';
      print(link);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invite created. Link copied:\n$link'),
          duration: const Duration(seconds: 4),
        ),
      );
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  Future<void> _updateRole(String memberDocId, String role) async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('members')
          .doc(memberDocId)
          .update({'role': role, 'updatedAt': FieldValue.serverTimestamp()});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Role updated')));
      }
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: ${e.message}')));
    }
  }

  Future<void> _removeMember(String memberDocId) async {
    final orgId = _orgId;
    final currentUid = _uid;
    if (orgId == null) return;
    if (memberDocId == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't remove yourself (Owner).")),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('members')
          .doc(memberDocId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member removed')));
      }
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Remove failed: ${e.message}')));
    }
  }

  Future<void> _deleteInvite(String inviteId) async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(orgId)
          .collection('invites')
          .doc(inviteId)
          .delete();
    } on FirebaseException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final orgId = _orgId;

    return MainLayout(
      userModel: UserModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile & Team'),
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
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Profile', icon: Icon(Icons.person_outline)),
              Tab(text: 'Team', icon: Icon(Icons.group_outlined)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            // ==== PROFILE TAB ====
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      _profileCard(context),
                      const SizedBox(height: 12),
                      _aboutCard(context),
                    ],
                  ),
                ),
              ),
            ),

            // ==== TEAM TAB ====
            if (orgId == null)
              const Center(child: Text('Sign in to manage your team'))
            else
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(
                      children: [
                        _orgInfoCard(context, orgId),
                        const SizedBox(height: 12),
                        _inviteCard(context),
                        const SizedBox(height: 12),
                        _membersCard(context, orgId),
                        const SizedBox(height: 12),
                        _invitesCard(context, orgId),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ====== PROFILE UI ======

  Widget _profileCard(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundImage:
                      (_photoCtrl.text.trim().isNotEmpty)
                          ? NetworkImage(_photoCtrl.text.trim())
                          : null,
                  child:
                      (_photoCtrl.text.trim().isEmpty)
                          ? const Icon(Icons.person, size: 34)
                          : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        readOnly: true,
                        initialValue: user?.email ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Email (from sign-in)',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveProfile,
                icon:
                    _saving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.save_outlined),
                label: const Text('Save profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About you',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _companyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Company',
                      prefixIcon: Icon(Icons.apartment_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Job title',
                      prefixIcon: Icon(Icons.work_outline),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _timezoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Timezone (e.g. UTC, America/New_York)',
                      prefixIcon: Icon(Icons.schedule_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _websiteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Website',
                      prefixIcon: Icon(Icons.link_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bioCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Bio / notes',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveProfile,
                icon:
                    _saving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.save_outlined),
                label: const Text('Save details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====== TEAM UI ======

  Widget _orgInfoCard(BuildContext context, String orgId) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Row(
          children: [
            const Icon(Icons.approval_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Organization ID',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    orgId,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: orgId));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Organization ID copied')),
                );
              },
              icon: const Icon(Icons.copy_all),
              label: const Text('Copy ID'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inviteCard(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invite teammate',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _inviteEmailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _inviteRole,
                    items:
                        const ['Admin', 'Member']
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                    onChanged:
                        (v) => setState(() => _inviteRole = v ?? 'Member'),
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _inviting ? null : _addMemberDirect,
                  icon:
                      _inviting
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.person_add_alt_outlined),
                  label: const Text('Add member'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Creates /orgs/{orgId}/invites/* with a tokenized link. Your backend (or a Cloud Function) can convert accepted invites into active members.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _membersCard(BuildContext context, String orgId) {
    final q = FirebaseFirestore.instance
        .collection('orgs')
        .doc(orgId)
        .collection('members')
        .orderBy('role'); // simple ordering

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingCard(title: 'Members');
        }
        if (snap.hasError) {
          return _ErrorCard(title: 'Members', error: '${snap.error}');
        }

        final docs = snap.data?.docs ?? const [];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Members (${docs.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('No members yet. Invite teammates above.'),
                  )
                else
                  ...docs.map((d) {
                    final data = d.data();
                    final name = (data['name'] ?? '').toString();
                    final email = (data['email'] ?? '').toString();
                    final role = (data['role'] ?? 'Member').toString();
                    final photo = (data['photoURL'] ?? '').toString();
                    final uid = (data['uid'] ?? '').toString();

                    final isOwner = role == 'Owner';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundImage:
                            (photo.isNotEmpty) ? NetworkImage(photo) : null,
                        child:
                            (photo.isEmpty) ? const Icon(Icons.person) : null,
                      ),
                      title: Text(name.isEmpty ? email : name),
                      subtitle: Text(email),
                      trailing: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 160,
                            child: AbsorbPointer(
                              absorbing: isOwner,
                              child: Opacity(
                                opacity: isOwner ? 0.7 : 1,
                                child: DropdownButtonFormField<String>(
                                  value: role,
                                  items:
                                      const ['Owner', 'Admin', 'Member']
                                          .map(
                                            (r) => DropdownMenuItem(
                                              value: r,
                                              child: Text(r),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (v) {
                                    if (v != null) _updateRole(d.id, v);
                                  },
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Role',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton.outlined(
                            tooltip:
                                isOwner ? "Owner can't be removed" : 'Remove',
                            onPressed:
                                isOwner ? null : () => _removeMember(d.id),
                            icon: const Icon(
                              Icons.person_remove_alt_1_outlined,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _invitesCard(BuildContext context, String orgId) {
    final q = FirebaseFirestore.instance
        .collection('orgs')
        .doc(orgId)
        .collection('invites')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingCard(title: 'Pending invites');
        }
        if (snap.hasError) {
          return _ErrorCard(title: 'Pending invites', error: '${snap.error}');
        }

        final docs = snap.data?.docs ?? const [];
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending invites (${docs.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                if (docs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('No pending invites.'),
                  )
                else
                  ...docs.map((d) {
                    final m = d.data();
                    final email = (m['email'] ?? '').toString();
                    final role = (m['role'] ?? 'Member').toString();
                    final token = (m['token'] ?? '').toString();
                    final link =
                        'https://app.excelarator.ai/join?org=$_orgId&token=$token';

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.mail_outline),
                      title: Text(email),
                      subtitle: Text('Role: $role'),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          IconButton.outlined(
                            tooltip: 'Copy invite link',
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: link),
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Invite link copied'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_all),
                          ),
                          IconButton.outlined(
                            tooltip: 'Delete invite',
                            onPressed: () => _deleteInvite(d.id),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===== Small helper cards =====

class _LoadingCard extends StatelessWidget {
  final String title;
  const _LoadingCard({required this.title});
  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Row(
          children: const [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading…'),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String title;
  final String error;
  const _ErrorCard({required this.title, required this.error});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Text('Error: $error', style: TextStyle(color: cs.error)),
      ),
    );
  }
}
