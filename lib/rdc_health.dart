import 'rdc_health_platform_interface.dart';
import 'src/models.dart';

export 'src/models.dart';
export 'src/slot_comparison.dart';
export 'src/step_rhythm.dart';

/// 걸음 데이터와 깨우기만 제공한다. 판정 규칙은 본 앱이 가진다.
class RdcHealth {
  Future<HealthAvailability> availability() =>
      RdcHealthPlatform.instance.availability();

  Future<bool> requestPermissions() =>
      RdcHealthPlatform.instance.requestPermissions();

  Future<bool?> stepPermissionGranted() =>
      RdcHealthPlatform.instance.stepPermissionGranted();

  Future<void> enable(String userId) =>
      RdcHealthPlatform.instance.enable(userId);

  Future<void> setActive(bool active) =>
      RdcHealthPlatform.instance.setActive(active);

  Future<void> disable() => RdcHealthPlatform.instance.disable();

  Future<List<MoveSegment>> moveSegments(DateTime from, DateTime to) =>
      RdcHealthPlatform.instance.moveSegments(from, to);

  Future<List<HourlySteps>> hourlySteps(DateTime from, DateTime to) =>
      RdcHealthPlatform.instance.hourlySteps(from, to);

  Future<void> setBackgroundHandler(Future<void> Function() handler) =>
      RdcHealthPlatform.instance.setBackgroundHandler(handler);
}
