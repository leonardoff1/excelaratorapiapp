import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TicketDetailPage extends StatelessWidget {
  final String orgId;
  final String ticketId;
  const TicketDetailPage({
    super.key,
    required this.orgId,
    required this.ticketId,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final ticketDoc = db
        .collection('orgs')
        .doc(orgId)
        .collection('tickets')
        .doc(ticketId);
    final msgsCol = ticketDoc.collection('messages').orderBy('createdAt');

    final replyCtrl = TextEditingController();

    Future<void> sendReply() async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || replyCtrl.text.trim().isEmpty) return;

      final now = FieldValue.serverTimestamp();
      await ticketDoc.collection('messages').add({
        'authorUid': uid,
        'authorType': 'user',
        'body': replyCtrl.text.trim(),
        'attachments': [],
        'createdAt': now,
      });
      await ticketDoc.set({
        'lastMessageAt': now,
        'lastMessageBy': uid,
        'updatedAt': now,
        'status': 'open', // when customer replies, put back to open
      }, SetOptions(merge: true));

      replyCtrl.clear();

      // OPTIONAL: ping backend to send email notification (see section 6)
      // await http.post(...);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ticket')),
      body: Column(
        children: [
          // ticket header
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: ticketDoc.snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              final t = snap.data!.data() ?? {};
              return ListTile(
                title: Text(t['subject'] ?? ''),
                subtitle: Text(
                  '${t['status']} • ${t['priority']} • ${t['category']}',
                ),
                trailing:
                    (t['relatedJobId'] != null)
                        ? Text('Job: ${t['relatedJobId']}')
                        : null,
              );
            },
          ),
          const Divider(height: 1),
          // messages
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: msgsCol.snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final m = docs[i].data();
                    final fromAgent = (m['authorType'] == 'agent');
                    return Align(
                      alignment:
                          fromAgent
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              fromAgent
                                  ? Colors.blue.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(m['body'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // reply box
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: replyCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Write a reply…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: sendReply,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
