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

  /// [detail]은 기록 줄의 detail에 그대로 들어간다(S8 되짚기 결과 등).
  Future<void> appendLog(
    String event, [
    Map<String, Object?> detail = const {},
  ]) {
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

  /// 건강 저장소 걸음을 [size] 칸으로 묶은 합계(S8 걸음 리듬). iOS는 HealthKit 통계 쿼리라 iPhone과 워치가 겹친 걸음을 한 번만 센다.
  /// Android는 Health Connect 집계라 삼성 헬스 하루 기록은 시간 비율로 나뉜 값이 된다(2026-11-06 T1).
  Future<List<StepBucket>> healthStepBuckets(
    DateTime from,
    DateTime to,
    Duration size,
  ) {
    throw UnimplementedError('healthStepBuckets() has not been implemented.');
  }

  /// 기기와 건강 저장소 상태(Android: Health Connect 상태와 기능, 삼성 헬스, 허용된 권한). 시험용.
  Future<Map<String, Object?>> deviceInfo() {
    throw UnimplementedError('deviceInfo() has not been implemented.');
  }

  /// Health Connect 집계 확인(Android 전용, 시험용): 오늘 합계 집계, 1시간 단위 집계, 기록 단건을 한 번에 돌려준다.
  Future<Map<String, Object?>> aggregateCheck() {
    throw UnimplementedError('aggregateCheck() has not been implemented.');
  }

  /// T4 시험용(Android 전용): minutes 분 뒤 로컬 알림을 부정확 알람으로 예약한다. 그 전에 걸음이 늘면 주기 작업이 취소한다.
  Future<void> scheduleTestNotification(int minutes) {
    throw UnimplementedError(
      'scheduleTestNotification() has not been implemented.',
    );
  }

  /// 관찰 쿼리가 새 걸음 샘플을 받을 때마다 내보낸다. Flutter 엔진이 떠 있을 때만 온다.
  Stream<List<HealthStepSample>> get stepSampleEvents {
    throw UnimplementedError('stepSampleEvents has not been implemented.');
  }
}
