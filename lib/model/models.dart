// lib/models/models.dart
// Minimal, dependency-free data models for ExcelaratorAPI.
// Firestore-friendly (handles Timestamp / DateTime), easy to extend.

// ---- Utils ----
DateTime? _dt(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v.runtimeType.toString() == 'Timestamp') {
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
  return null;
}

// Parse "foo" -> E.foo where E is an enum type.
E _enumFromString<E extends Enum>(String value, List<E> values) {
  return values.firstWhere((e) => e.name == value, orElse: () => values.first);
}

// Serialize enum -> "foo"
String _enum(Enum e) => e.name;

/// ---- Enums ---------------------------------------------------------------

enum JobType {
  spreadsheetToSpring,
  spreadsheetToDbAdmin,
  spreadsheetToPostgresSchema,
  spreadsheetToOrm,
  spreadsheetToEtl,
  spreadsheetToAnalytics,
  dbReverseEngineer,
  spreadsheetToSqlDump,
  spreadsheetToFirestore,
  spreadsheetToBackend, // future: FastAPI/Express/Laravel packs
}

enum JobStatus { pending, running, success, failed, canceled }

enum DbKind {
  postgres,
  mysql,
  sqlserver,
  sqlite,
  mongo,
  dynamodb,
  firestore,
  supabase,
  cosmos,
}

enum ArtifactKind { sourceZip, openapi, sqlDump, logs, preview }

enum PlanId { free, starter, pro, team, enterprise }

enum BillingCycle { monthly, yearly }

enum ApiScope {
  jobsRead,
  jobsWrite,
  keysManage,
  billingRead,
  billingWrite,
  admin,
}

enum FieldType {
  integer,
  decimal,
  number, // float/double
  boolean,
  string,
  date,
  datetime,
  json,
  bytes,
}

/// ---- Core identities -----------------------------------------------------

class UserProfile {
  final String id; // Firebase UID
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? companyId;
  final bool admin;
  final bool approved;
  final DateTime? createdAt;
  final String? orgId;

  const UserProfile({
    required this.id,
    this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.companyId,
    this.admin = false,
    this.approved = false,
    this.createdAt,
    this.orgId,
  });

  factory UserProfile.fromMap(String id, Map<String, dynamic> m) => UserProfile(
    id: id,
    email: m['email'],
    firstName: m['firstName'],
    lastName: m['lastName'],
    phone: m['phone'],
    companyId: m['companyId'],
    admin: (m['admin'] ?? false) as bool,
    approved: (m['approved'] ?? false) as bool,
    createdAt: _dt(m['createdAt']),
    orgId: m['orgId'],
  );

  Map<String, dynamic> toMap() => {
    'email': email,
    'firstName': firstName,
    'lastName': lastName,
    'phone': phone,
    'companyId': companyId,
    'admin': admin,
    'approved': approved,
    'createdAt': createdAt,
    'orgId': orgId,
  };

  String get displayName =>
      [firstName, lastName].where((s) => (s ?? '').isNotEmpty).join(' ').trim();
}

class AuthLog {
  final String id;
  final String? uid;
  final String? email;
  final String event; // "login" | "logout"
  final DateTime? timestamp;

  const AuthLog({
    required this.id,
    required this.event,
    this.uid,
    this.email,
    this.timestamp,
  });

  factory AuthLog.fromMap(String id, Map<String, dynamic> m) => AuthLog(
    id: id,
    uid: m['uid'],
    email: m['email'],
    event: m['event'] ?? 'login',
    timestamp: _dt(m['timestamp']),
  );

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'email': email,
    'event': event,
    'timestamp': timestamp,
  };
}

class Organization {
  final String id;
  final String name;
  final List<String> owners; // userIds
  final List<String> members; // userIds
  final PlanId planId;
  final BillingCycle cycle;
  final DateTime? createdAt;

  const Organization({
    required this.id,
    required this.name,
    required this.owners,
    required this.members,
    required this.planId,
    required this.cycle,
    this.createdAt,
  });

  factory Organization.fromMap(String id, Map<String, dynamic> m) =>
      Organization(
        id: id,
        name: m['name'] ?? 'Org',
        owners: List<String>.from(m['owners'] ?? const []),
        members: List<String>.from(m['members'] ?? const []),
        planId: _enumFromString(m['planId'] ?? 'free', PlanId.values),
        cycle: _enumFromString(m['cycle'] ?? 'monthly', BillingCycle.values),
        createdAt: _dt(m['createdAt']),
      );

