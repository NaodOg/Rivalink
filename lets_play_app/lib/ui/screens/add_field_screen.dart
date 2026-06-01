import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/playfair_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';
import '../widgets/pf_scaffold.dart';

class AddFieldScreen extends StatefulWidget {
  final SessionController session;
  final AppRepository repo;
  const AddFieldScreen({super.key, required this.session, required this.repo});

  @override
  State<AddFieldScreen> createState() => _AddFieldScreenState();
}

class _AddFieldScreenState extends State<AddFieldScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: 'Addis Ababa');
  final _locationCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _openingCtrl = TextEditingController(text: '06:00');
  final _closingCtrl = TextEditingController(text: '22:00');

  final _sportsCtrl = TextEditingController();
  final _amenitiesCtrl = TextEditingController();

  XFile? _image;
  bool _isSubmitting = false;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _locationCtrl.dispose();
    _priceCtrl.dispose();
    _capacityCtrl.dispose();
    _openingCtrl.dispose();
    _closingCtrl.dispose();
    _sportsCtrl.dispose();
    _amenitiesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _image = picked);
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Field name is required')));
      return;
    }

    setState(() => _isSubmitting = true);
    final token = widget.session.token;
    if (token == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    final result = await widget.repo.createField(
      token: token,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      sports: _sportsCtrl.text.trim(),
      pricePerHour: double.tryParse(_priceCtrl.text) ?? 0,
      capacity: int.tryParse(_capacityCtrl.text) ?? 0,
      amenities: _amenitiesCtrl.text.trim(),
      openingTime: _openingCtrl.text.trim(),
      closingTime: _closingCtrl.text.trim(),
      image: _image,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Field added successfully!')));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['error']?.toString() ?? 'Failed to add field')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PFScaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('Add Field'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: PFCard(
              padding: const EdgeInsets.all(0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(color: PFColors.cardSoft),
                  child: _image == null
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate_rounded, size: 40, color: PFColors.muted),
                              SizedBox(height: 8),
                              Text('Tap to add photo', style: TextStyle(color: PFColors.muted)),
                            ],
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(_image!.path), fit: BoxFit.cover),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.black54,
                                child: IconButton(
                                  iconSize: 16,
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: () => setState(() => _image = null),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Basic Info', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 14),
                _buildField(label: 'Field Name', controller: _nameCtrl, hint: 'Bole Stadium'),
                const SizedBox(height: 12),
                _buildField(label: 'Description', controller: _descCtrl, hint: 'Describe the field...', maxLines: 3),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Location', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 14),
                _buildField(label: 'Address', controller: _addressCtrl, hint: 'Bole Road'),
                const SizedBox(height: 12),
                _buildField(label: 'City', controller: _cityCtrl, hint: 'Addis Ababa'),
                const SizedBox(height: 12),
                _buildField(label: 'Area', controller: _locationCtrl, hint: 'Bole, CMC, Sarbet...'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pricing & Capacity', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(label: 'Price (Br/hr)', controller: _priceCtrl, hint: '1500', keyboardType: TextInputType.number),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(label: 'Capacity', controller: _capacityCtrl, hint: '50', keyboardType: TextInputType.number),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildField(label: 'Opening', controller: _openingCtrl, hint: '06:00'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(label: 'Closing', controller: _closingCtrl, hint: '22:00'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sports & Amenities', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 14),
                _buildField(label: 'Sports (comma-separated)', controller: _sportsCtrl, hint: 'Soccer, Basketball, Tennis'),
                const SizedBox(height: 12),
                _buildField(label: 'Amenities (comma-separated)', controller: _amenitiesCtrl, hint: 'Parking, Locker Rooms, Floodlights'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PFButton(label: _isSubmitting ? 'Adding Field...' : 'Add Field', onTap: _isSubmitting ? () {} : _submit),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String hint = '',
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PFColors.muted)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: PFColors.muted.withValues(alpha: 0.5)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
        ),
      ],
    );
  }
}
