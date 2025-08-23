import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../authentication/loginscreen.dart';
import '../model/user_model.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class CustomAppBarActions extends StatelessWidget {
  final UserModel userModel;

  const CustomAppBarActions({super.key, required this.userModel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder(
      future: userModel.fetchUserData(), // assumes Future<void>
      builder: (context, snapshot) {
        final widgets = <Widget>[];

        if (snapshot.connectionState == ConnectionState.waiting) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
            ),
          );
        } else {
          final name = _displayName(userModel);
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  // Initials avatar (brand primary + onPrimary text)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(name),
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Friendly name
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      name.isEmpty ? '—' : name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          );
        }

        // Actions menu (includes Sign out)
        widgets.add(
          PopupMenuButton<_MenuAction>(
            tooltip: AppLocalizations.of(context)!.exit,
            position: PopupMenuPosition.under,
            onSelected: (value) async {
              if (value == _MenuAction.signOut) {
                await _logout(context);
              }
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem<_MenuAction>(
                    value: _MenuAction.signOut,
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: cs.error, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.exit,
                          style: TextStyle(color: cs.error),
                        ),
                      ],
                    ),
                  ),
                ],
            icon: Icon(Icons.more_vert, color: cs.onSurface),
          ),
        );

        return Row(children: widgets);
      },
    );
  }

  String _displayName(UserModel userModel) {
    final first = (userModel.firstName ?? '').trim();
    final last = (userModel.lastName ?? '').trim();
    final email = (userModel.email ?? '').trim();
    if (first.isNotEmpty || last.isNotEmpty) {
      return [first, last].where((s) => s.isNotEmpty).join(' ');
    }
    return email;
  }

  String _initials(String nameOrEmail) {
    final s = nameOrEmail.trim();
    if (s.isEmpty) return '?';
    // If it's an email, use the first letter
    if (s.contains('@')) return s[0].toUpperCase();
    final parts = s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return s[0].toUpperCase();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Future<void> _logout(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('auth_logs').add({
          'uid': user.uid,
          'email': user.email,
          'event': 'logout',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error logging out: $e")));
      }
    }
  }
}

enum _MenuAction { signOut }