  Map<String, dynamic> toMap() => {
    'name': name,
    'owners': owners,
    'members': members,
    'planId': _enum(planId),
    'cycle': _enum(cycle),
    'createdAt': createdAt,
  };
}

/// ---- Billing -------------------------------------------------------------

class Plan {
  final PlanId id;
  final String label;
  final int monthlyUsd;
  final int conversions;
  final int minutes;
  final int seats;
  final int storageGb;
  final List<String> features;

  const Plan({
    required this.id,
    required this.label,
    required this.monthlyUsd,
    required this.conversions,
    required this.minutes,
    required this.seats,
    required this.storageGb,
    required this.features,
  });

  Map<String, dynamic> toMap() => {
    'id': _enum(id),
    'label': label,
    'monthlyUsd': monthlyUsd,
    'conversions': conversions,
    'minutes': minutes,
    'seats': seats,
    'storageGb': storageGb,
    'features': features,
  };

  factory Plan.fromMap(Map<String, dynamic> m) => Plan(
    id: _enumFromString(m['id'] ?? 'free', PlanId.values),
    label: m['label'] ?? '',
    monthlyUsd: (m['monthlyUsd'] ?? 0) as int,
    conversions: (m['conversions'] ?? 0) as int,
    minutes: (m['minutes'] ?? 0) as int,
    seats: (m['seats'] ?? 1) as int,
    storageGb: (m['storageGb'] ?? 0) as int,
    features: List<String>.from(m['features'] ?? const []),
  );
}

class Subscription {
  final String orgId;
  final PlanId planId;
  final BillingCycle cycle;
  final DateTime? renewsAt;
  final PaymentMethodInfo? paymentMethod;
  final Map<String, int>
  addons; // e.g., { "extraMinutesPacks": 2, "extraSeats": 3 }
  final bool cancelAtPeriodEnd;

  const Subscription({
    required this.orgId,
    required this.planId,
    required this.cycle,
    this.renewsAt,
    this.paymentMethod,
    this.addons = const {},
    this.cancelAtPeriodEnd = false,
  });

  factory Subscription.fromMap(String orgId, Map<String, dynamic> m) =>
      Subscription(
        orgId: orgId,
        planId: _enumFromString(m['planId'] ?? 'free', PlanId.values),
        cycle: _enumFromString(m['cycle'] ?? 'monthly', BillingCycle.values),
        renewsAt: _dt(m['renewsAt']),
        paymentMethod:
            m['paymentMethod'] == null
                ? null
                : PaymentMethodInfo.fromMap(m['paymentMethod']),
        addons: Map<String, int>.from(m['addons'] ?? const {}),
        cancelAtPeriodEnd: (m['cancelAtPeriodEnd'] ?? false) as bool,
      );

  Map<String, dynamic> toMap() => {
    'planId': _enum(planId),
    'cycle': _enum(cycle),
    'renewsAt': renewsAt,
    'paymentMethod': paymentMethod?.toMap(),
    'addons': addons,
    'cancelAtPeriodEnd': cancelAtPeriodEnd,
  };
}

class PaymentMethodInfo {
  final String brand; // "Visa"
  final String last4; // "4242"

  const PaymentMethodInfo({required this.brand, required this.last4});

  Map<String, dynamic> toMap() => {'brand': brand, 'last4': last4};

  factory PaymentMethodInfo.fromMap(Map<String, dynamic> m) =>
      PaymentMethodInfo(brand: m['brand'] ?? '', last4: m['last4'] ?? '');
}

/// ---- API Keys ------------------------------------------------------------

class ApiKey {
  final String id;
  final String orgId;
  final String label;
  final String prefix; // show-only prefix
  final List<ApiScope> scopes;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final bool revoked;

  const ApiKey({
    required this.id,
    required this.orgId,
    required this.label,
    required this.prefix,
    required this.scopes,
    this.createdAt,
    this.lastUsedAt,
    this.revoked = false,
  });

