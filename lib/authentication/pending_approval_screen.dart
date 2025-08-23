import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  late Timer _timer;
  bool _checking = false;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    // auto‑check every 15 s
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _checkStatus());
    _checkStatus(); // first immediate check
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_checking) return;
    _checking = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // reload e‑mail verification status
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser!;

      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(refreshedUser.uid)
              .get();

      final approved = refreshedUser.emailVerified;

      if (refreshedUser.emailVerified) {
        // both conditions satisfied → restart auth flow
        if (mounted) Navigator.pop(context); // AuthWrapper will take over
        context.go('/home');
        return;
      }

      setState(() {
        _statusText =
            approved
                ? AppLocalizations.of(context)!.email_ainda_nao_verificado
                : AppLocalizations.of(
                  context,
                )!.conta_aguardando_aprovacao_administrador;
      });
    } catch (e) {
      setState(
        () =>
            _statusText =
                '${AppLocalizations.of(context)!.erro_verificar_status} $e',
      );
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.hourglass_top, size: 80, color: Colors.blue),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)!.obrigado_por_registrar,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _statusText ??
                      '${AppLocalizations.of(context)!.estamos_revisando_seu_cadastro}'
                          '${AppLocalizations.of(context)!.voce_recebera_um_email_quando_for_liberada}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: Text(AppLocalizations.of(context)!.verificar_agora),
                    onPressed: _checkStatus,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                  child: Text(AppLocalizations.of(context)!.exit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
