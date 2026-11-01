import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'supplement_provider_models.dart';

/// Round partner logo, falling back to the name's initial.
class ProviderLogo extends StatelessWidget {
  final SupplementProvider provider;
  final double size;

  const ProviderLogo({super.key, required this.provider, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh, shape: BoxShape.circle),
      child: Text(
        provider.name.isEmpty ? '?' : provider.name[0].toUpperCase(),
        style: AppTypography.labelCaps.copyWith(color: AppColors.accent),
      ),
    );
    final url = provider.logoUrl;
    if (url == null) return fallback;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, __) => fallback,
          errorWidget: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}
