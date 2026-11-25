/// 건강 걸음 수집 가능 상태. 네이티브가 문자열로 넘긴다.
enum HealthAvailability {
  available,
  needsInstall,
  unsupported;

  // 결정: 모르는 문자열은 unsupported로 처리. 새 값이 생겨도 옛 앱이 죽지 않게 함
  static HealthAvailability parse(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => HealthAvailability.unsupported,
  );
}

/// 이동 구간 하나(5분, 50걸음 이상). 시각은 epoch ms.
class MoveSegment {
  const MoveSegment({
    required this.start,
    required this.end,
    required this.steps,
    required this.source,
  });

  factory MoveSegment.fromMap(Map<Object?, Object?> map) => MoveSegment(
    start: DateTime.fromMillisecondsSinceEpoch(map['start'] as int),
    end: DateTime.fromMillisecondsSinceEpoch(map['end'] as int),
    steps: map['steps'] as int,
    source: map['source'] as String,
  );

  final DateTime start;
  final DateTime end;
  final int steps;

  // 결정: 출처는 enum 대신 문자열. 네이티브가 새 출처를 넣어도 파싱이 깨지지 않음
  /// coreMotion, healthKit, activityTransition, recording, healthConnect
  final String source;
}

/// 한 시간 걸음 수.
class HourlySteps {
  const HourlySteps({required this.hourStart, required this.steps});

  factory HourlySteps.fromMap(Map<Object?, Object?> map) => HourlySteps(
    hourStart: DateTime.fromMillisecondsSinceEpoch(map['hourStart'] as int),
    steps: map['steps'] as int,
  );

  final DateTime hourStart;
  final int steps;
}

/// 걸음 샘플 하나. 공개 API는 아니고 S8 분석 코드(slot_comparison)의 입력 모델이다. 시각은 epoch ms.
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
    this.deviceType,
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
        deviceType: map['deviceType'] as String?,
      );

  final String uuid;
  final DateTime start;
  final DateTime end;
  final int count;
  final String sourceName;
  final String sourceBundleId;
  final String? deviceModel;
  final String? deviceName;

  /// Android Health Connect의 기기 종류(watch, phone 등). iOS는 null.
  final String? deviceType;

  // 결정: iOS는 HKDevice.model이 "Watch", Android는 기기 종류가 watch면 워치 샘플로 봄 [불확실: 실기기 값 확인 전]
  bool get isWatch => deviceModel == 'Watch' || deviceType == 'watch';
}

/// 걸음을 일정 간격으로 묶은 칸. 공개 API는 아니고 S8 분석 코드(slot_comparison)의 입력 모델이다.
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
