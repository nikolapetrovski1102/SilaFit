import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'supplement_provider_models.dart';
import '../../l10n/l10n.dart';

/// Copies the partner's code and confirms with a snackbar.
Future<void> copyProviderCode(
    BuildContext context, SupplementProvider provider) async {
  final code = provider.promoCode;
  if (code == null) return;
  await Clipboard.setData(ClipboardData(text: code));
  HapticFeedback.selectionClick();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(tr('Code {code} copied. Paste it at checkout.', {'code': code}))));
}

/// Opens the partner's shop in the browser, copying the code first so it is
/// ready at checkout.
Future<void> openProviderShop(
    BuildContext context, SupplementProvider provider) async {
  final url = provider.shopUrl;
  if (url == null) return;
  if (provider.promoCode != null) {
    await Clipboard.setData(ClipboardData(text: provider.promoCode!));
  }
  final ok =
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr("Couldn't open the shop."))));
  }
}
