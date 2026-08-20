// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/live_activity/deep_link_service.dart';
import 'core/notifications/push_router.dart';
import 'core/theme/app_theme.dart';
import 'features/common/home/home_screen.dart';
import 'features/legal/privacy_screen.dart';
import 'features/legal/settings_screen.dart';
import 'features/legal/task_rules_screen.dart';
import 'features/legal/terms_screen.dart';
import 'features/user/screens/account_data_screen.dart';
import 'features/user/screens/cancelled_refunds_screen.dart';
import 'features/user/screens/job_history_screen.dart';
import 'features/user/screens/profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------
  // 🔔 Firebase (reads GoogleService-Info.plist on iOS, google-services.json on Android)
  // ---------------------------
  await Firebase.initializeApp();

  // Background/terminated push handler must be registered before runApp.
  FirebaseMessaging.onBackgroundMessage(firebasePushBackgroundHandler);

  // ---------------------------
  // 🔐 Stripe Publishable Key
  // ---------------------------
  Stripe.publishableKey =
      'pk_test_51TZ9da3OAXc8h9NvpMErQIZuJiuxoMekiYD9DIMHdlIqenOxpdfNFbsoxAhEjvkNjLW7vWwiKJlV52VjRKzTI36q007are6pr1';
  await Stripe.instance.applySettings();

  // ---------------------------
  // 🟧 Supabase Initialization
  // ---------------------------
  await Supabase.initialize(
    url: 'https://hfgoixompxqymezvjllk.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhmZ29peG9tcHhxeW1lenZqbGxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ2MDI2MDgsImV4cCI6MjA3MDE3ODYwOH0.E_T-W4MNpVN0AnGkQdIzvEeWtgXoDDKXlFL8P-H3ba0',
    debug: true, // keep ON during development
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Handle Live Activity / Dynamic Island deep links once the tree is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.init();
      // App-wide FCM routing (in-task chat `new_message` pushes, etc.).
      PushRouter.instance.init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zanzo AI',
      debugShowCheckedModeBanner: false,
      navigatorKey: DeepLinkService.navigatorKey,

      // ---- Theme ----
      // Single source of truth — see lib/core/theme/app_theme.dart
      theme: AppTheme.light,

      // ---------------------------
      // 🏠 App Entry Point
      // ---------------------------
      home: const HomeScreen(),

      // ---------------------------
      // 🔀 App Routes
      // ---------------------------
      routes: {
        '/home': (context) => const HomeScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/history': (context) => const JobHistoryScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/terms': (context) => const TermsScreen(),
        '/privacy': (context) => const PrivacyScreen(),
        '/task_rules': (context) => const TaskRulesScreen(),
        '/account_data': (_) => const AccountDataScreen(),
        '/cancelled_refunds': (_) => const CancelledRefundsScreen(),
      },
    );
  }
}