  factory ApiKey.fromMap(String id, Map<String, dynamic> m) => ApiKey(
    id: id,
    orgId: m['orgId'] ?? '',
    label: m['label'] ?? '',
    prefix: m['prefix'] ?? '',
    scopes:
        (m['scopes'] as List? ?? const [])
            .map(
              (s) => _enumFromString<ApiScope>(s.toString(), ApiScope.values),
            )
            .toList(),
    createdAt: _dt(m['createdAt']),
    lastUsedAt: _dt(m['lastUsedAt']),
    revoked: (m['revoked'] ?? false) as bool,
  );

  Map<String, dynamic> toMap() => {
    'orgId': orgId,
    'label': label,
    'prefix': prefix,
    'scopes': scopes.map(_enum).toList(),
    'createdAt': createdAt,
    'lastUsedAt': lastUsedAt,
    'revoked': revoked,
  };
}

/// ---- Conversions & Schema -----------------------------------------------

class Conversion {
  final String id;
  final String orgId;
  final String createdBy; // userId
  final String name;
  final String? description;
  final JobType type;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Sources (one of these will be used depending on type)
  final SpreadsheetSource? spreadsheet; // for spreadsheetTo*
  final DbSource? database; // for dbReverseEngineer

  // Derived schema (after inference/reverse)
  final List<TableSchema> schema; // optional pre-computed schema preview

  const Conversion({
    required this.id,
    required this.orgId,
    required this.createdBy,
    required this.name,
    required this.type,
    this.description,
    this.createdAt,
    this.updatedAt,
    this.spreadsheet,
    this.database,
    this.schema = const [],
  });

  factory Conversion.fromMap(String id, Map<String, dynamic> m) => Conversion(
    id: id,
    orgId: m['orgId'] ?? '',
    createdBy: m['createdBy'] ?? '',
    name: m['name'] ?? '',
    description: m['description'],
    type: _enumFromString(m['type'] ?? 'spreadsheetToSpring', JobType.values),
    createdAt: _dt(m['createdAt']),
    updatedAt: _dt(m['updatedAt']),
    spreadsheet:
        m['spreadsheet'] == null
            ? null
            : SpreadsheetSource.fromMap(m['spreadsheet']),
    database: m['database'] == null ? null : DbSource.fromMap(m['database']),
    schema:
        (m['schema'] as List? ?? const [])
            .map(
              (t) => TableSchema.fromMap(Map<String, dynamic>.from(t as Map)),
            )
            .toList(),
  );

  Map<String, dynamic> toMap() => {
    'orgId': orgId,
    'createdBy': createdBy,
    'name': name,
    'description': description,
    'type': _enum(type),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'spreadsheet': spreadsheet?.toMap(),
    'database': database?.toMap(),
    'schema': schema.map((t) => t.toMap()).toList(),
  };
}

class SpreadsheetSource {
  final String fileName;
  final String storagePath; // gcs/firestore storage path or URL
  final List<SheetMapping> sheets; // sheet→table/collection
  final bool headerRow;

  const SpreadsheetSource({
    required this.fileName,
    required this.storagePath,
    required this.sheets,
    this.headerRow = true,
  });

  factory SpreadsheetSource.fromMap(Map<String, dynamic> m) =>
      SpreadsheetSource(
        fileName: m['fileName'] ?? '',
        storagePath: m['storagePath'] ?? '',
        sheets:
            (m['sheets'] as List? ?? const [])
                .map(
                  (x) =>
                      SheetMapping.fromMap(Map<String, dynamic>.from(x as Map)),
                )
                .toList(),
        headerRow: (m['headerRow'] ?? true) as bool,
      );

  Map<String, dynamic> toMap() => {
    'fileName': fileName,
    'storagePath': storagePath,
    'sheets': sheets.map((s) => s.toMap()).toList(),
    'headerRow': headerRow,
  };
}

class SheetMapping {
  final String sheetName;
  final String targetName; // table/collection name
  final Map<String, String> fieldRenames; // original -> target
  final Map<String, FieldType> fieldTypes; // optional overrides

  const SheetMapping({
    required this.sheetName,
    required this.targetName,
    this.fieldRenames = const {},
    this.fieldTypes = const {},
  });

