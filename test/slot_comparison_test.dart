import 'package:flutter_test/flutter_test.dart';
import 'package:rdc_health/rdc_health.dart';

import 'models_test.dart' show sample, t10;

void main() {
  test('두 칸에 걸친 샘플은 겹친 시간 비율로 나눈다', () {
    final rows = compareSlots(
      pedometer: const [],
      health: [
        HealthStepSample.fromMap(
          sample(
            t10.add(const Duration(minutes: 2, seconds: 30)),
            t10.add(const Duration(minutes: 7, seconds: 30)),
            100,
            'Watch',
          ),
        ),
      ],
      from: t10,
      to: t10.add(const Duration(minutes: 10)),
    );
    expect(rows.map((r) => r.healthWatchSteps), [50, 50]);
  });

  test('iPhone과 Watch 샘플을 나누고 CoreMotion 칸은 시작 시각으로 맞춘다', () {
    final rows = compareSlots(
      pedometer: [
        StepBucket(
          start: t10,
          end: t10.add(const Duration(minutes: 5)),
          steps: 30,
        ),
      ],
      health: [
        HealthStepSample.fromMap(
          sample(t10, t10.add(const Duration(minutes: 5)), 40, 'iPhone'),
        ),
      ],
      from: t10,
      to: t10.add(const Duration(minutes: 10)),
    );
    expect(rows.first.pedometerSteps, 30);
    expect(rows.first.healthIphoneSteps, 40);
    expect(rows.first.healthWatchSteps, 0);
    expect(rows.last.pedometerSteps, 0);
  });

  test('범위 밖 부분은 버린다', () {
    final rows = compareSlots(
      pedometer: const [],
      health: [
        HealthStepSample.fromMap(
          sample(
            t10.subtract(const Duration(minutes: 5)),
            t10.add(const Duration(minutes: 5)),
            100,
            'Watch',
          ),
        ),
      ],
      from: t10,
      to: t10.add(const Duration(minutes: 5)),
    );
    expect(rows.single.healthWatchSteps, 50);
  });

  test('길이가 0인 샘플은 시작 시각이 든 칸에 모두 넣는다', () {
    final rows = compareSlots(
      pedometer: const [],
      health: [
        HealthStepSample.fromMap(
          sample(
            t10.add(const Duration(minutes: 6)),
            t10.add(const Duration(minutes: 6)),
            7,
            null,
          ),
        ),
      ],
      from: t10,
      to: t10.add(const Duration(minutes: 10)),
    );
    expect(rows.map((r) => r.healthIphoneSteps), [0, 7]);
  });
}
