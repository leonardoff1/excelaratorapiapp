// reverse_db_launcher_page.dart
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ReverseDbLauncherPage extends StatefulWidget {
  const ReverseDbLauncherPage({super.key});

  @override
  State<ReverseDbLauncherPage> createState() => _ReverseDbLauncherPageState();
}

class _ReverseDbLauncherPageState extends State<ReverseDbLauncherPage> {
  // Optional: latest links live in Firestore so you can rotate them without app deploys.
  // Path suggestion: /metadata/downloads
  Future<Map<String, dynamic>> _loadLinks() async {
    try {
      final snap =
          await FirebaseFirestore.instance
              .collection('metadata')
              .doc('downloads')
              .get();
      if (snap.exists) {
        final m = (snap.data() ?? {})..removeWhere((k, v) => v == null);
        return Map<String, dynamic>.from(m);
      }
    } catch (_) {
      /* fall back */
    }
    // Fallback defaults (replace with your Storage/Hosting URLs)
    return {
      'win': 'https://your-host/downloads/Excelarator-ReverseDB-Setup.exe',
      'mac': 'https://your-host/downloads/Excelarator-ReverseDB.dmg',
      'linux': 'https://your-host/downloads/Excelarator-ReverseDB.AppImage',
      'jar': 'https://your-host/downloads/excelarator-reverser-cli.jar',
      // Optional checksums (display only)
      'winSha256': '—',
      'macSha256': '—',
      'linuxSha256': '—',
      'jarSha256': '—',
      // Optional release notes URL
      'notes': 'https://your-host/downloads/release-notes',
    };
  }

  String _preferredKey() {
    if (kIsWeb) return 'win'; // default suggestion on web
    if (Platform.isMacOS) return 'mac';
    if (Platform.isWindows) return 'win';
    if (Platform.isLinux) return 'linux';
    return 'win';
  }

  Future<void> _download(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open download link')),
      );
    }
  }

  Widget _downloadCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required String? url,
    String? sha256,
    bool highlight = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final border = Border.all(
      color: (highlight ? cs.primary : cs.outlineVariant).withOpacity(
        highlight ? 0.5 : 0.6,
      ),
      width: highlight ? 1.4 : 1,
    );
    return Card(
      elevation: highlight ? 1.5 : 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: cs.primary.withOpacity(0.12),
                  child: Icon(icon, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                if (highlight) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Recommended',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                FilledButton.icon(
                  onPressed: url == null ? null : () => _download(url),
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
            if (sha256 != null &&
                sha256.trim().isNotEmpty &&
                sha256 != '—') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'SHA-256: ',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Expanded(
                    child: Text(
                      sha256,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy checksum',
                    onPressed:
                        () => Clipboard.setData(ClipboardData(text: sha256)),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cliCard(String? jarUrl, String? sha256) {
    final cs = Theme.of(context).colorScheme;
    final cmd = 'java -jar excelarator-reverser-cli.jar --wizard';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, size: 22),
                const SizedBox(width: 8),
                Text(
                  'CLI / JAR (Java 17+)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: jarUrl == null ? null : () => _download(jarUrl),
                  icon: const Icon(Icons.download),
                  label: const Text('Download JAR'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Prefer a portable CLI? Download the JAR and run the wizard locally (works on macOS, Windows, Linux).',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      cmd,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy command',
                    onPressed:
                        () => Clipboard.setData(
                          const ClipboardData(
                            text:
                                'java -jar excelarator-reverser-cli.jar --wizard',
                          ),
                        ),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
            ),
            if (sha256 != null &&
                sha256.trim().isNotEmpty &&
                sha256 != '—') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'SHA-256: ',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Expanded(
                    child: Text(
                      sha256,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy checksum',
                    onPressed:
                        () => Clipboard.setData(ClipboardData(text: sha256)),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Reverse-engineer Database')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadLinks(),
        builder: (context, snap) {
          final data = snap.data ?? const {};
          final preferred = _preferredKey();
          final mac = data['mac'] as String?;
          final win = data['win'] as String?;
          final linux = data['linux'] as String?;
          final jar = data['jar'] as String?;
          final macSha = data['macSha256'] as String?;
          final winSha = data['winSha256'] as String?;
          final linSha = data['linuxSha256'] as String?;
          final jarSha = data['jarSha256'] as String?;

          final loading = snap.connectionState == ConnectionState.waiting;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              // Hero / intro
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Run the desktop wizard to reverse-engineer your DB',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'The wizard connects directly to your database (even localhost), extracts the schema, and uploads a JSON manifest to Excelarator. '
                        'Then your normal conversion flow runs in the cloud—just like spreadsheets.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.secondary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cs.secondary.withOpacity(0.30),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: cs.secondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                kIsWeb
                                    ? 'Browsers cannot open DB sockets; use the desktop wizard.'
                                    : (Platform.isAndroid || Platform.isIOS)
                                    ? 'Mobile cannot open DB sockets; use the desktop wizard.'
                                    : 'You’re on desktop—download and run the wizard for your OS.',
                                style: TextStyle(color: cs.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              if (loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                // OS-specific cards
                _downloadCard(
                  label: 'macOS',
                  subtitle: 'Universal .dmg (Apple Silicon & Intel)',
                  icon: Icons.laptop_mac,
                  url: mac,
                  sha256: macSha,
                  highlight: preferred == 'mac',
                ),
                _downloadCard(
                  label: 'Windows',
                  subtitle: 'Signed installer (.exe)',
                  icon: Icons.desktop_windows,
                  url: win,
                  sha256: winSha,
                  highlight: preferred == 'win',
                ),
                _downloadCard(
                  label: 'Linux',
                  subtitle: 'AppImage (.AppImage) or tarball',
                  icon: Icons.laptop,
                  url: linux,
                  sha256: linSha,
                  highlight: preferred == 'linux',
                ),

                const SizedBox(height: 8),
                _cliCard(jar, jarSha),

                const SizedBox(height: 16),
                if (data['notes'] != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed:
                          () => launchUrl(
                            Uri.parse(data['notes'] as String),
                            mode: LaunchMode.externalApplication,
                          ),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Release notes & requirements'),
                    ),
                  ),
              ],

              const SizedBox(height: 16),

              // How it works
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What happens next',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      _step(
                        '1',
                        'Connect',
                        'Point the wizard at Postgres/MySQL/SQL Server/Oracle/SQLite (localhost works).',
                      ),
                      _step(
                        '2',
                        'Extract',
                        'Pick schemas/tables. We build a JSON schema manifest—no data is copied.',
                      ),
                      _step(
                        '3',
                        'Upload',
                        'The wizard uploads the JSON to your secure Firebase Storage path.',
                      ),
                      _step(
                        '4',
                        'Generate',
                        'Excelarator picks up the upload and runs the same conversion pipeline.',
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

  Widget _step(String n, String title, String body) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: cs.primary.withOpacity(0.12),
            child: Text(
              n,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
