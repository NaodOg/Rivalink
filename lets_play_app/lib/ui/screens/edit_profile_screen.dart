import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/media_config.dart';
import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class EditProfileScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const EditProfileScreen({super.key, required this.session, required this.repo});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  XFile? _newImage;
  String? _existingImageUrl;
  bool _saving = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final user = widget.session.user ?? {};
    _nameCtrl.text = user['name']?.toString() ?? '';
    _bioCtrl.text = user['bio']?.toString() ?? '';
    _locationCtrl.text = user['location']?.toString() ?? '';
    _existingImageUrl = user['profile_image']?.toString();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1024);
    if (picked != null) setState(() => _newImage = picked);
  }

  Future<void> _save() async {
    final token = widget.session.token;
    if (token == null) return;

    setState(() => _saving = true);

    String? imageUrl = _existingImageUrl;

    if (_newImage != null) {
      final upload = await widget.repo.uploadProfileImage(token: token, imagePath: _newImage!.path);
      if (upload['success'] == true) {
        imageUrl = upload['url'] as String?;
      }
    }

    final result = await widget.repo.updateProfile(
      token: token,
      name: _nameCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      profileImage: imageUrl,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result['success'] == true) {
      final updatedUser = result['user'] as Map<String, dynamic>?;
      if (updatedUser != null) {
        await widget.session.updateUser(updatedUser);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']?.toString() ?? 'Failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedImage = MediaConfig.resolve(_existingImageUrl);
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Edit profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickImage,
            child: Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: PFColors.cardSoft,
                    backgroundImage: _newImage != null
                        ? FileImage(File(_newImage!.path))
                        : (resolvedImage != null ? CachedNetworkImageProvider(resolvedImage) : null),
                    child: (_newImage == null && (_existingImageUrl == null || _existingImageUrl!.isEmpty))
                        ? const Icon(Icons.person_rounded, size: 48, color: PFColors.muted)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: PFColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_rounded, size: 18, color: PFColors.background),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _pickImage,
              child: const Text('Change Photo', style: TextStyle(color: PFColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 16),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: 'Your name'),
                ),
                const SizedBox(height: 16),
                const Text('Bio', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _bioCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: 'Tell us about yourself'),
                ),
                const SizedBox(height: 16),
                const Text('Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: _locationCtrl,
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(hintText: 'Addis Ababa, Ethiopia'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PFButton(label: 'Save changes', loading: _saving, onTap: _save),
        ],
      ),
    );
  }
}
