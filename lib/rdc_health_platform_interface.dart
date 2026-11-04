import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'rdc_health_method_channel.dart';
import 'src/models.dart';

abstract class RdcHealthPlatform extends PlatformInterface {
  /// Constructs a RdcHealthPlatform.
  RdcHealthPlatform() : super(token: _token);

  static final Object _token = Object();

  static RdcHealthPlatform _instance = MethodChannelRdcHealth();

  /// The default instance of [RdcHealthPlatform] to use.
  ///
  /// Defaults to [MethodChannelRdcHealth].
  static RdcHealthPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [RdcHealthPlatform] when
  /// they register themselves.
  static set instance(RdcHealthPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// HealthKit 걸음 읽기와 쓰기(샘플 앱 시험용) 권한 요청. 요청 창 처리가 끝나면 true.
  /// 읽기를 허용했는지는 HealthKit이 알려 주지 않는다.
  Future<bool> requestHealthKitAuthorization() {
    throw UnimplementedError(
      'requestHealthKitAuthorization() has not been implemented.',
    );
  }

  Future<List<HealthStepSample>> healthStepSamples(DateTime from, DateTime to) {
    throw UnimplementedError('healthStepSamples() has not been implemented.');
  }
}
