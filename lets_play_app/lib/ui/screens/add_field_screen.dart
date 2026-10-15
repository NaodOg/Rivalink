import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/repositories/app_repository.dart';
import '../../core/state/session_controller.dart';
import '../../core/theme/rivalink_theme.dart';
import '../widgets/pf_button.dart';
import '../widgets/pf_card.dart';

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
    for (final c in [
      _nameCtrl, _descCtrl, _addressCtrl, _cityCtrl, _locationCtrl,
      _priceCtrl, _capacityCtrl, _openingCtrl, _closingCtrl, _sportsCtrl, _amenitiesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _image = picked);
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Field name is required')));
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
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error']?.toString() ?? 'Failed to add venue')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PFColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Add a venue'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _photo(),
          const SizedBox(height: PFSpacing.xl),
          _label('Basic info'),
          const SizedBox(height: PFSpacing.sm),
          PFCard(
            child: Column(
              children: [
                _field('Field name', _nameCtrl, 'Bole Stadium'),
                const SizedBox(height: PFSpacing.md),
                _field('Description', _descCtrl, 'Describe the venue…', maxLines: 3),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.lg),
          _label('Location'),
          const SizedBox(height: PFSpacing.sm),
          PFCard(
            child: Column(
              children: [
                _field('Address', _addressCtrl, 'Bole Road'),
                const SizedBox(height: PFSpacing.md),
                Row(
                  children: [
                    Expanded(child: _field('City', _cityCtrl, 'Addis Ababa')),
                    const SizedBox(width: PFSpacing.md),
                    Expanded(child: _field('Area', _locationCtrl, 'Bole, CMC…')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.lg),
          _label('Pricing & hours'),
          const SizedBox(height: PFSpacing.sm),
          PFCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _field('Price (Br/hr)', _priceCtrl, '1500',
                            keyboard: TextInputType.number)),
                    const SizedBox(width: PFSpacing.md),
                    Expanded(
                        child: _field('Capacity', _capacityCtrl, '50',
                            keyboard: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: PFSpacing.md),
                Row(
                  children: [
                    Expanded(child: _field('Opens', _openingCtrl, '06:00')),
                    const SizedBox(width: PFSpacing.md),
                    Expanded(child: _field('Closes', _closingCtrl, '22:00')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: PFSpacing.lg),
          _label('Sports & amenities'),
          const SizedBox(height: PFSpacing.sm),
          PFCard(
            child: Column(
              children: [
                _field('Sports (comma-separated)', _sportsCtrl, 'Soccer, Basketball'),
                const SizedBox(height: PFSpacing.md),
                _field('Amenities (comma-separated)', _amenitiesCtrl,
                    'Parking, Floodlights, Locker rooms'),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: PFColors.surface,
          border: Border(top: BorderSide(color: PFColors.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: PFButton(label: 'Add venue', loading: _isSubmitting, onTap: _submit),
          ),
        ),
      ),
    );
  }

  Widget _photo() {
    return GestureDetector(
      onTap: _pickImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PFRadius.xl),
        child: Container(
          height: 190,
          width: double.infinity,
          color: PFColors.surfaceRaised,
          child: _image == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_rounded,
                        size: 36, color: PFColors.textTertiary),
                    const SizedBox(height: PFSpacing.sm),
                    Text('Add a photo',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(_image!.path), fit: BoxFit.cover),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => setState(() => _image = null),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: PFColors.scrim,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: PFColors.text),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _label(String t) =>
      Text(t.toUpperCase(), style: Theme.of(context).textTheme.labelSmall);

  Widget _field(String label, TextEditingController c, String hint,
      {int maxLines = 1, TextInputType keyboard = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
