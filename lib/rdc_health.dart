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

  Future<void> writeTestSteps(int count) =>
      RdcHealthPlatform.instance.writeTestSteps(count);

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

  Future<void> scheduleTestNotification(int minutes) =>
      RdcHealthPlatform.instance.scheduleTestNotification(minutes);

  Stream<List<HealthStepSample>> get stepSampleEvents =>
      RdcHealthPlatform.instance.stepSampleEvents;
}
