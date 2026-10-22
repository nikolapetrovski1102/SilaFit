import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_config.dart';
import '../../../core/session/session_store.dart';

const _kFallback = 'assets/branding/split_hero.png';

// Mirrors SplitHeroImages.Prefix on the backend: user-built splits are
// auto-assigned a variant-neutral key ('asset:splits/push_pull_legs') whose
// dark and light artwork the API serves under /api/static.
const _kKeyPrefix = 'asset:splits/';

/// Resolves a split's stored hero value to the URL to load for the profile's
/// [gender]: an auto-assigned key becomes the API-hosted variant - the light
/// (female) artwork for a 'Female' profile, the dark (male) artwork for
/// everyone else, matching the avatar picker's male-by-default rule - and
/// anything else is already a URL. Null when there's nothing on record.
String? resolveSplitHeroUrl(String? heroImageUrl, String? gender) {
  if (heroImageUrl == null || heroImageUrl.isEmpty) return null;
  if (!heroImageUrl.startsWith(_kKeyPrefix)) return heroImageUrl;
  final key = heroImageUrl.substring(_kKeyPrefix.length);
  final variant = gender == 'Female' ? 'light' : 'dark';
  return '${ApiConfig.baseUrl}/static/splits/$variant/$key.jpg';
}

/// A split's hero artwork, memory- and disk-cached so it only ever downloads
/// once per device (and keeps showing offline). While loading it fades in
/// over a neutral surface; with nothing on record, or on a failed load, it
/// shows the stock training photo.
class SplitHeroImage extends StatelessWidget {
  final String? heroImageUrl;
  final BoxFit fit;

  const SplitHeroImage(this.heroImageUrl, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: context.read<SessionStore>().profileGender,
      builder: (context, gender, _) {
        final url = resolveSplitHeroUrl(heroImageUrl, gender);
        if (url == null) return Image.asset(_kFallback, fit: fit);

        return CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 180),
          placeholder: (context, _) => ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest),
          errorWidget: (_, __, ___) => Image.asset(_kFallback, fit: fit),
        );
      },
    );
  }
}

/// Warms the cache for [heroImageUrls] so cards render without a placeholder
/// flash - call once a split list has loaded.
void precacheSplitHeroImages(
    BuildContext context, Iterable<String?> heroImageUrls) {
  final gender = context.read<SessionStore>().profileGender.value;
  for (final value in heroImageUrls.toSet()) {
    final url = resolveSplitHeroUrl(value, gender);
    if (url == null) continue;
    precacheImage(CachedNetworkImageProvider(url), context).ignore();
  }
}
