import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/account_gate.dart';
import 'plans_controller.dart';
import '../../l10n/l10n.dart';

/// The one Restore Purchases flow, shared by Settings and the paywall so both
/// entry points gate, wait and report identically. Subscriptions are tied to a
/// Silen account server-side, so a guest is asked to sign in first instead of
/// the verify call failing silently behind them.
Future<void> runRestorePurchases(BuildContext context) async {
  final hasAccount = await AccountGate.ensure(context);
  if (!hasAccount || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final plans = context.read<PlansController>();
  messenger.hideCurrentSnackBar();
  messenger
      .showSnackBar(SnackBar(content: Text(tr('Restoring purchases...'))));

  final outcome = await plans.restorePurchases();
  if (outcome == null || !context.mounted) return;

  final message = switch (outcome) {
    RestoreOutcome.restored => tr('Your subscription has been restored.'),
    RestoreOutcome.nothingFound =>
      tr('No active subscription found for this Apple ID or Google account.'),
    RestoreOutcome.failed => plans.actionError!,
  };
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
