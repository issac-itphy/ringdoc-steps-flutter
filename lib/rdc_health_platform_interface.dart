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

  /// 샘플 앱 시험용: 지금부터 1분 전까지 걸음 샘플 하나를 HealthKit에 쓴다.
  Future<void> writeTestSteps(int count) {
    throw UnimplementedError('writeTestSteps() has not been implemented.');
  }

  /// 걸음 관찰 쿼리와 백그라운드 전달을 켠다. 다음 앱 시작부터 자동으로 다시 켜진다.
  Future<void> enableBackgroundDelivery() {
    throw UnimplementedError(
      'enableBackgroundDelivery() has not been implemented.',
    );
  }

  Future<List<HealthLogEntry>> readLog() {
    throw UnimplementedError('readLog() has not been implemented.');
  }

  Future<void> appendLog(String event) {
    throw UnimplementedError('appendLog() has not been implemented.');
  }

  Future<void> clearLog() {
    throw UnimplementedError('clearLog() has not been implemented.');
  }

  /// CoreMotion 걸음 측정이 가능한지(시뮬레이터는 false). 비교용.
  Future<bool> isStepCountingAvailable() {
    throw UnimplementedError(
      'isStepCountingAvailable() has not been implemented.',
    );
  }

  /// CoreMotion 걸음을 [size] 칸으로 묶어 돌려준다. 비교용.
  Future<List<StepBucket>> stepBuckets(
    DateTime from,
    DateTime to,
    Duration size,
  ) {
    throw UnimplementedError('stepBuckets() has not been implemented.');
  }

  /// 관찰 쿼리가 새 걸음 샘플을 받을 때마다 내보낸다. Flutter 엔진이 떠 있을 때만 온다.
  Stream<List<HealthStepSample>> get stepSampleEvents {
    throw UnimplementedError('stepSampleEvents has not been implemented.');
  }
}
