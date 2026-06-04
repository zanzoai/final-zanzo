// This file provides the job-based chat screen, handling message loading, polling, sending text/images,
// aligning bubbles by sender, and keeping scroll at the bottom.

// lib/features/common/chat/chat_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/messages_api.dart';

class ChatScreen extends StatefulWidget {
  final String jobId;
  final String? jobTitle;
  final String? viewerUserId; // fallback → SharedPreferences('user_id')

  const ChatScreen({
    super.key,
    required this.jobId,
    this.jobTitle,
    this.viewerUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();

  List<ChatMessage> _messages = [];
  String? _viewerUserId;
  bool _loading = true;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // ---------------------------------------------------------------------------
  // 1) INITIAL BOOTSTRAP → Determine viewer, load first messages, start polling
  // ---------------------------------------------------------------------------
  Future<void> _bootstrap() async {
    _viewerUserId = widget.viewerUserId;

    if (_viewerUserId == null) {
      final prefs = await SharedPreferences.getInstance();
      _viewerUserId = prefs.getString('user_id');
    }

    await _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  // ---------------------------------------------------------------------------
  // 2) LOAD MESSAGES (polling every 2 seconds)
  // ---------------------------------------------------------------------------
  Future<void> _refresh() async {
    try {
      final list = await MessagesApi.listByJob(widget.jobId);
      if (!mounted) return;

      setState(() {
        _messages = list;
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 3) SEND TEXT MESSAGE
  // ---------------------------------------------------------------------------
  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _viewerUserId == null) return;

    _input.clear();

    try {
      setState(() => _sending = true);

      await MessagesApi.sendText(
        jobId: widget.jobId,
        senderUserId: _viewerUserId!,
        content: text,
      );

      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to send')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 4) PICK IMAGE FROM CAMERA/GALLERY
  // ---------------------------------------------------------------------------
  Future<void> _pickImage(ImageSource source) async {
    if (_viewerUserId == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (picked == null) return;

    await _sendPickedImage(picked);
  }

  // ---------------------------------------------------------------------------
  // 5) SEND IMAGE MESSAGE (with caption if present)
  // ---------------------------------------------------------------------------
  Future<void> _sendPickedImage(XFile picked) async {
    if (_viewerUserId == null) return;

    try {
      setState(() => _sending = true);

      final bytes = await picked.readAsBytes();
      const maxBytes = 4 * 1024 * 1024;

      if (bytes.length > maxBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image too large (max ~4MB)')),
        );
        return;
      }

      // determine extension
      String ext = 'jpg';
      final name = picked.name.toLowerCase();
      if (name.endsWith('.png')) ext = 'png';
      else if (name.endsWith('.jpeg') || name.endsWith('.jpg')) ext = 'jpg';
      else if (name.endsWith('.webp')) ext = 'webp';

      // optional caption
      final caption =
          _input.text.trim().isEmpty ? null : _input.text.trim();
      if (caption != null) _input.clear();

      await MessagesApi.uploadAndSendImage(
        jobId: widget.jobId,
        senderUserId: _viewerUserId!,
        bytes: bytes,
        fileExt: ext,
        caption: caption,
      );

      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image send failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 6) UI BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final title = widget.jobTitle ?? 'Chat';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildMessages(),
          ),
          _buildInput(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 7) MESSAGES LIST
  // ---------------------------------------------------------------------------
  Widget _buildMessages() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final isMine =
            _viewerUserId != null && m.senderUserId == _viewerUserId;

        final bubbleColor = isMine
            ? Colors.orange.shade100
            : Colors.grey.shade200;

        return Align(
          alignment:
              isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft:
                      isMine ? const Radius.circular(14) : const Radius.circular(4),
                  bottomRight:
                      isMine ? const Radius.circular(4) : const Radius.circular(14),
                ),
              ),
              child: m.isImage ? _buildImageBubble(m) : Text(m.content),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 8) IMAGE BUBBLE + optional caption
  // ---------------------------------------------------------------------------
  Widget _buildImageBubble(ChatMessage m) {
    final url = m.publicImageUrl();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url != null)
          GestureDetector(
            onTap: () => _openImagePreview(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(url, width: 240, fit: BoxFit.cover),
            ),
          )
        else
          Container(
            width: 240,
            height: 160,
            color: Colors.black12,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined),
          ),
        if (m.content.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(m.content),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 9) FULLSCREEN IMAGE PREVIEW
  // ---------------------------------------------------------------------------
  void _openImagePreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 10) INPUT BAR (text + send + camera)
  // ---------------------------------------------------------------------------
  Widget _buildInput() {
    final disabled = _viewerUserId == null;

    return SafeArea(
      top: false,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: disabled
                ? null
                : () {
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.photo_camera),
                              title: const Text('Take Photo'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _pickImage(ImageSource.camera);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_library),
                              title: const Text('Choose from Gallery'),
                              onTap: () {
                                Navigator.pop(ctx);
                                _pickImage(ImageSource.gallery);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
          ),
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !disabled && !_sending,
              decoration: InputDecoration(
                hintText: disabled
                    ? 'Sign in to send messages'
                    : _sending ? 'Sending…' : 'Type a message…',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: (disabled || _sending) ? null : _sendText,
          ),
        ],
      ),
    );
  }
}