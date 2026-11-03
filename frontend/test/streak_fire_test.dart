import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/widgets/streak_fire.dart';

void main() {
  test('streak fire heats up at 1, 7 and 30 days', () {
    expect(StreakFire.heatFor(0), StreakHeat.out);
    expect(StreakFire.heatFor(1), StreakHeat.lit);
    expect(StreakFire.heatFor(6), StreakHeat.lit);
    expect(StreakFire.heatFor(7), StreakHeat.hot);
    expect(StreakFire.heatFor(29), StreakHeat.hot);
    expect(StreakFire.heatFor(30), StreakHeat.blazing);
    expect(StreakFire.heatFor(365), StreakHeat.blazing);
    expect(StreakFire.nextStageAt(3), 7);
    expect(StreakFire.nextStageAt(12), 30);
    expect(StreakFire.nextStageAt(30), isNull);
  });
}
