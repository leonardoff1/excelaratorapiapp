import 'package:flutter/material.dart';
import 'package:excelaratorapi/pages/dashboards/home_dashboard.dart';
import 'package:excelaratorapi/service/user_manager.dart';
import '../model/user_model.dart';
import '../widgets/main_layout.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userModel = UserModel();
    UserManager.initializeUser();

    return FutureBuilder<void>(
      future: userModel.fetchUserData(),
      builder: (context, snapshot) {
        // THEME shortcuts
        final cs = Theme.of(context).colorScheme;

        if (snapshot.connectionState == ConnectionState.waiting) {
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Loading your workspace…',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
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
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  color:
                      Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF111827)
                          : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: cs.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Error loading user data',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(color: cs.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // If you only proceed when we have a name, keep this check.
        // Otherwise, use email as a fallback.
        final displayName = _friendlyName(userModel);

        if (displayName.isNotEmpty) {
          return MainLayout(
            userModel: userModel,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Your actual dashboard
                  Expanded(child: HomeDashboardPage()),
                ],
              ),
            ),
          );
        }

        // Fallback if user has no name/email
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
            child: Text(
              'No user data available',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ),
        );
      },
    );
  }

  String _friendlyName(UserModel userModel) {
    final first = (userModel.firstName ?? '').trim();
    final last = (userModel.lastName ?? '').trim();
    final email = (userModel.email ?? '').trim();
    final name = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (name.isNotEmpty) return name;
    return email; // fallback to email if name not set
  }
}
