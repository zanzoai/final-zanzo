//  This file handles ALL chat messaging between customer ↔ crew.

// lib/core/services/messages_api.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:zanzo_frontend/core/services/api_service.dart';

// ---------------------------------------------------------------------------
// CHAT MESSAGE MODEL
// ---------------------------------------------------------------------------

class ChatMessage {
  final String id;
  final String jobId;
  final String senderUserId;
  final String kind; // 'text' | 'image'
  final String content; // message text OR caption
  final String? imageStoragePath; // storage path in bucket
  final String? extension; // 'jpg' | 'png'
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.jobId,
    required this.senderUserId,
    required this.kind,
    required this.content,
    required this.createdAt,
    this.imageStoragePath,
    this.extension,
    this.imageUrl,
  });

  /// Short-lived signed link from the API, for images uploaded through
  /// POST /messages/upload-image. Null for older images stored directly in
  /// Supabase — those use [publicImageUrl].
  final String? imageUrl;

  /// The link to show for this message's image, whichever way it was stored.
  String? displayImageUrl() => imageUrl ?? publicImageUrl();

  bool get isImage =>
      kind.toLowerCase() == 'image' ||
      (imageStoragePath != null && imageStoragePath!.isNotEmpty);

  /// Return public URL if bucket is public.
  String? publicImageUrl({String bucket = 'chat_uploads'}) {
    if (imageStoragePath == null || imageStoragePath!.isEmpty) return null;
    try {
      return Supabase.instance.client.storage
          .from(bucket)
          .getPublicUrl(imageStoragePath!);
    } catch (_) {
      return null;
    }
  }

  factory ChatMessage.fromJson(Map<String, dynamic> m) {
    String? _nullIfEmpty(String? s) =>
        (s == null || s.trim().isEmpty) ? null : s.trim();

    return ChatMessage(
      id: (m['id'] ?? '').toString(),
      jobId: (m['job_id'] ?? '').toString(),
      senderUserId: (m['sender_user_id'] ?? '').toString(),
      kind: (m['kind'] ?? 'text').toString(),
      content: (m['content'] ?? '').toString(),
      imageStoragePath: _nullIfEmpty(m['image_storage_path']?.toString()),
      extension: _nullIfEmpty(m['extension']?.toString()),
      imageUrl: _nullIfEmpty(m['image_url']?.toString()),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

// ---------------------------------------------------------------------------
// MESSAGES API
// ---------------------------------------------------------------------------

class MessagesApi {

  // ---------------------------
  // 1) LIST MESSAGES FOR A JOB
  // ---------------------------

  static Future<List<ChatMessage>> listByJob(String jobId) async {
    final uri = Uri.parse('${ApiService.baseUrl}/messages/by-task/$jobId');

    final res = await http.get(uri, headers: await ApiService.authHeaders());
    if (res.statusCode != 200) {
      throw Exception(
        'GET /messages/by-task failed: ${res.statusCode} ${res.body}',
      );
    }

    final raw = jsonDecode(res.body);
    if (raw is! List) return <ChatMessage>[];

    final list = raw
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Oldest → newest
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  // ---------------------------
  // 2) SEND TEXT MESSAGE
  // ---------------------------

  static Future<ChatMessage> sendText({
    required String jobId,
    required String senderUserId,
    required String content,
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/messages/send');

    final res = await http.post(
      uri,
      headers: await ApiService.authHeaders(),
      body: jsonEncode({
        'task_id': jobId,
        'sender_user_id': senderUserId,
        'content': content,
        'kind': 'text',
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'POST /messages/send failed: ${res.statusCode} ${res.body}',
      );
    }

    return ChatMessage.fromJson(
      Map<String, dynamic>.from(jsonDecode(res.body)),
    );
  }

  // ---------------------------
  // 3) UPLOAD IMAGE BYTES THROUGH THE API
  // ---------------------------
  // POST /messages/upload-image (multipart: task_id + file). The server checks
  // the caller is part of the task and checks the file really is an image,
  // then stores it under that task. Returns the storage path to send with the
  // message. (Images used to go straight to a Supabase bucket with the public
  // key, with no check on who uploaded what.)

  static Future<String> uploadImageBytes({
    required String jobId,
    required Uint8List bytes,
    required String fileExt,   // jpg | png | webp
    required String mimeType,  // image/jpeg | image/png | image/webp
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/messages/upload-image');

    final res = await ApiService.callWithRefresh((headers) async {
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          if (headers['Authorization'] != null)
            'Authorization': headers['Authorization']!,
        })
        ..fields['task_id'] = jobId
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: '${const Uuid().v4()}.$fileExt',
          contentType: MediaType.parse(mimeType),
        ));
      return http.Response.fromStream(await req.send());
    });

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        res.statusCode == 413
            ? 'That image is too large.'
            : 'Could not upload the image (${res.statusCode}).',
      );
    }
    final path = (jsonDecode(res.body) as Map<String, dynamic>)['storage_path']?.toString();
    if (path == null || path.isEmpty) throw Exception('Could not upload the image.');
    return path;
  }

  // ---------------------------
  // 4) SEND IMAGE MESSAGE
  // ---------------------------

  static Future<ChatMessage> sendImage({
    required String jobId,
    required String senderUserId,
    required String storagePath,
    required String extension,
    String? caption,
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/messages/send');

    final res = await http.post(
      uri,
      headers: await ApiService.authHeaders(),
      body: jsonEncode({
        'task_id': jobId,
        'sender_user_id': senderUserId,
        'kind': 'image',
        'content': caption ?? '',
        'image_storage_path': storagePath,
        'extension': extension,
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'POST /messages/send (image) failed: ${res.statusCode} ${res.body}',
      );
    }

    return ChatMessage.fromJson(
      Map<String, dynamic>.from(jsonDecode(res.body)),
    );
  }

  // ---------------------------
  // 5) UPLOAD BYTES + SEND IMAGE (CONVENIENCE)
  // ---------------------------

  static Future<ChatMessage> uploadAndSendImage({
    required String jobId,
    required String senderUserId,
    required Uint8List bytes,
    required String fileExt,
    String? caption,
  }) async {
    final mime = _mimeForExt(fileExt);

    final path = await uploadImageBytes(
      jobId: jobId,
      bytes: bytes,
      fileExt: fileExt,
      mimeType: mime,
    );

    return sendImage(
      jobId: jobId,
      senderUserId: senderUserId,
      storagePath: path,
      extension: fileExt,
      caption: caption,
    );
  }

  // ---------------------------
  // 6) MIME TYPE HELPER
  // ---------------------------

  static String _mimeForExt(String ext) {
    final e = ext.toLowerCase();
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'png') return 'image/png';
    if (e == 'webp') return 'image/webp';
    return 'application/octet-stream';
  }
}