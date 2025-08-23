// lib/pages/support_admin_inbox.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// If you want replies to be emailed by your Spring API, set this to true and
/// set [kAdminApiBaseUrl] below. If false, we only write to Firestore.
const bool kUseBackendForReplies = true;

// e.g. https://api.excelarator.ai  (no trailing slash)
const String kAdminApiBaseUrl = String.fromEnvironment(
  'ADMIN_API_BASE_URL',
  defaultValue: '',
);

class SupportAdminInboxPage extends StatefulWidget {
  const SupportAdminInboxPage({super.key});

  @override
  State<SupportAdminInboxPage> createState() => _SupportAdminInboxPageState();
}

class _SupportAdminInboxPageState extends State<SupportAdminInboxPage> {
  String? _orgId;
  bool _loading = true;

  String _status =
      'open'; // open | investigating | waiting_customer | resolved | closed | all
  String _query = '';
  Timer? _debounce;

  // Prevent auto-opening the index link multiple times
  bool _triedOpenIndexOnce = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final orgId = await _resolveOrgId();
    if (!mounted) return;
    setState(() {
      _orgId = orgId;
      _loading = false;
    });
  }

  Future<String?> _resolveOrgId() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    final token = await u.getIdTokenResult(true);
    final claim = token.claims?['orgId'] as String?;
    if (claim != null && claim.isNotEmpty) return claim;

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
    final fromDoc = doc.data()?['orgId'] as String?;
    if (fromDoc != null && fromDoc.isNotEmpty) return fromDoc;

    final personal = 'org-${u.uid}';
    final ownerSnap =
        await FirebaseFirestore.instance
            .collection('orgs')
            .doc(personal)
            .collection('members')
            .doc(u.uid)
            .get();
    return ownerSnap.exists ? personal : null;
  }

  // Avoid composite index by NOT filtering status server-side.
  // We order by updatedAt only, and do status filtering locally.
  Query<Map<String, dynamic>>? _ticketsQuery() {
    final orgId = _orgId;
    if (orgId == null) return null;

    return FirebaseFirestore.instance
        .collection('orgs')
        .doc(orgId)
        .collection('tickets')
        .orderBy('updatedAt', descending: true)
        .limit(200);
  }

  // Extract & open the “create_composite” URL from Firestore error text (if present)
  Future<void> _openFirestoreIndexLinkFromError(Object error) async {
    if (_triedOpenIndexOnce) return;
    _triedOpenIndexOnce = true;

    final text = error.toString();
    final re = RegExp(
      r'(https://console\.firebase\.google\.com/[^\s"]*?indexes\?create_composite=[^\s"]+)',
    );
    final m = re.firstMatch(text);
    final url = m?.group(1);

    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(
        Uri.parse(
          'https://console.firebase.google.com/u/0/project/excelaratorapi/firestore/indexes',
        ),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final q = _ticketsQuery();
    if (q == null) {
      return const Scaffold(
        body: Center(
          child: Text('Sign in as an admin to view support tickets.'),
        ),
      );
    }

    return MainLayout(
      userModel: UserModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Inbox'),
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
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(
                    value: 'investigating',
                    child: Text('Investigating'),
                  ),
                  DropdownMenuItem(
                    value: 'waiting_customer',
                    child: Text('Waiting customer'),
                  ),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'open'),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search subject / requester / ticket id…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (text) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 250), () {
                    if (mounted) {
                      setState(() => _query = text.trim().toLowerCase());
                    }
                  });
                },
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: q.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    // Offer to open the index link if Firestore provided one
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _openFirestoreIndexLinkFromError(snap.error!);
                    });
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Error: ${snap.error}'),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  () => _openFirestoreIndexLinkFromError(
                                    snap.error!,
                                  ),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Open index setup'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final docs = snap.data?.docs ?? const [];

                  // Client-side filtering (status + search)
                  final filtered =
                      docs.where((d) {
                        final m = d.data();
                        final status =
                            (m['status'] ?? 'open').toString().toLowerCase();
                        final matchesStatus =
                            _status == 'all' || status == _status;

                        if (_query.isEmpty) return matchesStatus;

                        final subject =
                            (m['subject'] ?? '').toString().toLowerCase();
                        final email =
                            (m['email'] ?? m['requesterEmail'] ?? '')
                                .toString()
                                .toLowerCase();
                        final id = d.id.toLowerCase();

                        final matchesQuery =
                            subject.contains(_query) ||
                            email.contains(_query) ||
                            id.contains(_query);

                        return matchesStatus && matchesQuery;
                      }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('No tickets found.'));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final d = filtered[i];
                      final t = d.data();
                      final subject = (t['subject'] ?? d.id).toString();
                      final email =
                          (t['email'] ?? t['requesterEmail'] ?? '').toString();
                      final status = (t['status'] ?? 'open').toString();
                      final priority = (t['priority'] ?? 'Normal').toString();
                      final jobId = (t['relatedJobId'] ?? '').toString();

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          title: Text(
                            subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              email,
                              if (jobId.isNotEmpty) 'Job: $jobId',
                              'Priority: $priority',
                            ].join(' • '),
                          ),
                          leading: _StatusDot(status: status),
                          trailing: const Icon(Icons.chevron_right),
                          onTap:
                              () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder:
                                      (_) => _TicketDetailPage(
                                        orgId: _orgId!,
                                        ticketId: d.id,
                                      ),
                                ),
                              ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String status;
  const _StatusDot({required this.status});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color c;
    switch (status) {
      case 'open':
        c = cs.primary;
        break;
      case 'investigating':
        c = Colors.amber.shade700;
        break;
      case 'waiting_customer':
        c = cs.tertiary;
        break;
      case 'resolved':
        c = Colors.green.shade700;
        break;
      case 'closed':
        c = cs.outline;
        break;
      default:
        c = cs.onSurfaceVariant;
    }
    return CircleAvatar(
      radius: 12,
      backgroundColor: c.withOpacity(0.15),
      child: Icon(Icons.mail, color: c, size: 16),
    );
  }
}

