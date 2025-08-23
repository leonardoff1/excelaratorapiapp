import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:excelaratorapi/service/user_manager.dart';

class PlanSuccessPage extends StatefulWidget {
  final String?
  sessionId; // pass from route: state.uri.queryParameters['session_id']
  const PlanSuccessPage({super.key, required this.sessionId});

  @override
  State<PlanSuccessPage> createState() => _PlanSuccessPageState();
}

class _PlanSuccessPageState extends State<PlanSuccessPage> {
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();

    // We need the query param "mode" to decide if this page should confirm or redirect.
    // Read it after first frame so GoRouter's context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mode = GoRouterState.of(context).uri.queryParameters['mode'];
      if (mode == 'changed') {
        context.go('/account/plan/changed');
        return;
      }
      if (mode == 'cancelled') {
        context.go('/account/plan/cancelled');
        return;
      }

      // Only confirm with backend if we actually have a Stripe session_id
      if (widget.sessionId != null && widget.sessionId!.isNotEmpty) {
        _confirm();
      } else {
        setState(() => _error = 'Missing session_id in URL.');
      }
    });
  }

  Future<void> _confirm() async {
    try {
      final apiBase =
          UserManager.currentUser?.userURL ?? 'http://localhost:5001';
      final res = await http.post(
        Uri.parse('$apiBase/api/billing/checkout/confirm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionId': widget.sessionId}),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => _done = true);
        if (!mounted) return;

        // After confirmation, show the live status page that watches Firestore:
        context.go(
          '/account/plan/success',
        ); // this route should render BillingConfirmationPage(success)
      } else {
        setState(
          () => _error = res.body.isNotEmpty ? res.body : 'Unknown error',
        );
      }
    } catch (e) {
      setState(() => _error = 'Network error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;

    return Scaffold(
      appBar: AppBar(title: const Text('Plan success')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              _error != null
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => context.go('/account/plan'),
                        child: const Text('Back to Manage Plan'),
                      ),
                    ],
                  )
                  : _done
                  ? const SizedBox() // we immediately navigate away on success
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Confirming your subscription…\n(session: ${sessionId ?? '—'})',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}
