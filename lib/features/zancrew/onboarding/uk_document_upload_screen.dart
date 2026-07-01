// lib/features/zancrew/onboarding/uk_document_upload_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/uk_provider_api.dart';
import 'uk_pending_screen.dart';

enum _DocStatus { idle, uploading, done, failed }

class UkDocumentUploadScreen extends StatefulWidget {
  const UkDocumentUploadScreen({super.key});

  @override
  State<UkDocumentUploadScreen> createState() => _UkDocumentUploadScreenState();
}

class _UkDocumentUploadScreenState extends State<UkDocumentUploadScreen> {
  static const _bg = Color(0xFFFCFAF6);
  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF9B8B7E);
  static const _accent = Color(0xFFD97706);
  static const _border = Color(0xFFE8E2D9);
  static const _success = Color(0xFF16A34A);

  final _picker = ImagePicker();

  File? _passportFile;
  _DocStatus _passportStatus = _DocStatus.idle;
  String? _passportError;

  File? _selfieFile;
  _DocStatus _selfieStatus = _DocStatus.idle;
  String? _selfieError;

  bool get _bothDone =>
      _passportStatus == _DocStatus.done && _selfieStatus == _DocStatus.done;

  Future<void> _pickAndUpload({
    required String docType,
    required ImageSource source,
    required bool useFrontCamera,
  }) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        preferredCameraDevice: useFrontCamera
            ? CameraDevice.front
            : CameraDevice.rear,
        imageQuality: 85,
        maxWidth: 1800,
        maxHeight: 1800,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open camera or gallery. Please try again.'),
        ),
      );
      return;
    }

    if (picked == null) return;
    final file = File(picked.path);

    setState(() {
      if (docType == 'passport_photo') {
        _passportFile = file;
        _passportStatus = _DocStatus.uploading;
        _passportError = null;
      } else {
        _selfieFile = file;
        _selfieStatus = _DocStatus.uploading;
        _selfieError = null;
      }
    });

    try {
      await UkProviderApi.uploadDocument(documentType: docType, file: file);
      if (!mounted) return;
      setState(() {
        if (docType == 'passport_photo') {
          _passportStatus = _DocStatus.done;
        } else {
          _selfieStatus = _DocStatus.done;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (docType == 'passport_photo') {
          _passportStatus = _DocStatus.failed;
          _passportError = 'Upload failed. Please try again.';
        } else {
          _selfieStatus = _DocStatus.failed;
          _selfieError = 'Upload failed. Please try again.';
        }
      });
    }
  }

  void _showSourcePicker(String docType, bool useFrontCamera) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: _ink),
                title: const Text(
                  'Take photo',
                  style: TextStyle(fontWeight: FontWeight.w600, color: _ink),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(
                    docType: docType,
                    source: ImageSource.camera,
                    useFrontCamera: useFrontCamera,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: _ink),
                title: const Text(
                  'Choose from gallery',
                  style: TextStyle(fontWeight: FontWeight.w600, color: _ink),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUpload(
                    docType: docType,
                    source: ImageSource.gallery,
                    useFrontCamera: useFrontCamera,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _docCard({
    required String docType,
    required String label,
    required String hint,
    required File? file,
    required _DocStatus status,
    required String? error,
    required bool useFrontCamera,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == _DocStatus.done ? const Color(0xFFBBF7D0) : _border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: status == _DocStatus.done
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    status == _DocStatus.done ? Icons.check : icon,
                    size: 20,
                    color: status == _DocStatus.done ? _success : _accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              style: const TextStyle(fontSize: 13, color: _muted, height: 1.3),
            ),
            const SizedBox(height: 12),
            if (file != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  file,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F2EE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Icon(
                  Icons.image_outlined,
                  size: 40,
                  color: Colors.grey.shade400,
                ),
              ),
            const SizedBox(height: 12),
            if (status == _DocStatus.uploading)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Uploading…',
                    style: TextStyle(color: _accent, fontSize: 13),
                  ),
                ],
              )
            else if (status == _DocStatus.done)
              Row(
                children: [
                  const Icon(Icons.check_circle, color: _success, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Uploaded',
                      style: TextStyle(
                        color: _success,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showSourcePicker(docType, useFrontCamera),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Change'),
                    style: TextButton.styleFrom(
                      foregroundColor: _muted,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              if (status == _DocStatus.failed && error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => _showSourcePicker(docType, useFrontCamera),
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(file == null ? 'Add Photo' : 'Retake / Change'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: const BorderSide(color: _accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Upload Documents',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 18, color: _accent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'We need two photos to verify your identity before your application can be reviewed. These are stored securely and only used for manual verification — they are never shared outside Zanzo.',
                      style: TextStyle(fontSize: 13, color: _ink, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _docCard(
              docType: 'passport_photo',
              label: 'Passport or ID Photo',
              hint:
                  'Take a clear photo of your passport photo page or other government-issued ID.',
              file: _passportFile,
              status: _passportStatus,
              error: _passportError,
              useFrontCamera: false,
              icon: Icons.badge_outlined,
            ),
            _docCard(
              docType: 'selfie',
              label: 'Selfie',
              hint:
                  'Take a clear selfie of your face in good lighting, matching your ID photo.',
              file: _selfieFile,
              status: _selfieStatus,
              error: _selfieError,
              useFrontCamera: true,
              icon: Icons.face_outlined,
            ),

            if (!_bothDone)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _passportStatus == _DocStatus.idle &&
                          _selfieStatus == _DocStatus.idle
                      ? 'Upload both photos to continue.'
                      : _passportStatus != _DocStatus.done
                      ? 'Passport / ID photo still needed.'
                      : 'Selfie still needed.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _bothDone
                    ? () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UkPendingScreen(),
                        ),
                      )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor: _border,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
