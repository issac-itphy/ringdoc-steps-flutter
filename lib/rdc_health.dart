import 'rdc_health_platform_interface.dart';
import 'src/models.dart';

export 'src/models.dart';
export 'src/slot_comparison.dart';
export 'src/step_rhythm.dart';

class RdcHealth {
  Future<String?> getPlatformVersion() {
    return RdcHealthPlatform.instance.getPlatformVersion();
  }

  Future<bool> requestHealthKitAuthorization() =>
      RdcHealthPlatform.instance.requestHealthKitAuthorization();

  Future<List<HealthStepSample>> healthStepSamples(
    DateTime from,
    DateTime to,
  ) => RdcHealthPlatform.instance.healthStepSamples(from, to);

  Future<void> writeTestSteps(int count, {int daysAgo = 0}) =>
      RdcHealthPlatform.instance.writeTestSteps(count, daysAgo: daysAgo);

  Future<void> enableBackgroundDelivery() =>
      RdcHealthPlatform.instance.enableBackgroundDelivery();

  Future<List<HealthLogEntry>> readLog() =>
      RdcHealthPlatform.instance.readLog();

  Future<void> appendLog(
    String event, [
    Map<String, Object?> detail = const {},
  ]) => RdcHealthPlatform.instance.appendLog(event, detail);

  Future<void> clearLog() => RdcHealthPlatform.instance.clearLog();

  Future<bool> isStepCountingAvailable() =>
      RdcHealthPlatform.instance.isStepCountingAvailable();

  Future<List<StepBucket>> stepBuckets(
    DateTime from,
    DateTime to,
    Duration size,
  ) => RdcHealthPlatform.instance.stepBuckets(from, to, size);

  Future<List<StepBucket>> healthStepBuckets(
    DateTime from,
    DateTime to,
    Duration size,
  ) => RdcHealthPlatform.instance.healthStepBuckets(from, to, size);

  Future<Map<String, Object?>> deviceInfo() =>
      RdcHealthPlatform.instance.deviceInfo();

  Future<Map<String, Object?>> aggregateCheck() =>
      RdcHealthPlatform.instance.aggregateCheck();

  /// [alarmClock]이면 본 앱과 같은 정확한 알람(setAlarmClock). 권한이 없으면 false.
  Future<bool> scheduleTestNotification(
    int minutes, {
    bool alarmClock = false,
  }) => RdcHealthPlatform.instance.scheduleTestNotification(
    minutes,
    alarmClock: alarmClock,
  );

  Stream<List<HealthStepSample>> get stepSampleEvents =>
      RdcHealthPlatform.instance.stepSampleEvents;
}
