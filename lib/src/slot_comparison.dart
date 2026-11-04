import 'models.dart';

/// 한 칸(기본 5분)의 출처별 걸음.
class SlotComparison {
  const SlotComparison({
    required this.start,
    required this.pedometerSteps,
    required this.healthIphoneSteps,
    required this.healthWatchSteps,
  });

  final DateTime start;
  final int pedometerSteps;

  /// 워치가 아닌 HealthKit 샘플(iPhone, 직접 입력 등).
  final int healthIphoneSteps;
  final int healthWatchSteps;
}

/// [from]부터 [to]까지 [size] 칸마다 CoreMotion과 HealthKit 걸음을 나란히 놓는다.
/// 칸에 걸친 HealthKit 샘플은 겹친 시간 비율로 나눈다.
List<SlotComparison> compareSlots({
  required List<StepBucket> pedometer,
  required List<HealthStepSample> health,
  required DateTime from,
  required DateTime to,
  Duration size = const Duration(minutes: 5),
}) {
  final rows = <SlotComparison>[];
  for (var start = from; start.isBefore(to); start = start.add(size)) {
    final end = start.add(size).isAfter(to) ? to : start.add(size);
    var iphone = 0.0;
    var watch = 0.0;
    for (final sample in health) {
      final steps = _share(sample, start, end) * sample.count;
      if (sample.isWatch) {
        watch += steps;
      } else {
        iphone += steps;
      }
    }
    rows.add(
      SlotComparison(
        start: start,
        pedometerSteps: pedometer
            .where((b) => b.start == start)
            .fold(0, (sum, b) => sum + b.steps),
        healthIphoneSteps: iphone.round(),
        healthWatchSteps: watch.round(),
      ),
    );
  }
  return rows;
}

/// 샘플 가운데 [start, end) 칸에 속하는 비율.
double _share(HealthStepSample sample, DateTime start, DateTime end) {
  final total = sample.end.difference(sample.start).inMilliseconds;
  if (total <= 0) {
    return !sample.start.isBefore(start) && sample.start.isBefore(end) ? 1 : 0;
  }
  final from = sample.start.isAfter(start) ? sample.start : start;
  final to = sample.end.isBefore(end) ? sample.end : end;
  final overlap = to.difference(from).inMilliseconds;
  return overlap > 0 ? overlap / total : 0;
}
