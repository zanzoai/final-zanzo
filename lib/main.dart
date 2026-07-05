// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/common/home/home_screen.dart';
import 'features/legal/privacy_screen.dart';
import 'features/legal/settings_screen.dart';
import 'features/legal/task_rules_screen.dart';
import 'features/legal/terms_screen.dart';
import 'features/user/screens/account_data_screen.dart';
import 'features/user/screens/job_history_screen.dart';
import 'features/user/screens/profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------
  // 🔔 Firebase (reads GoogleService-Info.plist on iOS, google-services.json on Android)
  // ---------------------------
  await Firebase.initializeApp();

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zanzo AI',
      debugShowCheckedModeBanner: false,

      // ---- Theme ----
      theme: ThemeData(
        fontFamily: 'Roboto',
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.orangeAccent,
          foregroundColor: Colors.white,
        ),
      ),

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
      },
    );
  }
}
