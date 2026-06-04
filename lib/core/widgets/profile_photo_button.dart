// This file shows the user's profile avatar and lets them capture & upload a new photo.

// lib/core/widgets/profile_photo_button.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/profile_photo_helper.dart';

class ProfilePhotoButton extends StatefulWidget {
  const ProfilePhotoButton({super.key, this.size = 84});
  final double size;

  @override
  State<ProfilePhotoButton> createState() => _ProfilePhotoButtonState();
}

class _ProfilePhotoButtonState extends State<ProfilePhotoButton> {
  String? _remoteUrl;     // URL from backend
  File? _localFile;       // Local preview image
  bool _busy = false;     // Upload spinner state

  // ---------------------------------------------------------------------------
  // 1) LOAD EXISTING SAVED PROFILE PHOTO (SharedPreferences)
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _remoteUrl = prefs.getString('profile_photo_url');
    });
  }

  // ---------------------------------------------------------------------------
  // 2) PICK PHOTO FROM CAMERA → CROP → UPLOAD TO BACKEND
  // ---------------------------------------------------------------------------
  Future<void> _pickAndUpload() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final file = await ProfilePhotoHelper.captureFromCamera(context);
      if (file == null) {
        setState(() => _busy = false);
        return;
      }

      // Show preview instantly
      setState(() => _localFile = file);

      // Upload to server
      final url = await ApiService.uploadProfilePhoto(file);
      if (!mounted) return;

      if (url != null && url.isNotEmpty) {
        setState(() => _remoteUrl = url);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated 👍')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 3) BUILD AVATAR WIDGET + CAMERA BUTTON
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final radius = widget.size / 2;

    Widget avatar;

    if (_localFile != null) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(_localFile!),
      );
    } else if (_remoteUrl != null && _remoteUrl!.isNotEmpty) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(_remoteUrl!),
      );
    } else {
      avatar = CircleAvatar(
        radius: radius,
        child: const Icon(Icons.person, size: 36),
      );
    }

    return Stack(
      children: [
        avatar,
        Positioned(
          bottom: 0,
          right: 0,
          child: InkWell(
            onTap: _busy ? null : _pickAndUpload,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.black.withOpacity(0.75),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}