  factory SheetMapping.fromMap(Map<String, dynamic> m) => SheetMapping(
    sheetName: m['sheetName'] ?? '',
    targetName: m['targetName'] ?? '',
    fieldRenames: Map<String, String>.from(m['fieldRenames'] ?? const {}),
    fieldTypes: (m['fieldTypes'] as Map? ?? const {}).map(
      (k, v) => MapEntry(
        k as String,
        _enumFromString(v.toString(), FieldType.values),
      ),
    ),
  );

  Map<String, dynamic> toMap() => {
    'sheetName': sheetName,
    'targetName': targetName,
    'fieldRenames': fieldRenames,
    'fieldTypes': fieldTypes.map((k, v) => MapEntry(k, _enum(v))),
  };
}

class DbSource {
  final DbConnection connection;
  final List<String> includeSchemas; // e.g., public
  final List<String> includeTables; // optional filters

  const DbSource({
    required this.connection,
    this.includeSchemas = const [],
    this.includeTables = const [],
  });

  factory DbSource.fromMap(Map<String, dynamic> m) => DbSource(
    connection: DbConnection.fromMap(
      Map<String, dynamic>.from(m['connection'] ?? const {}),
    ),
    includeSchemas: List<String>.from(m['includeSchemas'] ?? const []),
    includeTables: List<String>.from(m['includeTables'] ?? const []),
  );

  Map<String, dynamic> toMap() => {
    'connection': connection.toMap(),
    'includeSchemas': includeSchemas,
    'includeTables': includeTables,
  };
}

class DbConnection {
  final DbKind kind;
  final String name; // display name
  final String host;
  final int port;
  final String database;
  final String username;
  final String
  secretRef; // reference to backend-stored secret (never store pwd here)
  final bool ssl;

  const DbConnection({
    required this.kind,
    required this.name,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.secretRef,
    this.ssl = true,
  });

  factory DbConnection.fromMap(Map<String, dynamic> m) => DbConnection(
    kind: _enumFromString(m['kind'] ?? 'postgres', DbKind.values),
    name: m['name'] ?? '',
    host: m['host'] ?? '',
    port: (m['port'] ?? 5432) as int,
    database: m['database'] ?? '',
    username: m['username'] ?? '',
    secretRef: m['secretRef'] ?? '',
    ssl: (m['ssl'] ?? true) as bool,
  );

  Map<String, dynamic> toMap() => {
    'kind': _enum(kind),
    'name': name,
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'secretRef': secretRef,
    'ssl': ssl,
  };
}

class TableSchema {
  final String name;
  final List<FieldSchema> fields;
  final String? primaryKey; // field name
  final List<ForeignKey> foreignKeys;

  const TableSchema({
    required this.name,
    required this.fields,
    this.primaryKey,
    this.foreignKeys = const [],
  });

  factory TableSchema.fromMap(Map<String, dynamic> m) => TableSchema(
    name: m['name'] ?? '',
    fields:
        (m['fields'] as List? ?? const [])
            .map(
              (f) => FieldSchema.fromMap(Map<String, dynamic>.from(f as Map)),
            )
            .toList(),
    primaryKey: m['primaryKey'],
    foreignKeys:
        (m['foreignKeys'] as List? ?? const [])
            .map((f) => ForeignKey.fromMap(Map<String, dynamic>.from(f as Map)))
            .toList(),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'fields': fields.map((f) => f.toMap()).toList(),
    'primaryKey': primaryKey,
    'foreignKeys': foreignKeys.map((f) => f.toMap()).toList(),
  };
}

class FieldSchema {
  final String name;
  final FieldType type;
  final bool nullable;
  final bool unique;
  final int? length; // strings
  final int? precision; // decimals
  final int? scale; // decimals

  const FieldSchema({
    required this.name,
    required this.type,
    this.nullable = true,
    this.unique = false,
    this.length,
    this.precision,
    this.scale,
  });

  factory FieldSchema.fromMap(Map<String, dynamic> m) => FieldSchema(
    name: m['name'] ?? '',
    type: _enumFromString(m['type'] ?? 'string', FieldType.values),
    nullable: (m['nullable'] ?? true) as bool,
    unique: (m['unique'] ?? false) as bool,
    length: m['length'],
    precision: m['precision'],
    scale: m['scale'],
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'type': _enum(type),
    'nullable': nullable,
    'unique': unique,
    'length': length,
    'precision': precision,
    'scale': scale,
  };
}

