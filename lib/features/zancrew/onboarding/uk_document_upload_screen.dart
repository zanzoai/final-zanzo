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
        preferredCameraDevice:
            useFrontCamera ? CameraDevice.front : CameraDevice.rear,
        imageQuality: 85,
        maxWidth: 1800,
        maxHeight: 1800,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open camera/gallery: $e')),
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
          _passportError = e.toString().replaceFirst('Exception: ', '');
        } else {
          _selfieStatus = _DocStatus.failed;
          _selfieError = e.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  void _showSourcePicker(String docType, bool useFrontCamera) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take photo'),
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
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
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
    );
  }

  Widget _docSection({
    required String docType,
    required String label,
    required String hint,
    required File? file,
    required _DocStatus status,
    required String? error,
    required bool useFrontCamera,
    required IconData icon,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (status == _DocStatus.done)
                  const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            const SizedBox(height: 4),
            Text(hint,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            if (file != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  file,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Icon(Icons.image_outlined,
                    size: 48, color: Colors.grey.shade400),
              ),
            const SizedBox(height: 12),
            if (status == _DocStatus.uploading)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Uploading…',
                      style: TextStyle(color: Colors.orange)),
                ],
              )
            else if (status == _DocStatus.done)
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('Uploaded',
                        style: TextStyle(color: Colors.green)),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _showSourcePicker(docType, useFrontCamera),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Change'),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.grey),
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
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _showSourcePicker(docType, useFrontCamera),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                      file == null ? 'Add Photo' : 'Retake / Change'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange),
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
      appBar: AppBar(
        title: const Text('Upload Documents'),
        backgroundColor: Colors.orangeAccent,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orangeAccent),
              ),
              child: const Text(
                'We need two photos to confirm your identity before your '
                'application can be reviewed. These are used for manual '
                'verification only and are stored securely — they are '
                'never shared outside Zanzo.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            _docSection(
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
            _docSection(
              docType: 'selfie',
              label: 'Selfie',
              hint:
                  'Take a clear selfie of your face in good lighting, matching your ID photo.',
              file: _selfieFile,
              status: _selfieStatus,
              error: _selfieError,
              useFrontCamera: true,
              icon: Icons.face,
            ),
            const SizedBox(height: 4),
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
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _bothDone
                    ? () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const UkPendingScreen()),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: const Text(
                  'Continue',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
