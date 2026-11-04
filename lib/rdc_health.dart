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
}
