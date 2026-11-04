/// 걸음 샘플 하나(iOS HealthKit, Android Health Connect). 시각은 네이티브가 epoch ms로 넘김.
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

/// 네이티브가 기기 안 파일에 남긴 실행 기록 한 줄.
class HealthLogEntry {
  const HealthLogEntry({
    required this.at,
    required this.event,
    required this.appState,
    required this.protectedData,
    required this.detail,
  });

  factory HealthLogEntry.fromMap(Map<Object?, Object?> map) => HealthLogEntry(
    at: DateTime.fromMillisecondsSinceEpoch(map['at'] as int),
    event: map['event'] as String,
    appState: map['appState'] as String,
    protectedData: map['protectedData'] as bool,
    detail: Map<String, Object?>.from(map['detail'] as Map),
  );

  final DateTime at;
  final String event;

  /// active, inactive, background
  final String appState;

  /// false면 기기가 잠겨 HealthKit을 읽을 수 없는 상태.
  final bool protectedData;
  final Map<String, Object?> detail;
}
