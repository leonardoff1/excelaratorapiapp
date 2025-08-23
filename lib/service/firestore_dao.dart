// lib/services/firestore_dao.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/model/models.dart';

/// Generic factory: (id, data) -> entity
typedef FromMap<E> = E Function(String id, Map<String, dynamic> data);

/// Generic serializer: entity -> map
typedef ToMap<E> = Map<String, dynamic> Function(E entity);

/// Paged result for list queries
class PagedResult<E> {
  final List<E> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  const PagedResult({required this.items, required this.lastDoc});
}

/// A lightweight Firestore DAO for your models.
/// Works with plain Map collections and your model's fromMap/toMap.
class FirestoreDao<E> {
  final CollectionReference<Map<String, dynamic>> coll;
  final FromMap<E> fromMap;
  final ToMap<E>? toMap;

  FirestoreDao({required this.coll, required this.fromMap, this.toMap});

  /// Build a query using the base collection.
  Query<Map<String, dynamic>> _applyQuery(
    Query<Map<String, dynamic>> base, {
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> q)? build,
  }) {
    return (build != null) ? build(base) : base;
  }

  /// ---- CRUD ----

  Future<E?> get(String id) async {
    final doc = await coll.doc(id).get();
    if (!doc.exists) return null;
    return fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }

  Stream<E?> watch(String id) {
    return coll.doc(id).snapshots().map((d) {
      if (!d.exists) return null;
      return fromMap(d.id, d.data() ?? <String, dynamic>{});
    });
  }

  Future<List<E>> list({
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> q)? build,
    int? limit,
  }) async {
    var q = _applyQuery(coll, build: build);
    if (limit != null) q = q.limit(limit);
    final snap = await q.get();
    return snap.docs.map((d) => fromMap(d.id, d.data())).toList();
  }

  /// Paginated list (forward only).
  Future<PagedResult<E>> listPaged({
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> q)? build,
    int pageSize = 20,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    var q = _applyQuery(coll, build: build).limit(pageSize);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.get();
    final items = snap.docs.map((d) => fromMap(d.id, d.data())).toList();
    final last = snap.docs.isEmpty ? null : snap.docs.last;
    return PagedResult(items: items, lastDoc: last);
  }

  /// Create from raw map (convenient for quick writes).
  Future<String> createMap(
    Map<String, dynamic> data, {
    String? id,
    bool stamp = true,
  }) async {
    final payload = Map<String, dynamic>.from(data);
    if (stamp) {
      // Only set these if caller passes keys or wants timestamps.
      payload['createdAt'] ??= FieldValue.serverTimestamp();
      payload['updatedAt'] = FieldValue.serverTimestamp();
    }
    if (id != null) {
      await coll.doc(id).set(payload);
      return id;
    } else {
      final ref = await coll.add(payload);
      return ref.id;
    }
  }

  /// Create from entity (requires toMap).
  Future<String> createEntity(E entity, {String? id, bool stamp = true}) async {
    if (toMap == null) throw StateError('toMap is required for createEntity');
    return createMap(toMap!(entity), id: id, stamp: stamp);
  }

  Future<void> updateMap(
    String id,
    Map<String, dynamic> data, {
    bool stamp = true,
    bool merge = true,
  }) async {
    final payload = Map<String, dynamic>.from(data);
    if (stamp) payload['updatedAt'] = FieldValue.serverTimestamp();
    if (merge) {
      await coll.doc(id).set(payload, SetOptions(merge: true));
    } else {
      await coll.doc(id).update(payload);
    }
  }

  Future<void> updateEntity(
    String id,
    E entity, {
    bool stamp = true,
    bool merge = true,
  }) async {
    if (toMap == null) throw StateError('toMap is required for updateEntity');
    await updateMap(id, toMap!(entity), stamp: stamp, merge: merge);
  }

  Future<void> delete(String id) => coll.doc(id).delete();

  /// ---- Streams ----

  Stream<List<E>> watchList({
    Query<Map<String, dynamic>> Function(Query<Map<String, dynamic>> q)? build,
    int? limit,
  }) {
    var q = _applyQuery(coll, build: build);
    if (limit != null) q = q.limit(limit);
    return q.snapshots().map(
      (snap) => snap.docs.map((d) => fromMap(d.id, d.data())).toList(),
    );
  }
}

/// ------------------------------------------------------------------------------------
/// Repositories: strongly-typed wrappers around FirestoreDao for common collections.
/// Adjust collection paths to your structure.
/// ------------------------------------------------------------------------------------

