// lib/core/live_activity/job_live_activity.dart
//
// Thin Dart wrapper over the native iOS Live Activity (Dynamic Island + Lock
// Screen) for job tracking. Backed by the `zanzo/live_activity` MethodChannel
// implemented in ios/Runner/LiveActivityBridge.swift.
//
// No-op on non-iOS platforms and on iOS < 16.1 (the native side degrades
// gracefully), so callers can invoke these unconditionally.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JobLiveActivity {
  JobLiveActivity._();
  static final JobLiveActivity instance = JobLiveActivity._();

  static const MethodChannel _channel = MethodChannel('zanzo/live_activity');

  bool get _supported => !kIsWeb && Platform.isIOS;

  /// Whether the user has Live Activities enabled and the OS supports them.
  Future<bool> areEnabled() async {
    if (!_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('areEnabled')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isActive() async {
    if (!_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('isActive')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Start the tracking activity. Safe to call repeatedly — the native side
  /// updates the running activity instead of stacking a new one.
  Future<void> start({
    required String taskTitle,
    required int totalStages,
    required int stageIndex,
    required String stageLabel,
    required String statusRaw,
    required String jobId,
    String? crewName,
    int unreadCount = 0,
    double? endEpoch,
    bool overtime = false,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<String>('start', {
        'taskTitle': taskTitle,
        'totalStages': totalStages,
        'stageIndex': stageIndex,
        'stageLabel': stageLabel,
        'statusRaw': statusRaw,
        'jobId': jobId,
        'crewName': crewName,
        'unreadCount': unreadCount,
        'endEpoch': endEpoch,
        'overtime': overtime,
      });
    } catch (e) {
      debugPrint('JobLiveActivity.start failed: $e');
    }
  }

  /// Push a new state to the running activity.
  Future<void> update({
    required int stageIndex,
    required String stageLabel,
    required String statusRaw,
    String? crewName,
    int unreadCount = 0,
    double? endEpoch,
    bool overtime = false,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('update', {
        'stageIndex': stageIndex,
        'stageLabel': stageLabel,
        'statusRaw': statusRaw,
        'crewName': crewName,
        'unreadCount': unreadCount,
        'endEpoch': endEpoch,
        'overtime': overtime,
      });
    } catch (e) {
      debugPrint('JobLiveActivity.update failed: $e');
    }
  }

  /// End the activity, showing a final state briefly before it dismisses.
  Future<void> end({
    required int stageIndex,
    required String stageLabel,
    required String statusRaw,
    String? crewName,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('end', {
        'stageIndex': stageIndex,
        'stageLabel': stageLabel,
        'statusRaw': statusRaw,
        'crewName': crewName,
      });
    } catch (e) {
      debugPrint('JobLiveActivity.end failed: $e');
    }
  }
}