class ForeignKey {
  final String column;
  final String referencesTable;
  final String referencesColumn;
  final String? onDelete; // cascade/restrict/set_null

  const ForeignKey({
    required this.column,
    required this.referencesTable,
    required this.referencesColumn,
    this.onDelete,
  });

  factory ForeignKey.fromMap(Map<String, dynamic> m) => ForeignKey(
    column: m['column'] ?? '',
    referencesTable: m['referencesTable'] ?? '',
    referencesColumn: m['referencesColumn'] ?? '',
    onDelete: m['onDelete'],
  );

  Map<String, dynamic> toMap() => {
    'column': column,
    'referencesTable': referencesTable,
    'referencesColumn': referencesColumn,
    'onDelete': onDelete,
  };
}

/// ---- Jobs & artifacts ----------------------------------------------------

class Job {
  final String id;
  final String orgId;
  final String userId;
  final String? conversionId; // optional link to a Conversion
  final String name;
  final JobType type;
  final JobStatus status;
  final double progress; // 0..1
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error; // message/stack
  final List<Artifact> artifacts;

  const Job({
    required this.id,
    required this.orgId,
    required this.userId,
    required this.name,
    required this.type,
    required this.status,
    this.progress = 0.0,
    this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.error,
    this.conversionId,
    this.artifacts = const [],
  });

  factory Job.fromMap(String id, Map<String, dynamic> m) => Job(
    id: id,
    orgId: m['orgId'] ?? '',
    userId: m['userId'] ?? '',
    name: m['name'] ?? '',
    type: _enumFromString(m['type'] ?? 'spreadsheetToSpring', JobType.values),
    status: _enumFromString(m['status'] ?? 'pending', JobStatus.values),
    progress: (m['progress'] is num) ? (m['progress'] as num).toDouble() : 0.0,
    createdAt: _dt(m['createdAt']),
    startedAt: _dt(m['startedAt']),
    finishedAt: _dt(m['finishedAt']),
    error: m['error'],
    conversionId: m['conversionId'],
    artifacts:
        (m['artifacts'] as List? ?? const [])
            .map((a) => Artifact.fromMap(Map<String, dynamic>.from(a as Map)))
            .toList(),
  );

  Map<String, dynamic> toMap() => {
    'orgId': orgId,
    'userId': userId,
    'name': name,
    'type': _enum(type),
    'status': _enum(status),
    'progress': progress,
    'createdAt': createdAt,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'error': error,
    'conversionId': conversionId,
    'artifacts': artifacts.map((a) => a.toMap()).toList(),
  };

  int? get durationSecs =>
      (startedAt != null && finishedAt != null)
          ? finishedAt!.difference(startedAt!).inSeconds
          : null;
}

class Artifact {
  final String id;
  final ArtifactKind kind;
  final String fileName;
  final String url; // signed URL or Storage path
  final int? sizeBytes;
  final DateTime? expiresAt;

  const Artifact({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.url,
    this.sizeBytes,
    this.expiresAt,
  });

  factory Artifact.fromMap(Map<String, dynamic> m) => Artifact(
    id: m['id'] ?? '',
    kind: _enumFromString(m['kind'] ?? 'sourceZip', ArtifactKind.values),
    fileName: m['fileName'] ?? '',
    url: m['url'] ?? '',
    sizeBytes: m['sizeBytes'],
    expiresAt: _dt(m['expiresAt']),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': _enum(kind),
    'fileName': fileName,
    'url': url,
    'sizeBytes': sizeBytes,
    'expiresAt': expiresAt,
  };
}

/// ---- Usage & quotas ------------------------------------------------------

class UsagePeriod {
  final String orgId;
  final int year; // e.g., 2025
  final int month; // 1-12
  final int conversionsUsed;
  final int minutesUsed;
  final int seatsUsed;
  final int storageGbUsed;

  const UsagePeriod({
    required this.orgId,
    required this.year,
    required this.month,
    required this.conversionsUsed,
    required this.minutesUsed,
    required this.seatsUsed,
    required this.storageGbUsed,
  });

