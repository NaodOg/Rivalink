import 'package:flutter/material.dart';

import '../../core/data/media_config.dart';
import '../../core/theme/rivalink_theme.dart';

class PFAvatar extends StatelessWidget {
  final String? name;
  final String? imageUrl;
  final double size;

  const PFAvatar({super.key, this.name, this.imageUrl, this.size = 44});

  String get _initial {
    final n = (name ?? '').trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = MediaConfig.resolve(imageUrl);
    final hasImage = resolved != null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PFColors.surfaceHigh,
        shape: BoxShape.circle,
        border: Border.all(color: PFColors.border),
        image: hasImage
            ? DecorationImage(image: NetworkImage(resolved), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: hasImage
          ? null
          : Text(
              _initial,
              style: TextStyle(
                color: PFColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
              ),
            ),
    );
  }
}
