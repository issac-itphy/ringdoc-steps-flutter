import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'rdc_health_platform_interface.dart';
import 'src/background.dart';
import 'src/models.dart';

/// An implementation of [RdcHealthPlatform] that uses method channels.
class MethodChannelRdcHealth extends RdcHealthPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('rdc_health');

  Map<String, int> _range(DateTime from, DateTime to) => {
    'from': from.millisecondsSinceEpoch,
    'to': to.millisecondsSinceEpoch,
  };

  @override
  Future<HealthAvailability> availability() async => HealthAvailability.parse(
    await methodChannel.invokeMethod<String>('availability'),
  );

  @override
  Future<bool> requestPermissions() async =>
      await methodChannel.invokeMethod<bool>('requestPermissions') ?? false;

  @override
  Future<void> enable(String userId) =>
      methodChannel.invokeMethod<void>('enable', {'userId': userId});

  @override
  Future<void> setActive(bool active) =>
      methodChannel.invokeMethod<void>('setActive', {'active': active});

  @override
  Future<void> disable() => methodChannel.invokeMethod<void>('disable');

  @override
  Future<List<MoveSegment>> moveSegments(DateTime from, DateTime to) async {
    final maps = await methodChannel.invokeListMethod<Map<Object?, Object?>>(
      'moveSegments',
      _range(from, to),
    );
    return [
      for (final map in maps ?? const <Map<Object?, Object?>>[])
        MoveSegment.fromMap(map),
    ];
  }

  @override
  Future<List<HourlySteps>> hourlySteps(DateTime from, DateTime to) async {
    final maps = await methodChannel.invokeListMethod<Map<Object?, Object?>>(
      'hourlySteps',
      _range(from, to),
    );
    return [
      for (final map in maps ?? const <Map<Object?, Object?>>[])
        HourlySteps.fromMap(map),
    ];
  }

  @override
  Future<void> setBackgroundHandler(Future<void> Function() handler) {
    final dispatcher = PluginUtilities.getCallbackHandle(
      rdcHealthBackgroundDispatcher,
    );
    final handlerHandle = PluginUtilities.getCallbackHandle(handler);
    if (dispatcher == null || handlerHandle == null) {
      throw ArgumentError.value(
        handler,
        'handler',
        '최상위 또는 static 함수여야 합니다(클로저 불가)',
      );
    }
    // 결정: iOS는 앱 엔진을 깨우므로 같은 `run` 호출이 메인 isolate로 온다. 여기서도 받아 둔다
    rdcHealthBackgroundChannel.setMethodCallHandler(handleBackgroundCall);
    return methodChannel.invokeMethod<void>('setBackgroundHandler', {
      'dispatcherHandle': dispatcher.toRawHandle(),
      'handlerHandle': handlerHandle.toRawHandle(),
    });
  }
}