/// /orgs/{orgId}/jobs/{id}
class JobsRepository {
  FirestoreDao<T> _daoFor<T>({
    required String orgId,
    required FromMap<T> fromMap,
    ToMap<T>? toMap,
  }) {
    final coll = FirebaseFirestore.instance
        .collection('orgs')
        .doc(orgId)
        .collection('jobs')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (s, _) => s.data() ?? <String, dynamic>{},
          toFirestore: (m, _) => m,
        );
    return FirestoreDao<T>(coll: coll, fromMap: fromMap, toMap: toMap);
  }

  // Replace the types below with your concrete Job model import.
  // import 'package:excelaratorapi/models/models.dart' show Job, JobStatus, JobType;

  Future<List<Job>> listJobs(
    String orgId, {
    JobStatus? status,
    int limit = 50,
  }) {
    final dao = _daoFor<Job>(
      orgId: orgId,
      fromMap: (id, m) => Job.fromMap(id, m),
      toMap: (j) => j.toMap(),
    );

    return dao.list(
      limit: limit,
      build: (q) {
        if (status != null) {
          q = q.where('status', isEqualTo: status.name);
        }
        return q.orderBy('createdAt', descending: true);
      },
    );
  }

  Stream<List<Job>> watchJobs(
    String orgId, {
    JobStatus? status,
    int limit = 100,
  }) {
    final dao = _daoFor<Job>(
      orgId: orgId,
      fromMap: (id, m) => Job.fromMap(id, m),
      toMap: (j) => j.toMap(),
    );

    return dao.watchList(
      limit: limit,
      build: (q) {
        if (status != null) {
          q = q.where('status', isEqualTo: status.name);
        }
        return q.orderBy('createdAt', descending: true);
      },
    );
  }

  Future<Job?> getJob(String orgId, String jobId) {
    final dao = _daoFor<Job>(
      orgId: orgId,
      fromMap: (id, m) => Job.fromMap(id, m),
      toMap: (j) => j.toMap(),
    );
    return dao.get(jobId);
  }

  Future<String> createJob(String orgId, Job job) {
    final dao = _daoFor<Job>(
      orgId: orgId,
      fromMap: (id, m) => Job.fromMap(id, m),
      toMap: (j) => j.toMap(),
    );
    return dao.createEntity(job, stamp: true);
  }

  Future<void> updateJob(
    String orgId,
    String jobId,
    Map<String, dynamic> patch,
  ) {
    final dao = _daoFor<Job>(
      orgId: orgId,
      fromMap: (id, m) => Job.fromMap(id, m),
      toMap: (j) => j.toMap(),
    );
    return dao.updateMap(jobId, patch, stamp: true, merge: true);
  }

  Future<void> deleteJob(String orgId, String jobId) {
    final dao = _daoFor<Job>(
      orgId: orgId,
      fromMap: (id, m) => Job.fromMap(id, m),
      toMap: (j) => j.toMap(),
    );
    return dao.delete(jobId);
  }
}

/// /orgs/{orgId}/conversions/{id}
class ConversionsRepository {
  FirestoreDao<T> _daoFor<T>({
    required String orgId,
    required FromMap<T> fromMap,
    ToMap<T>? toMap,
  }) {
    final coll = FirebaseFirestore.instance
        .collection('orgs')
        .doc(orgId)
        .collection('conversions')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (s, _) => s.data() ?? <String, dynamic>{},
          toFirestore: (m, _) => m,
        );
    return FirestoreDao<T>(coll: coll, fromMap: fromMap, toMap: toMap);
  }

  Future<List<Conversion>> listConversions(String orgId, {int limit = 50}) {
    final dao = _daoFor<Conversion>(
      orgId: orgId,
      fromMap: (id, m) => Conversion.fromMap(id, m),
      toMap: (c) => c.toMap(),
    );
    return dao.list(
      limit: limit,
      build: (q) => q.orderBy('createdAt', descending: true),
    );
  }

  Stream<List<Conversion>> watchConversions(String orgId, {int limit = 100}) {
    final dao = _daoFor<Conversion>(
      orgId: orgId,
      fromMap: (id, m) => Conversion.fromMap(id, m),
      toMap: (c) => c.toMap(),
    );
    return dao.watchList(
      limit: limit,
      build: (q) => q.orderBy('createdAt', descending: true),
    );
  }

  Future<Conversion?> getConversion(String orgId, String id) {
    final dao = _daoFor<Conversion>(
      orgId: orgId,
      fromMap: (id, m) => Conversion.fromMap(id, m),
      toMap: (c) => c.toMap(),
    );
    return dao.get(id);
  }

  Future<String> createConversion(String orgId, Conversion c) {
    final dao = _daoFor<Conversion>(
      orgId: orgId,
      fromMap: (id, m) => Conversion.fromMap(id, m),
      toMap: (c) => c.toMap(),
    );
    return dao.createEntity(c, stamp: true);
  }

  Future<void> updateConversion(
    String orgId,
    String id,
    Map<String, dynamic> patch,
  ) {
    final dao = _daoFor<Conversion>(
      orgId: orgId,
      fromMap: (id, m) => Conversion.fromMap(id, m),
      toMap: (c) => c.toMap(),
    );
    return dao.updateMap(id, patch, stamp: true, merge: true);
  }

  Future<void> deleteConversion(String orgId, String id) {
    final dao = _daoFor<Conversion>(
      orgId: orgId,
      fromMap: (id, m) => Conversion.fromMap(id, m),
      toMap: (c) => c.toMap(),
    );
    return dao.delete(id);
  }
}

/// ---- Example usage (anywhere in your app) ----
///
/// final jobsRepo = JobsRepository();
/// final jobs = await jobsRepo.listJobs(orgId, status: JobStatus.running);
/// final sub = jobsRepo.watchJobs(orgId).listen((list) { /* update UI */ });
///
/// // Create
/// final id = await jobsRepo.createJob(orgId, jobInstance);
///
/// // Update partial
/// await jobsRepo.updateJob(orgId, jobId, {'status': JobStatus.running.name});
///
/// // Delete
/// await jobsRepo.deleteJob(orgId, jobId);
