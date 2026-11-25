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

  /// 걸음 수집 가능 상태 하나. iOS는 HealthKit 사용 가능, Android는 활동 인식과 Play 서비스 버전, API 28 이상이면 Health Connect 설치 여부.
  Future<HealthAvailability> availability() {
    throw UnimplementedError('availability() has not been implemented.');
  }

  /// 휴대폰 권한 요청(iOS 걸음 읽기, Android 신체 활동과 Health Connect 걸음 읽기, 백그라운드 읽기). 허용되면 true.
  Future<bool> requestPermissions() {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }

  /// 수집 스위치를 켜고 등록한다(iOS 관찰 쿼리와 백그라운드 전달, Android 활동 전환, Recording API 구독, Health Connect 변경 토큰, 주기 작업).
  Future<void> enable(String userId) {
    throw UnimplementedError('enable() has not been implemented.');
  }

  /// 로그아웃용. 기록만 멈추고 등록은 유지한다.
  Future<void> setActive(bool active) {
    throw UnimplementedError('setActive() has not been implemented.');
  }

  /// 모든 등록을 풀고 네이티브 파일을 지운다. 여러 번 불러도 안전하다.
  Future<void> disable() {
    throw UnimplementedError('disable() has not been implemented.');
  }

  /// 이동 구간 목록(5분, 50걸음 이상).
  Future<List<MoveSegment>> moveSegments(DateTime from, DateTime to) {
    throw UnimplementedError('moveSegments() has not been implemented.');
  }

  /// 시간별 걸음 수.
  Future<List<HourlySteps>> hourlySteps(DateTime from, DateTime to) {
    throw UnimplementedError('hourlySteps() has not been implemented.');
  }

  /// OS가 앱을 깨울 때 실행할 Dart 함수를 등록한다. [handler]는 `@pragma('vm:entry-point')`가 붙은 최상위 또는 static 함수여야 한다(아니면 [ArgumentError]).
  Future<void> setBackgroundHandler(Future<void> Function() handler) {
    throw UnimplementedError(
      'setBackgroundHandler() has not been implemented.',
    );
  }
}
