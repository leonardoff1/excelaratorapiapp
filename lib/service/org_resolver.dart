import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrgResolver {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Returns the user's primary orgId.
  /// Order of precedence:
  /// 1) Custom claims.orgId
  /// 2) /users/{uid}.orgId
  /// 3) Any membership found via collectionGroup('members').where('uid'==uid)
  /// 4) (optional) Create a personal org if none found and createIfNone = true
  static Future<String?> resolveForCurrentUser({
    bool createIfNone = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    // 1) claims
    final token = await user.getIdTokenResult(true);
    final claim = token.claims?['orgId'];
    if (claim is String && claim.isNotEmpty) return claim;

    // 2) users/{uid}.orgId
    final uSnap = await _db.collection('users').doc(user.uid).get();
    final orgIdFromUser = (uSnap.data()?['orgId'] as String?);
    if (orgIdFromUser != null && orgIdFromUser.isNotEmpty) return orgIdFromUser;

    // 3) membership lookup
    final cg =
        await _db
            .collectionGroup('members')
            .where('uid', isEqualTo: user.uid)
            .limit(5)
            .get();

    if (cg.docs.isNotEmpty) {
      // Pick the most recently updated membership if multiple
      cg.docs.sort((a, b) {
        final at = a.data()['updatedAt'];
        final bt = b.data()['updatedAt'];
        final ai = (at is Timestamp) ? at.toDate().millisecondsSinceEpoch : 0;
        final bi = (bt is Timestamp) ? bt.toDate().millisecondsSinceEpoch : 0;
        return bi.compareTo(ai);
      });
      final first = cg.docs.first;
      final orgId = first.reference.parent.parent!.id;

      // Persist to users/{uid} for quick load next time
      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'orgId': orgId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return orgId;
    }

    // 4) Optional: no memberships anywhere → create personal org (only if you want this behavior)
    if (createIfNone) {
      final orgId = 'org-${user.uid}';
      final orgRef = _db.collection('orgs').doc(orgId);
      final batch = _db.batch();
      batch.set(orgRef, {
        'id': orgId,
        'name':
            user.displayName?.trim().isNotEmpty == true
                ? '${user.displayName} (Personal)'
                : 'Personal Workspace',
        'ownerUid': user.uid,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(orgRef.collection('members').doc(user.uid), {
        'uid': user.uid,
        'email': user.email,
        'name': user.displayName ?? '',
        'role': 'Owner',
        'admin': true,
        'roles': FieldValue.arrayUnion(['owner', 'admin']),
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(_db.collection('users').doc(user.uid), {
        'uid': user.uid,
        'email': user.email,
        'orgId': orgId,
        'admin': true,
        'adminOrgs': FieldValue.arrayUnion([orgId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      return orgId;
    }

    return null;
  }
}
