import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/account_gate.dart';
import 'plans_controller.dart';
import 'plans_screen.dart';

/// The one "Redeem a code" flow, shared by Settings and the paywall.
///
/// iOS: codes are App Store offer codes, so this only opens Apple's
/// redemption sheet - whatever it grants comes back through the normal
/// purchase verification and unlocks with a celebration.
///
/// Android: Play promo codes can only grant free time, so discounts are
/// Silen's own codes. The server checks the code and names the Play offer it
/// unlocks, then the paywall sells that offer at the store's discounted price
/// ([openPaywall] is false when the caller already is the paywall). Play's
/// own codes are still one tap away in the dialog.
///
/// A subscription belongs to a Silen account, so guests sign in first.
Future<void> runRedeemCode(BuildContext context,
    {bool openPaywall = true}) async {
  final hasAccount = await AccountGate.ensure(context);
  if (!hasAccount || !context.mounted) return;

  if (Platform.isAndroid) {
    await _redeemOnAndroid(context, openPaywall: openPaywall);
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<PlansController>().redeemCode();
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Code redemption isn\'t available right now.')));
  }
}

Future<void> _redeemOnAndroid(BuildContext context,
    {required bool openPaywall}) async {
  final controller = context.read<PlansController>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  final result = await showDialog<_RedeemResult>(
    context: context,
    builder: (_) => _PromoCodeDialog(controller: controller),
  );

  switch (result) {
    case _RedeemResult.applied:
      messenger.showSnackBar(const SnackBar(
          content: Text('Code applied - your discount is on the plans.')));
      if (openPaywall) {
        navigator.push(MaterialPageRoute(builder: (_) => const PlansScreen()));
      }
    case _RedeemResult.playCode:
      try {
        await controller.redeemCode();
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Redeem your code in Google Play, then come back - SilaFit unlocks automatically.')));
      } catch (_) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Code redemption isn\'t available right now.')));
      }
    case null:
      break;
  }
}

enum _RedeemResult { applied, playCode }

class _PromoCodeDialog extends StatefulWidget {
  final PlansController controller;

  const _PromoCodeDialog({required this.controller});

  @override
  State<_PromoCodeDialog> createState() => _PromoCodeDialogState();
}

class _PromoCodeDialogState extends State<_PromoCodeDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.applyPromoCode(code);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(_RedeemResult.applied);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Redeem a code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            maxLength: 40,
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              hintText: 'Enter your code',
              errorText: _error,
              errorMaxLines: 3,
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).pop(_RedeemResult.playCode),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: const Text('Have a Google Play code?'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _apply,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Apply'),
        ),
      ],
    );
  }
}
