import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/features/diet_plans/diet_plan_models.dart';
import 'package:silafit/features/providers/protein_partner_hint.dart';

// Mirrors backend Silen.Tests/Helpers/DietPlanRotationTests.cs so the app and
// the API pick the same plan day for a date.
void main() {
  // Wednesday 4 Nov 2026; its week starts Monday 2 Nov.
  final activated = DateTime.utc(2026, 11, 4, 15);

  int dayFor(DateTime date, int duration, [int maxDay = 0]) =>
      dietPlanDayIndexFor(date,
          activatedOn: activated,
          durationDays: duration,
          maxDayIndex: maxDay);

  test('a 7-day plan maps Monday..Sunday onto days 1..7', () {
    for (var i = 0; i < 14; i++) {
      final date = DateTime(2026, 11, 2 + i);
      expect(dayFor(date, 7), date.weekday);
    }
  });

  test('a multi-week plan advances weekly and loops', () {
    expect(dayFor(DateTime(2026, 11, 2), 28), 1);
    expect(dayFor(DateTime(2026, 11, 9), 28), 8);
    expect(dayFor(DateTime(2026, 12, 2), 28), 3); // looped on 30 Nov
    expect(dayFor(DateTime(2026, 11, 30), 28), 1);
    expect(dayFor(DateTime(2026, 11, 1), 28), 28); // the Sunday before
  });

  test('cycle covers duration and highest authored day in whole weeks', () {
    expect(dietPlanCycleLength(0, 0), 7);
    expect(dietPlanCycleLength(7, 0), 7);
    expect(dietPlanCycleLength(10, 0), 14);
    expect(dietPlanCycleLength(7, 15), 21);
    expect(dietPlanCycleLength(182, 0), 182);
  });

  test('protein-heavy threshold', () {
    expect(ProteinPartnerHint.isProteinHeavy(25, 900), isTrue);
    expect(ProteinPartnerHint.isProteinHeavy(20, 240), isTrue);
    expect(ProteinPartnerHint.isProteinHeavy(10, 600), isFalse);
    expect(ProteinPartnerHint.isProteinHeavy(5, 40), isFalse);
  });
}
