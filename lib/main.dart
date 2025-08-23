import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/pages/account/billing_confirmation_page.dart';
import 'package:excelaratorapi/pages/account/manage_plan_page.dart';
import 'package:excelaratorapi/pages/account/profile_team_page.dart';
import 'package:excelaratorapi/pages/account/settings_page.dart';
import 'package:excelaratorapi/pages/dashboards/system_status_page.dart';
import 'package:excelaratorapi/pages/details/docs_page.dart';
import 'package:excelaratorapi/pages/details/reverse_db_launcher_page.dart';
import 'package:excelaratorapi/pages/details/sample_templates_page.dart';
import 'package:excelaratorapi/pages/details/support_admin_inbox.dart';
import 'package:excelaratorapi/pages/details/support_page.dart';
import 'package:excelaratorapi/pages/job/job_detail_page.dart';
import 'package:excelaratorapi/pages/job/jobs_list_page.dart';
import 'package:excelaratorapi/pages/job/new_conversion_page.dart';
import 'package:excelaratorapi/pages/job/upload_schema_page.dart';
import 'package:excelaratorapi/widgets/main_layout.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';

import 'package:excelaratorapi/service/user_manager.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'authentication/authwrapper.dart';
import 'model/user_model.dart';
import './pages/not_found_page.dart';

import 'theme/excelarator_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Small helper that lets GoRouter refresh when auth state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _sub;
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Firebase init ---
  const firebaseConfig = FirebaseOptions(
    apiKey: "AIzaSyDhjDgqn7nyUJ_YFIwzArVAR_GHkfgiwPA",
    authDomain: "excelaratorapi.firebaseapp.com",
    projectId: "excelaratorapi",
    storageBucket: "excelaratorapi.firebasestorage.app",
    messagingSenderId: "164609508734",
    appId: "1:164609508734:web:c17f6090d14f68f1045f2f",
    measurementId: "G-Q9EX94REFR",
  );
  await Firebase.initializeApp(options: firebaseConfig);

  // (If this needs Firebase, do it after init)
  await UserManager.initializeUser();

  final analytics = FirebaseAnalytics.instance;
  final firestore = FirebaseFirestore.instance;

  // --- Auth telemetry to Analytics + Firestore ---

  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user != null) {
      await analytics.setUserId(id: user.uid);
      await analytics.logLogin(
        loginMethod:
            user.providerData.isNotEmpty
                ? user.providerData.first.providerId
                : 'unknown',
      );
      await firestore.collection('auth_logs').add({
        'uid': user.uid,
        'email': user.email,
        'event': 'login',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } else {
      await analytics.setUserId(); // clear
      await analytics.logEvent(name: 'logout');
    }
  });

  // --- Router (auth-guarded) ---
  final authStream = FirebaseAuth.instance.authStateChanges();
  final router = GoRouter(
    initialLocation: '/home',
    debugLogDiagnostics: false,
    refreshListenable: GoRouterRefreshStream(authStream),
    observers: [FirebaseAnalyticsObserver(analytics: analytics)],
    redirect: (context, state) {
      final bool authed = FirebaseAuth.instance.currentUser != null;
      final bool goingToAuth = state.matchedLocation == '/auth';

      // Require auth for everything except /auth
      if (!authed && !goingToAuth) return '/auth';

      // If already authed, keep them out of /auth
      if (authed && goingToAuth) return '/home';

      return null;
    },
    routes: [
      // Auth screen
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (_, __) => const AuthWrapper(),
      ),

      // Home (you can keep this going to your shell or dashboard)
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (_, __) => const AuthWrapper(),
      ),
      GoRoute(
        path: '/jobs',
        name: 'jobs-list',
        builder: (_, __) => const JobsListPage(),
      ),
      GoRoute(
        path: '/convert',
        name: 'convert',
        builder: (_, __) => const NewConversionPage(),
      ),
      GoRoute(
        path: '/jobs/:jobId',
        name: 'job-detail',
        pageBuilder:
            (context, state) => MaterialPage(
              child: MainLayout(
                userModel: UserModel(),
                child: JobDetailPage(jobId: state.pathParameters['jobId']!),
              ),
            ),
      ),
      GoRoute(
        path: '/reverse',
        name: 'reverse',
        builder: (_, __) => const ReverseDbLauncherPage(),
      ),
      GoRoute(
        path: '/schema',
        name: 'upload-schema',
        builder: (_, __) => const UploadSchemaPage(),
      ),
      GoRoute(
        path: '/docs',
        name: 'docs',
        builder: (_, __) => const DocsPage(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (_, __) => const ProfileTeamPage(),
      ),
      GoRoute(
        path: '/supportadmin',
        name: 'supportadmin',
        builder: (_, __) => const SupportAdminInboxPage(),
      ),
      GoRoute(
        path: '/support',
        name: 'support',
        builder: (_, __) => const SupportPage(),
      ),
      GoRoute(
        path: '/status',
        name: 'status',
        builder: (_, __) => const SystemStatusPage(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (_, __) => const SettingsPage(),
      ),
      GoRoute(
        path: '/templates',
        name: 'templates',
        builder: (_, __) => SampleTemplatesPage(),
      ),
      // Account root
      GoRoute(
        path: '/account',
        name: 'account',
        builder: (_, __) => const AuthWrapper(),
        routes: [
          // Manage plan
          GoRoute(
            path: 'plan',
            name: 'account-plan',
            builder: (_, __) => const ManagePlanPage(),
            routes: [
              // Stripe Checkout success (first-time purchase)
              GoRoute(
                path: 'success',
                name: 'account-plan-success',
                pageBuilder:
                    (context, state) => MaterialPage(
                      child: BrandedShell(
                        child: BillingConfirmationPage.fromPath(
                          '/account/plan/success',
                        ),
                      ),
                    ),
              ),

              // In-place plan change (no Checkout)
              GoRoute(
                path: 'changed',
                name: 'account-plan-changed',
                pageBuilder:
                    (context, state) => MaterialPage(
                      child: BrandedShell(
                        child: BillingConfirmationPage.fromPath(
                          '/account/plan/changed',
                        ),
                      ),
                    ),
              ),

              // Cancellation confirmation
              GoRoute(
                path: 'cancelled',
                name: 'account-plan-cancelled',
                pageBuilder:
                    (context, state) => MaterialPage(
                      child: BrandedShell(
                        child: BillingConfirmationPage.fromPath(
                          '/account/plan/cancelled',
                        ),
                      ),
                    ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, __) => const NotFoundPage(),
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => UserModel()..fetchUserData(),
      child: MyApp(router: router, analytics: analytics),
    ),
  );
}

class MyApp extends StatelessWidget {
  final GoRouter router;
  final FirebaseAnalytics analytics;
  const MyApp({super.key, required this.router, required this.analytics});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ExcelaratorAPI',
      theme: excelaratorLight(),
      darkTheme: excelaratorLight(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', '')],
    );
  }
}

/// Optional: keep your nice branded shell around the body
class BrandedShell extends StatelessWidget {
  final Widget child;
  const BrandedShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SvgPicture.asset(
                'assets/brand/excelarator_mark.svg',
                width: 28,
                height: 28,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
            const Text('ExcelaratorAPI'),
          ],
        ),
        centerTitle: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111827), Color(0xFF1F2A44)],
          ),
        ),
        child: child,
      ),
    );
  }
}
