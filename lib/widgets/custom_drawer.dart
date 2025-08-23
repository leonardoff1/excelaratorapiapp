// custom_drawer.dart (fixed: no overflow)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/pages/details/docs_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:excelaratorapi/authentication/loginscreen.dart';
import 'package:excelaratorapi/model/user_model.dart';
import 'package:excelaratorapi/service/user_manager.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  void _go(BuildContext context, String path) {
    Navigator.of(context).pop(); // close the drawer
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final user = UserManager.currentUser;

    final isAdmin = (user?.isAdmin == true) || (user?.admin == true);

    final isSupport = false;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Keep header fixed
            DrawerHeader(
              margin: EdgeInsets.zero,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF111827), Color(0xFF1F2A44)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/brand/excelarator_mark.svg',
                    width: 40,
                    height: 40,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ExcelaratorAPI',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (user != null)
                          Text(
                            user.email ?? user.firstName ?? user.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable middle content
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _sectionHeader(context, 'Build'),
                  _item(
                    context,
                    icon: Icons.home_outlined,
                    label: 'Home',
                    onTap: () => _go(context, '/home'),
                  ),
                  _item(
                    context,
                    icon: Icons.auto_awesome_motion_outlined,
                    label: 'New Conversion',
                    onTap: () => _go(context, '/convert'),
                  ),
                  _item(
                    context,
                    icon: Icons.storage_outlined,
                    label: 'Reverse-engineer DB',
                    onTap: () {
                      Navigator.pop(context); // close drawer
                      context.go('/schema');
                    },
                  ),
                  _item(
                    context,
                    icon: Icons.history_outlined,
                    label: 'Jobs',
                    onTap: () => _go(context, '/jobs'),
                  ),
                  _item(
                    context,
                    icon: Icons.menu_book_outlined,
                    label: 'Docs',
                    onTap: () => _go(context, '/docs'),
                  ),

                  _sectionHeader(context, 'Account'),

                  if (isAdmin)
                    _item(
                      context,
                      icon: Icons.credit_card_outlined,
                      label: 'Manage plan',
                      onTap: () => _go(context, '/account/plan'),
                    ),
                  if (isAdmin)
                    _item(
                      context,
                      icon: Icons.group_outlined,
                      label: 'Profile & Team',
                      onTap: () => _go(context, '/profile'),
                    ),

                  // if (isAdmin) ...[
                  //   _sectionHeader(context, 'Admin'),
                  //   _item(
                  //     context,
                  //     icon: Icons.analytics_outlined,
                  //     label: 'Usage & Limits',
                  //     onTap:
                  //         () => _navigateToPage(
                  //           context,
                  //           const _StubPage(title: 'Usage & Limits'),
                  //         ),
                  //   ),
                  //   _item(
                  //     context,
                  //     icon: Icons.receipt_long_outlined,
                  //     label: 'Billing Admin',
                  //     onTap:
                  //         () => _navigateToPage(
                  //           context,
                  //           const _StubPage(title: 'Billing Admin'),
                  //         ),
                  //   ),
                  // ],
                  _sectionHeader(context, 'Help'),
                  _item(
                    context,
                    icon: Icons.help_outline,
                    label: 'Support',
                    onTap: () => _go(context, '/support'),
                  ),
                  if (isSupport)
                    _item(
                      context,
                      icon: Icons.help_outline,
                      label: 'Support Inbox',
                      onTap: () => _go(context, '/supportadmin'),
                    ),
                  _item(
                    context,
                    icon: Icons.cloud_done_outlined,
                    label: 'System status',
                    onTap: () => _go(context, '/status'),
                  ),

                  const SizedBox(height: 8), // small bottom breathing room
                ],
              ),
            ),

            const Divider(height: 1),

            // Fixed footer actions (never scroll out, never overflow)
            _item(
              context,
              icon: Icons.logout,
              label: AppLocalizations.of(context)!.exit,
              destructive: true,
              onTap: () => _logout(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool destructive = false,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = destructive ? cs.error : cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          label,
          style: destructive ? TextStyle(color: cs.error) : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        hoverColor: (destructive ? cs.error : cs.primary).withOpacity(0.06),
        onTap: onTap,
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Erro ao sair: $e")));
    }
  }

  void _navigateToPage(BuildContext context, Widget page) {
    final userModel = UserModel();
    UserManager.initializeUser();
    Navigator.pop(context); // Close drawer
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MainLayout(userModel: userModel, child: page),
      ),
    );
  }
}

// Tiny stub for pages you haven't built yet (safe to delete when replaced)
class _StubPage extends StatelessWidget {
  final String title;
  const _StubPage({required this.title});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text('Coming soon')),
    );
  }
}
