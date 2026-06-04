//This file manages taking or picking a profile photo and cropping it before uploading.

// lib/core/services/profile_photo_helper.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePhotoHelper {
  static final ImagePicker _picker = ImagePicker();

  // ---------------------------------------------------------------------------
  // CAPTURE PHOTO (CAMERA)
  // ---------------------------------------------------------------------------

  static Future<File?> captureFromCamera(BuildContext context) async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));

      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (shot == null) return null;

      final file = File(shot.path);
      final cropped = await _crop(file);
      return cropped ?? file;
    } catch (e) {
      debugPrint('❌ captureFromCamera failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // PICK FROM GALLERY
  // ---------------------------------------------------------------------------

  static Future<File?> pickFromGallery(BuildContext context) async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));

      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (picked == null) return null;

      final file = File(picked.path);
      final cropped = await _crop(file);
      return cropped ?? file;
    } catch (e) {
      debugPrint('❌ pickFromGallery failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // CROP IMAGE
  // ---------------------------------------------------------------------------

  static Future<File?> _crop(File file) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Photo',
            toolbarColor: Colors.deepPurple,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Crop Photo'),
        ],
      );

      if (cropped == null) return null;
      return File(cropped.path);
    } catch (e) {
      debugPrint('❌ crop failed: $e');
      return null;
    }
  }
}