  factory UsagePeriod.fromMap(String orgId, Map<String, dynamic> m) =>
      UsagePeriod(
        orgId: orgId,
        year: (m['year'] ?? DateTime.now().year) as int,
        month: (m['month'] ?? DateTime.now().month) as int,
        conversionsUsed: (m['conversionsUsed'] ?? 0) as int,
        minutesUsed: (m['minutesUsed'] ?? 0) as int,
        seatsUsed: (m['seatsUsed'] ?? 0) as int,
        storageGbUsed: (m['storageGbUsed'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
    'year': year,
    'month': month,
    'conversionsUsed': conversionsUsed,
    'minutesUsed': minutesUsed,
    'seatsUsed': seatsUsed,
    'storageGbUsed': storageGbUsed,
  };
}

/// ---- Webhooks & notifications --------------------------------------------

class Webhook {
  final String id;
  final String orgId;
  final String url;
  final List<String> events; // e.g., ['job.succeeded','job.failed']
  final String secret; // HMAC
  final bool enabled;
  final DateTime? createdAt;

  const Webhook({
    required this.id,
    required this.orgId,
    required this.url,
    required this.events,
    required this.secret,
    this.enabled = true,
    this.createdAt,
  });

  factory Webhook.fromMap(String id, Map<String, dynamic> m) => Webhook(
    id: id,
    orgId: m['orgId'] ?? '',
    url: m['url'] ?? '',
    events: List<String>.from(m['events'] ?? const []),
    secret: m['secret'] ?? '',
    enabled: (m['enabled'] ?? true) as bool,
    createdAt: _dt(m['createdAt']),
  );

  Map<String, dynamic> toMap() => {
    'orgId': orgId,
    'url': url,
    'events': events,
    'secret': secret,
    'enabled': enabled,
    'createdAt': createdAt,
  };
}

class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;
  final String? actionUrl;
  final String? jobId; // link to job

  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    this.read = false,
    this.createdAt,
    this.actionUrl,
    this.jobId,
  });

  factory AppNotification.fromMap(String id, Map<String, dynamic> m) =>
      AppNotification(
        id: id,
        userId: m['userId'] ?? '',
        title: m['title'] ?? '',
        body: m['body'] ?? '',
        read: (m['read'] ?? false) as bool,
        createdAt: _dt(m['createdAt']),
        actionUrl: m['actionUrl'],
        jobId: m['jobId'],
      );

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'title': title,
    'body': body,
    'read': read,
    'createdAt': createdAt,
    'actionUrl': actionUrl,
    'jobId': jobId,
  };
}

/// ---- Settings ------------------------------------------------------------

class UserSettings {
  final String userId;
  final String locale; // 'en', 'pt', 'es'
  final String theme; // 'system' | 'light' | 'dark'
  final bool emailAlerts;

  const UserSettings({
    required this.userId,
    this.locale = 'en',
    this.theme = 'system',
    this.emailAlerts = true,
  });

  factory UserSettings.fromMap(String userId, Map<String, dynamic> m) =>
      UserSettings(
        userId: userId,
        locale: m['locale'] ?? 'en',
        theme: m['theme'] ?? 'system',
        emailAlerts: (m['emailAlerts'] ?? true) as bool,
      );

  Map<String, dynamic> toMap() => {
    'locale': locale,
    'theme': theme,
    'emailAlerts': emailAlerts,
  };
}

class OrgSettings {
  final String orgId;
  final String defaultRegion; // e.g., 'us-east1'
  final bool
  allowPublicArtifacts; // if true, artifact URLs can be public/read-only
  final bool telemetry; // product analytics consent

  const OrgSettings({
    required this.orgId,
    this.defaultRegion = 'us-east1',
    this.allowPublicArtifacts = false,
    this.telemetry = true,
  });

  factory OrgSettings.fromMap(String orgId, Map<String, dynamic> m) =>
      OrgSettings(
        orgId: orgId,
        defaultRegion: m['defaultRegion'] ?? 'us-east1',
        allowPublicArtifacts: (m['allowPublicArtifacts'] ?? false) as bool,
        telemetry: (m['telemetry'] ?? true) as bool,
      );

  Map<String, dynamic> toMap() => {
    'defaultRegion': defaultRegion,
    'allowPublicArtifacts': allowPublicArtifacts,
    'telemetry': telemetry,
  };
}
