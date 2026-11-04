import 'package:flutter_test/flutter_test.dart';
import 'package:rdc_health/rdc_health.dart';

final t10 = DateTime(2026, 11, 5, 10);

Map<String, Object?> sample(DateTime s, DateTime e, int n, String? model) => {
  'uuid': 'u',
  'start': s.millisecondsSinceEpoch,
  'end': e.millisecondsSinceEpoch,
  'count': n,
  'sourceName': 'x',
  'sourceBundleId': 'x',
  'deviceModel': model,
  'deviceName': null,
};

void main() {
  test('fromMap은 ms를 로컬 시각으로 바꾸고 Watch를 구분한다', () {
    final s = HealthStepSample.fromMap(
      sample(t10, t10.add(const Duration(minutes: 5)), 120, 'Watch'),
    );
    expect(s.start, t10);
    expect(s.count, 120);
    expect(s.isWatch, isTrue);
    expect(
      HealthStepSample.fromMap(sample(t10, t10, 1, 'iPhone')).isWatch,
      isFalse,
    );
    expect(
      HealthStepSample.fromMap(sample(t10, t10, 1, null)).isWatch,
      isFalse,
    );
  });

  test('Android는 기기 종류(deviceType)로 워치를 구분한다', () {
    final s = HealthStepSample.fromMap({
      ...sample(t10, t10, 1, 'SM-R960'),
      'deviceType': 'watch',
    });
    expect(s.deviceType, 'watch');
    expect(s.isWatch, isTrue);
    expect(
      HealthStepSample.fromMap({
        ...sample(t10, t10, 1, 'SM-S948N'),
        'deviceType': 'phone',
      }).isWatch,
      isFalse,
    );
  });

  test('StepBucket.fromMap', () {
    final b = StepBucket.fromMap({
      'start': t10.millisecondsSinceEpoch,
      'end': t10.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      'steps': 30,
    });
    expect(b.start, t10);
    expect(b.steps, 30);
  });
}
