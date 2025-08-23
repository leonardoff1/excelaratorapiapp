import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _message = '';
  bool _success = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _message = '';
      _success = false;
      _isSubmitting = true;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      setState(() {
        _success = true;
        _isSubmitting = false;
        _message =
            '${AppLocalizations.of(context)!.link_para_redefinir_sua_senha} ${_emailController.text.trim()}';
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _success = false;
        _isSubmitting = false;
        _message =
            '${AppLocalizations.of(context)!.erro_ocorreu_para_redefinir_senha} ${e.message ?? ''}'
                .trim();
      });
    } catch (_) {
      setState(() {
        _success = false;
        _isSubmitting = false;
        _message = AppLocalizations.of(context)!.erro_desconhecido_ocorreu;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenW = MediaQuery.of(context).size.width;
    final cardW = math.min(screenW * 0.9, 480.0);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            SvgPicture.asset(
              'assets/brand/excelarator_mark.svg',
              width: 28,
              height: 28,
              colorFilter: ColorFilter.mode(
                isDark ? Colors.white : cs.primary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 10),
            Text(AppLocalizations.of(context)!.redefinir_senha),
          ],
        ),
        centerTitle: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF111827), Color(0xFF1F2A44)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: cardW),
            child: Card(
              color: isDark ? const Color(0xFF111827) : Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header text
                    Text(
                      AppLocalizations.of(
                        context,
                      )!.entre_seu_endereco_de_email_redefinir_senha,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isDark ? Colors.white : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Form
                    Form(
                      key: _formKey,
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return AppLocalizations.of(
                              context,
                            )!.usuario_nao_encontrado;
                          }
                          final s = v.trim();
                          if (!s.contains('@') || !s.contains('.')) {
                            return AppLocalizations.of(context)!.falha_de_login;
                          }
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSubmitting ? null : _resetPassword,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            _isSubmitting
                                ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.enviar_email_para_redefinir_senha,
                                ),
                      ),
                    ),

                    if (_message.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_success ? cs.secondary : cs.error)
                              .withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (_success ? cs.secondary : cs.error)
                                .withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _success
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              size: 20,
                              color: _success ? cs.secondary : cs.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _message,
                                style: TextStyle(
                                  color: _success ? cs.secondary : cs.error,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}
