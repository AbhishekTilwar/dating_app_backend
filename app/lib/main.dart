import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:spark/core/theme/app_theme.dart';
import 'package:spark/core/router/app_router.dart';

/// App entry point and initializer.
/// 1. Binds Flutter, 2. Initializes Firebase, 3. Runs app with router.
/// First route is `/` (SplashScreen) — see [AppRouter.createRouter] initialLocation.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase.initializeApp failed: $e');
    debugPrint('$st');
    rethrow;
  }
  runApp(const SparkApp());
}

class SparkApp extends StatelessWidget {
  const SparkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Crossed',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: AppRouter.createRouter(),
    );
  }
}
