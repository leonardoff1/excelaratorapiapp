import 'dart:convert';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// ====== Configure these (via --dart-define or edit defaults) ======
/// Example: flutter run --dart-define=API_BASE_URL=https://api.excelarator.ai
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:5001',
);

/// Example: flutter run --dart-define=HEALTH_PATH=/actuator/health
const String kHealthPath = String.fromEnvironment(
  'HEALTH_PATH',
  defaultValue: '/actuator/health',
);

/// If your health endpoint is protected, pass an ID token:
/// flutter run --dart-define=HEALTH_WITH_AUTH=true
const bool kHealthWithAuth = bool.fromEnvironment('HEALTH_WITH_AUTH');

class SystemStatusPage extends StatefulWidget {
  const SystemStatusPage({super.key});

  @override
  State<SystemStatusPage> createState() => _SystemStatusPageState();
}

class _SystemStatusPageState extends State<SystemStatusPage> {
  bool _checking = false;
  bool? _up; // null = unknown
  int? _httpStatus;
  Duration? _latency;
  DateTime? _lastChecked;
  String? _errorSnippet;

  Uri get _healthUri => Uri.parse(
    kApiBaseUrl.endsWith('/')
        ? '${kApiBaseUrl.substring(0, kApiBaseUrl.length - 1)}$kHealthPath'
        : '$kApiBaseUrl$kHealthPath',
  );

  @override
  void initState() {
    super.initState();
    _checkNow();
  }

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _errorSnippet = null;
    });

    final sw = Stopwatch()..start();
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (kHealthWithAuth) {
        final tok = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (tok != null) headers['Authorization'] = 'Bearer $tok';
      }

      final res = await http
          .get(_healthUri, headers: headers)
          .timeout(const Duration(seconds: 8));
      sw.stop();

      bool ok = res.statusCode >= 200 && res.statusCode < 300;

      // If it's Spring Actuator: {"status":"UP"|"DOWN"|...}
      try {
        final body = json.decode(res.body);
        if (body is Map && body['status'] is String) {
          final s = (body['status'] as String).toUpperCase();
          if (s == 'UP') ok = true;
          if (s == 'DOWN') ok = false;
        }
      } catch (_) {
        // ignore parse errors; rely on HTTP status
      }

      setState(() {
        _up = ok;
        _httpStatus = res.statusCode;
        _latency = sw.elapsed;
        _lastChecked = DateTime.now();
        _errorSnippet = ok ? null : _trim(res.body);
      });
    } catch (e) {
      sw.stop();
      setState(() {
        _up = false;
        _httpStatus = null;
        _latency = sw.elapsed;
        _lastChecked = DateTime.now();
        _errorSnippet = _trim(e.toString());
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _trim(String s, [int max = 240]) {
    s = s.trim();
    return s.length <= max ? s : '${s.substring(0, max)}…';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final color =
        _up == null
            ? cs.onSurfaceVariant
            : _up == true
            ? Colors.green
            : cs.error;

    final icon =
        _up == null
            ? Icons.help_outline
            : _up == true
            ? Icons.check_circle_outline
            : Icons.error_outline;

    final label =
        _up == null
            ? 'Unknown'
            : _up == true
            ? 'API is UP'
            : 'API is DOWN';

    return MainLayout(
      userModel: UserModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('System status'),
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
            IconButton(
              tooltip: 'Open health endpoint',
              onPressed:
                  () => launchUrl(
                    _healthUri,
                    mode: LaunchMode.externalApplication,
                  ),
              icon: const Icon(Icons.open_in_new),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _checking ? null : _checkNow,
              icon:
                  _checking
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.refresh),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: color.withOpacity(0.12),
                            child: Icon(icon, color: color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              style: Theme.of(
                                context,
                              ).textTheme.titleLarge?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _checking ? null : _checkNow,
                            icon:
                                _checking
                                    ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.refresh),
                            label: const Text('Check now'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _kv('Endpoint', _healthUri.toString(), context),
                      _kv('HTTP', _httpStatus?.toString() ?? '—', context),
                      _kv(
                        'Latency',
                        _latency == null
                            ? '—'
                            : '${_latency!.inMilliseconds} ms',
                        context,
                      ),
                      _kv(
                        'Last checked',
                        _lastChecked?.toLocal().toString() ?? '—',
                        context,
                      ),
                      if (_errorSnippet != null &&
                          _errorSnippet!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _errorSnippet!,
                            style: TextStyle(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(k, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              v,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
