import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 네이티브 <-> Dart 백그라운드 채널.
///
/// 네이티브가 Dart로 부르는 메서드:
/// - `run` {handlerHandle: int}: OS가 앱을 깨웠을 때. 등록한 핸들러를 실행하고 끝나면 반환한다.
///   iOS는 앱 엔진(메인 isolate)에서, Android는 헤드리스 엔진([rdcHealthBackgroundDispatcher])에서 온다.
///   네이티브는 이 호출의 결과(성공/오류)를 받으면 HealthKit 완료 콜백을 부르거나 엔진을 끈다.
/// Dart가 네이티브로 부르는 메서드(헤드리스 엔진만):
/// - `ready`: 디스패처가 `run`을 받을 준비를 마침. 네이티브는 이 신호 전에는 `run`을 보내지 않는다.
const rdcHealthBackgroundChannel = MethodChannel('rdc_health/background');

/// 헤드리스 엔진의 진입점. 네이티브가 `setBackgroundHandler`로 받은 dispatcherHandle로 시작한다.
@pragma('vm:entry-point')
Future<void> rdcHealthBackgroundDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  rdcHealthBackgroundChannel.setMethodCallHandler(handleBackgroundCall);
  await rdcHealthBackgroundChannel.invokeMethod<void>('ready');
}

/// `run` 호출 처리. 헤드리스 엔진과 메인 isolate가 함께 쓴다.
Future<Object?> handleBackgroundCall(MethodCall call) async {
  if (call.method != 'run') return null;
  final handle = (call.arguments as Map)['handlerHandle'] as int;
  final callback = PluginUtilities.getCallbackFromHandle(
    CallbackHandle.fromRawHandle(handle),
  );
  if (callback == null) {
    throw PlatformException(code: 'no_handler', message: 'handle $handle');
  }
  try {
    await (callback as Future<void> Function())();
  } catch (error, stack) {
    // 결정: 오류는 보고만 하고 다시 던진다. 네이티브가 실패 결과를 받아 어느 쪽이든 완료 처리하게 함
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'rdc_health',
      ),
    );
    throw PlatformException(code: 'handler_failed', message: '$error');
  }
  return null;
}
