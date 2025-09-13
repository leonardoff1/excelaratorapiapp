import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excelaratorapi/authentication/email_verification.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../homescreen.dart';
import './loginscreen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          // Check if the user is logged in
          User? user = snapshot.data;
          if (user == null) {
            // User is not logged in, show login screen
            return const LoginScreen();
          } else {
            // Log logout BEFORE signin
            // FirebaseFirestore.instance.collection('auth_logs').add({
            //   'uid': user.uid,
            //   'email': user.email,
            //   'event': 'refresh',
            //   'timestamp': FieldValue.serverTimestamp(),
            // });
            // User is logged in, show home screen

            return StreamBuilder<DocumentSnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  ); // loading
                }

                final approved = user.emailVerified;
                if (!approved) return EmailVerificationPopup(); // wait

                return HomeScreen(); // 🎉 go
              },
            );
          }
        }
        // Waiting for authentication state to be available
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
