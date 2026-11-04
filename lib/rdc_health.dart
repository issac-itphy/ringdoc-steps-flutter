
import 'rdc_health_platform_interface.dart';

class RdcHealth {
  Future<String?> getPlatformVersion() {
    return RdcHealthPlatform.instance.getPlatformVersion();
  }
}