class _TicketDetailPage extends StatefulWidget {
  final String orgId;
  final String ticketId;
  const _TicketDetailPage({required this.orgId, required this.ticketId});

  @override
  State<_TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<_TicketDetailPage> {
  final _replyCtrl = TextEditingController();
  bool _sending = false;

  Future<void> _sendReply() async {
    final body = _replyCtrl.text.trim();
    if (body.isEmpty) return;

    setState(() => _sending = true);
    try {
      if (kUseBackendForReplies && kAdminApiBaseUrl.isNotEmpty) {
        // Call your Spring endpoint to both save + email
        final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
        final url = Uri.parse(
          '$kAdminApiBaseUrl/api/support/orgs/${widget.orgId}/tickets/${widget.ticketId}/reply',
        );
        final res = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'body': body}),
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('Reply failed (${res.statusCode}): ${res.body}');
        }
      } else {
        // Client-only: write the message and update ticket metadata
        final u = FirebaseAuth.instance.currentUser!;
        final db = FirebaseFirestore.instance;
        final ticketRef = db
            .collection('orgs')
            .doc(widget.orgId)
            .collection('tickets')
            .doc(widget.ticketId);

        await ticketRef.collection('messages').add({
          'body': body,
          'authorUid': u.uid,
          'authorEmail': u.email,
          'authorRole': 'agent', // agent | requester
          'createdAt': FieldValue.serverTimestamp(),
        });

        await ticketRef.set({
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessageBy': u.uid,
          'status': 'waiting_customer', // typical after agent reply
        }, SetOptions(merge: true));
      }

      _replyCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reply sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reply failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // Keep this helper here too, in case a messages query ever triggers the same error.
  Future<void> openFirestoreIndexLink(Object error) async {
    final text = error.toString();
    final re = RegExp(
      r'(https://console\.firebase\.google\.com/[^\s"]*?indexes\?create_composite=[^\s"]+)',
    );
    final m = re.firstMatch(text);
    final url = m?.group(1);

    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(
        Uri.parse(
          'https://console.firebase.google.com/u/0/project/excelaratorapi/firestore/indexes',
        ),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('orgs')
          .doc(widget.orgId)
          .collection('tickets')
          .doc(widget.ticketId)
          .set({
            'status': newStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticketRef = FirebaseFirestore.instance
        .collection('orgs')
        .doc(widget.orgId)
        .collection('tickets')
        .doc(widget.ticketId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Ticket #${widget.ticketId.substring(0, 6)}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Change status',
            onSelected: _updateStatus,
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: 'open', child: Text('Open')),
                  PopupMenuItem(
                    value: 'investigating',
                    child: Text('Investigating'),
                  ),
                  PopupMenuItem(
                    value: 'waiting_customer',
                    child: Text('Waiting customer'),
                  ),
                  PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                  PopupMenuItem(value: 'closed', child: Text('Closed')),
                ],
            icon: const Icon(Icons.flag_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ticketRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final t = snap.data!.data() ?? <String, dynamic>{};
          final subject = (t['subject'] ?? '').toString();
          final email = (t['email'] ?? t['requesterEmail'] ?? '').toString();
          final status = (t['status'] ?? 'open').toString();
          final priority = (t['priority'] ?? 'Normal').toString();
          final jobId = (t['relatedJobId'] ?? '').toString();

          return Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _pill('Status: $status', Icons.flag_outlined),
                            _pill(
                              'Priority: $priority',
                              Icons.priority_high_outlined,
                            ),
                            if (email.isNotEmpty)
                              _pill(email, Icons.mail_outline),
                            if (jobId.isNotEmpty)
                              _pill('Job: $jobId', Icons.history_outlined),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Messages
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream:
                      ticketRef
                          .collection('messages')
                          .orderBy('createdAt')
                          .snapshots(),
                  builder: (context, ms) {
                    if (ms.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = ms.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return const Center(child: Text('No messages yet.'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final m = docs[i].data();
                        final isAgent = (m['authorRole'] ?? '') == 'agent';
                        final body = (m['body'] ?? '').toString();
                        final author =
                            (m['authorEmail'] ?? m['authorUid'] ?? '')
                                .toString();
                        return Align(
                          alignment:
                              isAgent
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color:
                                    isAgent
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                        : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      isAgent
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                  children: [
                                    Text(body),
                                    const SizedBox(height: 6),
                                    Text(
                                      author,
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Composer
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyCtrl,
                          minLines: 1,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            hintText: 'Write a reply…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _sending ? null : _sendReply,
                        icon:
                            _sending
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.send),
                        label: const Text('Send'),
                      ),
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

  Widget _pill(String text, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text),
        ],
      ),
    );
  }
}
