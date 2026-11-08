// lib/core/notifications/chat_unread_store.dart
//
// App-wide unread-chat-message counts, keyed by task/job id.
//
// Fed from three places, deduped by message id so none of them double-count:
//   • the chat WebSocket watchers on TrackJobScreen / zancrew_JobDetails
//     (increment while a badge-hosting screen is open but the chat is not),
//   • the FCM `new_message` push router (increment while the app/chat is away),
//   • cleared by ChatScreen when the conversation is opened / read.
//
// Persisted to SharedPreferences so a push received while the app was closed is
// still reflected on the chat badge after the next launch.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatUnreadStore extends ChangeNotifier {
  ChatUnreadStore._();
  static final ChatUnreadStore instance = ChatUnreadStore._();

  static const _prefsKey = 'chat_unread_ids_v1';

  // taskId -> set of unread message ids.
  final Map<String, Set<String>> _unread = {};
  bool _loaded = false;

  /// Loads persisted state once. Safe to call repeatedly.
  Future<void> load() => _ensureLoaded();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) {
          if (v is List) _unread[k] = v.map((e) => e.toString()).toSet();
        });
      }
    } catch (_) {
      // Corrupt/missing — start empty.
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _unread.map((k, v) => MapEntry(k, v.toList()));
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {}
  }

  int countFor(String taskId) => _unread[taskId]?.length ?? 0;

  int get total => _unread.values.fold(0, (a, s) => a + s.length);

  /// Records an unread message (caller has already established it is from the
  /// other party and not currently being viewed). No-op if already recorded.
  Future<void> add(String taskId, String messageId) async {
    if (taskId.isEmpty || messageId.isEmpty) return;
    await _ensureLoaded();
    final set = _unread.putIfAbsent(taskId, () => <String>{});
    if (set.add(messageId)) {
      notifyListeners();
      await _persist();
    }
  }

  /// Clears the unread count for a task (conversation opened / read).
  Future<void> clear(String taskId) async {
    await _ensureLoaded();
    if (_unread.remove(taskId) != null) {
      notifyListeners();
      await _persist();
    }
  }
}
