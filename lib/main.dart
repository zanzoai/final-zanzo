// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
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
import 'package:zanzo_frontend/core/utils/market.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------
  // 🔔 Firebase (reads GoogleService-Info.plist on iOS, google-services.json on Android)
  // ---------------------------
  await Firebase.initializeApp();

  // Background/terminated push handler must be registered before runApp.
  FirebaseMessaging.onBackgroundMessage(firebasePushBackgroundHandler);

  final missing = AppConfig.missingKeys;
  if (missing.isNotEmpty) {
    runApp(_ConfigErrorApp(missing));
    return;
  }

  // ---------------------------
  // 🔐 Stripe publishable key (see lib/core/config/app_config.dart)
  // ---------------------------
  // The user's market (UK default / India) for local display conventions.
  await Market.load();

  Stripe.publishableKey = AppConfig.stripePublishableKey;
  await Stripe.instance.applySettings();

  // ---------------------------
  // 🟧 Supabase (realtime updates + legacy chat images)
  // ---------------------------
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    debug: kDebugMode,
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

/// Shown instead of a silent splash freeze when required Dart defines are absent.
/// Dismissed by rebuilding with the correct --dart-define-from-file flag.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp(this.missing);
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFCFAF6),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Missing build config',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB00020),
                  ),
                ),
                const SizedBox(height: 16),
                ...missing.map(
                  (k) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $k',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Run with:\nflutter run \\\n  --dart-define-from-file=config/test.json\n\nor:\n  make iphone',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFF444444),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
