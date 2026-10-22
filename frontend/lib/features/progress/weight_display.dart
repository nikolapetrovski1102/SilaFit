import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../settings/settings_controller.dart';

/// Same factor as the Active Workout Tracker, so a set logged there reads
/// the same number here.
const _kgToLb = 2.20462;

/// The account's weight unit ('kg' or 'lb'), rebuilding when it changes.
/// Falls back to kg while settings load, or where no [SettingsController]
/// is provided (widget tests).
String weightUnitOf(BuildContext context) =>
    context.watch<SettingsController?>()?.state.data?.weightUnit ?? 'kg';

/// [kg] converted to [unit].
double toDisplayWeight(double kg, String unit) =>
    unit == 'lb' ? kg * _kgToLb : kg;

/// A weight already in display units: whole numbers without a decimal,
/// everything else to one place.
String formatDisplayWeight(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// [kg] converted to [unit] and formatted, without the unit label.
String formatWeight(double kg, String unit) =>
    formatDisplayWeight(toDisplayWeight(kg, unit));

/// Appended to a weight logged per hand on a two-dumbbell exercise, so
/// "30 kg × 8" isn't read as the total load.
const perDumbbellSuffix = ' · per dumbbell';
