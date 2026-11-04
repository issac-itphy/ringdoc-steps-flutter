/// HealthKit 걸음 샘플 하나. 시각은 네이티브가 epoch ms로 넘김.
class HealthStepSample {
  const HealthStepSample({
    required this.uuid,
    required this.start,
    required this.end,
    required this.count,
    required this.sourceName,
    required this.sourceBundleId,
    this.deviceModel,
    this.deviceName,
  });

  factory HealthStepSample.fromMap(Map<Object?, Object?> map) =>
      HealthStepSample(
        uuid: map['uuid'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(map['start'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(map['end'] as int),
        count: map['count'] as int,
        sourceName: map['sourceName'] as String,
        sourceBundleId: map['sourceBundleId'] as String,
        deviceModel: map['deviceModel'] as String?,
        deviceName: map['deviceName'] as String?,
      );

  final String uuid;
  final DateTime start;
  final DateTime end;
  final int count;
  final String sourceName;
  final String sourceBundleId;
  final String? deviceModel;
  final String? deviceName;

  // 결정: HKDevice.model이 "Watch"면 워치 샘플로 봄 [불확실: 실기기 값 확인 전]
  bool get isWatch => deviceModel == 'Watch';
}

/// CoreMotion 걸음을 일정 간격으로 묶은 칸.
class StepBucket {
  const StepBucket({
    required this.start,
    required this.end,
    required this.steps,
  });

  factory StepBucket.fromMap(Map<Object?, Object?> map) => StepBucket(
    start: DateTime.fromMillisecondsSinceEpoch(map['start'] as int),
    end: DateTime.fromMillisecondsSinceEpoch(map['end'] as int),
    steps: map['steps'] as int,
  );

  final DateTime start;
  final DateTime end;
  final int steps;
}
