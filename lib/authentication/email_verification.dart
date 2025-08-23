import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class EmailVerificationPopup extends StatefulWidget {
  const EmailVerificationPopup({super.key});

  @override
  State<EmailVerificationPopup> createState() => _EmailVerificationPopupState();
}

class _EmailVerificationPopupState extends State<EmailVerificationPopup> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // Show dialog after first frame so context & scaffold are ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowDialog());
  }

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<void> _maybeShowDialog() async {
    final u = _user;
    if (!mounted || _dialogShown) return;
    if (u == null) return; // not logged in
    if (!u.emailVerified) {
      _dialogShown = true;
      _showEmailVerificationDialog();
    }
  }

  void _showEmailVerificationDialog() {
    final rootCtx = context; // keep a reference to the page context
    bool busy = false;

    showDialog(
      context: rootCtx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            Future<void> setBusy(bool v) async {
              if (mounted) setDialogState(() => busy = v);
            }

            return AlertDialog(
              title: Text(
                AppLocalizations.of(rootCtx)!.um_e_mail_verificacao_foi_env,
              ),
              content: Text(
                AppLocalizations.of(rootCtx)!.seu_email_nao_foi_verificado,
              ),
              actions: <Widget>[
                TextButton(
                  onPressed:
                      busy
                          ? null
                          : () async {
                            await setBusy(true);
                            // Refresh the auth user; Firebase only updates emailVerified after reload
                            await FirebaseAuth.instance.currentUser?.reload();
                            final refreshed = FirebaseAuth.instance.currentUser;
                            await setBusy(false);

                            if (refreshed != null && refreshed.emailVerified) {
                              // 1) Close the dialog
                              if (Navigator.of(
                                dialogCtx,
                                rootNavigator: true,
                              ).canPop()) {
                                Navigator.of(
                                  dialogCtx,
                                  rootNavigator: true,
                                ).pop();
                              }
                              // 2) Navigate using the root page context
                              if (rootCtx.mounted) rootCtx.go('/home');
                            } else {
                              ScaffoldMessenger.of(rootCtx).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Still not verified. Please click the link in your email, then tap Continue.',
                                  ),
                                ),
                              );
                            }
                          },
                  child:
                      busy
                          ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Continue'),
                ),
                TextButton(
                  onPressed:
                      busy
                          ? null
                          : () async {
                            await setBusy(true);
                            try {
                              final u = FirebaseAuth.instance.currentUser;
                              if (u != null) {
                                await u.sendEmailVerification();
                                if (rootCtx.mounted) {
                                  ScaffoldMessenger.of(rootCtx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(
                                          rootCtx,
                                        )!.email_verificacao_enviado,
                                      ),
                                    ),
                                  );
                                }
                              }
                            } finally {
                              await setBusy(false);
                            }
                          },
                  child: Text(AppLocalizations.of(rootCtx)!.reenviar_email),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? '—';
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.account)),
      body: Center(child: Text(email)),
    );
  }
}
