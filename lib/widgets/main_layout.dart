// main_layout.dart
import 'package:flutter/material.dart';
import 'custom_app_bar.dart';
import 'custom_drawer.dart';
import '../model/user_model.dart';
import 'custom_app_bar_actions.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  final UserModel userModel;

  const MainLayout({super.key, required this.child, required this.userModel});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final contentW = screenW * 0.96;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: CustomAppBar(
        title: 'ExcelaratorAPI',
        actions: <Widget>[CustomAppBarActions(userModel: userModel)],
      ),
      drawer: const CustomDrawer(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF111827), Color(0xFF1F2A44)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: contentW),
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    );
  }
}
