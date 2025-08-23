import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/model/models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:excelaratorapi/authentication/pending_approval_screen.dart';
import 'authwrapper.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companyIdController =
      TextEditingController(); // optional (not shown in UI currently)
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _showPassword = false;
  bool _showConfirm = false;
  bool _isSubmitting = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _companyIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _errorMessage = '';
      _isSubmitting = true;
    });

    try {
      // 1) Auth account
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final user = cred.user!;
      await user.sendEmailVerification();
      await user.updateDisplayName(
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
      );

      // 2) Build a UserProfile model (your data shape)
      final profile = UserProfile(
        id: user.uid,
        email: user.email,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        companyId: 'excelaratorapi',
        admin: false,
        approved: false,
        // createdAt comes from server timestamp on write
        orgId: 'org-${user.uid}', // simple default; swap later if you add Orgs
      );

      // 3) Persist to Firestore using your model
      final data = profile.toMap();
      // Ensure server timestamps (your model accepts DateTime, so set it on write)
      data['createdAt'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(data);

      // 4) Optionally: seed an auth log (skip if you already log elsewhere)
      // await FirebaseFirestore.instance.collection('auth_logs').add({
      //   'uid': user.uid,
      //   'email': user.email,
      //   'event': 'signup',
      //   'timestamp': FieldValue.serverTimestamp(),
      // });

      // 5) Sign out and route to "pending approval"
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage =
            e.message ??
            AppLocalizations.of(context)!.ocorreu_um_erro_durante_registro;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '${AppLocalizations.of(context)!.erro_inesperado} $e';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screenW = MediaQuery.of(context).size.width;
    final cardW = math.min(screenW * 0.9, 720.0);

    return Scaffold(
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Brand header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/brand/excelarator_mark.svg',
                            width: 32,
                            height: 32,
                            colorFilter: ColorFilter.mode(
                              isDark ? Colors.white : cs.primary,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'ExcelaratorAPI',
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.criar_conta,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(
                          context,
                        )!.preencha_informacoes_abaixo_comecar,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white70 : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // First / Last
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              controller: _firstNameController,
                              label: AppLocalizations.of(context)!.name,
                              icon: Icons.person,
                              autofill: const [AutofillHints.givenName],
                              validator:
                                  (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? AppLocalizations.of(
                                            context,
                                          )!.campo_obrigatorio
                                          : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              controller: _lastNameController,
                              label: AppLocalizations.of(context)!.lastname,
                              icon: Icons.person_outline,
                              autofill: const [AutofillHints.familyName],
                              validator:
                                  (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? AppLocalizations.of(
                                            context,
                                          )!.campo_obrigatorio
                                          : null,
                            ),
                          ),
                        ],
                      ),

                      // Phone (you can add Company here later if you like)
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              controller: _phoneController,
                              label: AppLocalizations.of(context)!.phone,
                              icon: Icons.phone,
                              keyboardType: TextInputType.phone,
                              autofill: const [AutofillHints.telephoneNumber],
                              validator:
                                  (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? AppLocalizations.of(
                                            context,
                                          )!.campo_obrigatorio
                                          : null,
                            ),
                          ),
                        ],
                      ),

                      // Email
                      _textField(
                        controller: _emailController,
                        label: 'Email',
                        icon: Icons.email,
                        keyboardType: TextInputType.emailAddress,
                        autofill: const [AutofillHints.email],
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty ||
                              !s.contains('@') ||
                              !s.contains('.')) {
                            return AppLocalizations.of(
                              context,
                            )!.digite_email_valido;
                          }
                          return null;
                        },
                      ),

                      // Password / Confirm
                      _passwordField(
                        controller: _passwordController,
                        label: AppLocalizations.of(context)!.password,
                        visible: _showPassword,
                        onToggle:
                            () =>
                                setState(() => _showPassword = !_showPassword),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty || s.length < 6) {
                            return AppLocalizations.of(
                              context,
                            )!.senha_deve_pelo_menos_caracteres;
                          }
                          return null;
                        },
                      ),
                      _passwordField(
                        controller: _confirmController,
                        label: AppLocalizations.of(context)!.confirmar_senha,
                        visible: _showConfirm,
                        onToggle:
                            () => setState(() => _showConfirm = !_showConfirm),
                        validator: (v) {
                          if (v != _passwordController.text) {
                            return AppLocalizations.of(
                              context,
                            )!.senhas_nao_conferem;
                          }
                          return null;
                        },
                      ),

                      // Error banner
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.error.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.error.withOpacity(0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: cs.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(
                                    color: cs.error,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _isSubmitting ? null : _register,
                          style: FilledButton.styleFrom(
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
                                    AppLocalizations.of(context)!.criar_conta,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AuthWrapper(),
                            ),
                          );
                        },
                        child: Text(
                          AppLocalizations.of(context)!.ja_tem_uma_conta_entrar,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
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

  // ---- Field helpers ----

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    List<String>? autofill,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        autofillHints: autofill,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: validator,
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: !visible,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock),
          suffixIcon: IconButton(
            tooltip: visible ? 'Hide' : 'Show',
            icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
            onPressed: onToggle,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: validator,
      ),
    );
  }
}
