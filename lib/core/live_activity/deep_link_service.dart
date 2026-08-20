// lib/core/live_activity/deep_link_service.dart
//
// Handles `zanzo://track?jobId=…&title=…` deep links delivered by tapping the
// job-tracking Live Activity / Dynamic Island. Native side is
// ios/Runner/DeepLinkBridge.swift over the "zanzo/deeplink" MethodChannel.
//
// Routes to the specific task's TrackJobScreen using a global navigator key.
// No-op off iOS.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zanzo_frontend/features/user/screens/track_job_screen.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  /// Attach to MaterialApp so we can navigate from outside the widget tree.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const MethodChannel _channel = MethodChannel('zanzo/deeplink');

  bool get _supported => !kIsWeb && Platform.isIOS;
  String? _lastJobId;

  /// Call once at startup (after the first frame). Registers the warm-link
  /// handler and drains any cold-start link.
  Future<void> init() async {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        _route(_asMap(call.arguments));
      }
    });
    try {
      final initial = await _channel.invokeMethod<dynamic>('getInitialLink');
      if (initial != null) _route(_asMap(initial));
    } catch (e) {
      debugPrint('DeepLinkService.getInitialLink failed: $e');
    }
  }

  Map<String, String> _asMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
    return const {};
  }

  void _route(Map<String, String> data) {
    final jobId = (data['jobId'] ?? '').trim();
    if (jobId.isEmpty) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    // Avoid stacking the same task twice if tapped repeatedly.
    if (_lastJobId == jobId && nav.canPop()) return;
    // Skip if a TrackJobScreen for this job is already open (e.g. Home
    // auto-opened it), so the deep link doesn't stack a duplicate.
    if (TrackJobScreen.isOpenForJob(jobId)) return;
    _lastJobId = jobId;

    final title = (data['title'] ?? '').trim();
    nav.push(
      MaterialPageRoute(
        builder: (_) => TrackJobScreen(
          taskTitle: title.isEmpty ? 'Your Zanzo task' : title,
          userLocation: '',
          jobId: jobId,
        ),
      ),
    );
  }
}
