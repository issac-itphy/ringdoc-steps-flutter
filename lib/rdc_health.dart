import 'rdc_health_platform_interface.dart';
import 'src/models.dart';

export 'src/models.dart';
export 'src/slot_comparison.dart';

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

  Future<void> appendLog(String event) =>
      RdcHealthPlatform.instance.appendLog(event);

  Future<void> clearLog() => RdcHealthPlatform.instance.clearLog();

  Future<bool> isStepCountingAvailable() =>
      RdcHealthPlatform.instance.isStepCountingAvailable();

  Future<List<StepBucket>> stepBuckets(
    DateTime from,
    DateTime to,
    Duration size,
  ) => RdcHealthPlatform.instance.stepBuckets(from, to, size);

  Future<Map<String, Object?>> deviceInfo() =>
      RdcHealthPlatform.instance.deviceInfo();

  Stream<List<HealthStepSample>> get stepSampleEvents =>
      RdcHealthPlatform.instance.stepSampleEvents;
}
