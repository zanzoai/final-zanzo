// lib/core/notifications/push_router.dart
//
// App-wide FCM handler for the `data.type`-routed pushes documented in
// ZANZO_FLUTTER_API_REFERENCE.md §4 ("Routing pushes"). Today it implements the
// `new_message` (in-task chat) route:
//
//   • Notification TAP (background / terminated) → open that task's ChatScreen.
//   • Foreground push → the chat WebSocket already delivers the message when the
//     chat is open (see task_chat_ws_service.dart), so we suppress a duplicate
//     if the user is already viewing that task's chat; otherwise we surface a
//     tappable in-app SnackBar that opens the chat. De-dupe is by `task_id`.
//
// `new_offer` foreground/open handling still lives in zancrew_dashboard.dart;
// this router intentionally ignores it to avoid double-processing.
//
// Reuses DeepLinkService.navigatorKey (attached to MaterialApp) so we can
// navigate from outside the widget tree.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zanzo_frontend/core/live_activity/deep_link_service.dart';
import 'package:zanzo_frontend/core/notifications/chat_unread_store.dart';
import 'package:zanzo_frontend/features/common/chat/chat_screen.dart';

/// Registered in main() via [FirebaseMessaging.onBackgroundMessage].
/// Must be a top-level (or static) function. When a push carries a
/// `notification` block the OS renders the banner itself while the app is
/// backgrounded/terminated, so there is nothing to do here — the tap is handled
/// by [FirebaseMessaging.onMessageOpenedApp] / getInitialMessage. Kept for
/// completeness and future data-only handling.
@pragma('vm:entry-point')
Future<void> firebasePushBackgroundHandler(RemoteMessage message) async {
  // Runs in a background isolate — do NOT touch UI. We only persist state that
  // the UI reads on next launch.
  //
  // Admin force-offline (`crew_status_changed`) is a silent/data-only push, so
  // it must be applied here too: write the online flag so a backgrounded /
  // terminated crew app comes up OFFLINE. The dashboard reads `zancrew_online`
  // in _loadState. See ZANZO_FLUTTER_API_REFERENCE.md §4.
  if (message.data['type'] == 'crew_status_changed') {
    final isOnline = message.data['is_online'] == 'true';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('zancrew_online', isOnline);
    } catch (_) {}
  }
}

class PushRouter {
  PushRouter._();
  static final PushRouter instance = PushRouter._();

  /// Set by [ChatScreen] while it is on screen so foreground pushes for the
  /// same task don't produce a redundant in-app banner (the WS already shows
  /// the message live). Null when no chat is open.
  static String? currentChatTaskId;

  bool _initialised = false;

  /// Call once at startup, after Firebase.initializeApp(). Safe to call again.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    try {
      await FirebaseMessaging.instance.requestPermission();

      // We render our own in-app banner for foreground `new_message` pushes, so
      // suppress the OS auto-banner on iOS to avoid a double notification.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    } catch (e) {
      debugPrint('[PushRouter] permission/options setup failed: $e');
    }

    // Foreground pushes.
    FirebaseMessaging.onMessage.listen(
      (m) => _handle(m, opened: false),
      onError: (e) => debugPrint('[PushRouter] onMessage error: $e'),
    );

    // Tapped while the app was backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _handle(m, opened: true),
      onError: (e) => debugPrint('[PushRouter] onMessageOpenedApp error: $e'),
    );

    // Tapped from a fully terminated state (cold start).
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handle(initial, opened: true);
    } catch (e) {
      debugPrint('[PushRouter] getInitialMessage error: $e');
    }
  }

  // ---------------------------------------------------------------------------

  void _handle(RemoteMessage message, {required bool opened}) {
    final data = message.data;
    final type = (data['type'] ?? '').toString();

    switch (type) {
      case 'new_message':
        _handleNewMessage(data, opened: opened);
        break;
      case 'crew_status_changed':
        // Admin force-offline. Persist the flag app-wide so it's respected even
        // if the crew isn't on the dashboard (which applies it live when it is).
        _persistCrewOnline(data['is_online'] == 'true');
        break;
      // `new_offer` and `task_status_update` are handled elsewhere / TBD.
      default:
        break;
    }
  }

  Future<void> _persistCrewOnline(bool isOnline) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('zancrew_online', isOnline);
    } catch (_) {}
  }

  void _handleNewMessage(Map<String, dynamic> data, {required bool opened}) {
    final taskId = (data['task_id'] ?? '').toString().trim();
    if (taskId.isEmpty) return;

    final preview = (data['preview'] ?? '').toString().trim();
    final messageId = (data['message_id'] ?? '').toString().trim();

    if (opened) {
      // Notification tap → jump straight to the chat (which clears its unread).
      _openChat(taskId);
      return;
    }

    // Foreground: if the user is already looking at this task's chat, the WS
    // has it covered — do nothing.
    if (currentChatTaskId == taskId) return;

    // Bump the unread badge (deduped by message id against the WS watcher) and
    // surface a tappable in-app banner.
    if (messageId.isNotEmpty) {
      ChatUnreadStore.instance.add(taskId, messageId);
    }
    _showInAppBanner(taskId: taskId, preview: preview);
  }

  void _showInAppBanner({required String taskId, required String preview}) {
    final ctx = DeepLinkService.navigatorKey.currentContext;
    if (ctx == null) return;

    final messenger = ScaffoldMessenger.maybeOf(ctx);
    if (messenger == null) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            preview.isEmpty ? 'New message' : preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'View',
            onPressed: () => _openChat(taskId),
          ),
        ),
      );
  }

  void _openChat(String taskId) {
    // Already viewing this chat — nothing to do.
    if (currentChatTaskId == taskId) return;

    final nav = DeepLinkService.navigatorKey.currentState;
    if (nav == null) return;

    nav.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(jobId: taskId),
      ),
    );
  }
}
