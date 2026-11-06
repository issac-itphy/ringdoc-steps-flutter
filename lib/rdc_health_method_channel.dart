import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'rdc_health_platform_interface.dart';
import 'src/models.dart';

/// An implementation of [RdcHealthPlatform] that uses method channels.
class MethodChannelRdcHealth extends RdcHealthPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('rdc_health');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<bool> requestHealthKitAuthorization() async =>
      await methodChannel.invokeMethod<bool>('requestHealthKitAuthorization') ??
      false;

  @override
  Future<List<HealthStepSample>> healthStepSamples(
    DateTime from,
    DateTime to,
  ) async {
    final maps = await methodChannel.invokeListMethod<Map<Object?, Object?>>(
      'healthStepSamples',
      {'from': from.millisecondsSinceEpoch, 'to': to.millisecondsSinceEpoch},
    );
    return [
      for (final map in maps ?? const <Map<Object?, Object?>>[])
        HealthStepSample.fromMap(map),
    ];
  }

  @override
  Future<void> writeTestSteps(int count, {int daysAgo = 0}) =>
      methodChannel.invokeMethod<void>('writeTestSteps', {
        'count': count,
        'daysAgo': daysAgo,
      });

  @override
  Future<void> enableBackgroundDelivery() =>
      methodChannel.invokeMethod<void>('enableBackgroundDelivery');

  @override
  Future<List<HealthLogEntry>> readLog() async {
    final maps = await methodChannel.invokeListMethod<Map<Object?, Object?>>(
      'readLog',
    );
    return [
      for (final map in maps ?? const <Map<Object?, Object?>>[])
        HealthLogEntry.fromMap(map),
    ];
  }

  @override
  Future<void> appendLog(
    String event, [
    Map<String, Object?> detail = const {},
  ]) => methodChannel.invokeMethod<void>('appendLog', {
    'event': event,
    if (detail.isNotEmpty) 'detail': detail,
  });

  @override
  Future<void> clearLog() => methodChannel.invokeMethod<void>('clearLog');

  @override
  Future<bool> isStepCountingAvailable() async =>
      await methodChannel.invokeMethod<bool>('isStepCountingAvailable') ??
      false;

  @override
  Future<List<StepBucket>> stepBuckets(
    DateTime from,
    DateTime to,
    Duration size,
  ) async {
    final maps = await methodChannel
        .invokeListMethod<Map<Object?, Object?>>('stepBuckets', {
          'from': from.millisecondsSinceEpoch,
          'to': to.millisecondsSinceEpoch,
          'sizeSec': size.inSeconds,
        });
    return [
      for (final map in maps ?? const <Map<Object?, Object?>>[])
        StepBucket.fromMap(map),
    ];
  }

  @override
  Future<List<StepBucket>> healthStepBuckets(
    DateTime from,
    DateTime to,
    Duration size,
  ) async {
    final maps = await methodChannel
        .invokeListMethod<Map<Object?, Object?>>('healthStepBuckets', {
          'from': from.millisecondsSinceEpoch,
          'to': to.millisecondsSinceEpoch,
          'sizeSec': size.inSeconds,
        });
    return [
      for (final map in maps ?? const <Map<Object?, Object?>>[])
        StepBucket.fromMap(map),
    ];
  }

  @override
  Future<Map<String, Object?>> deviceInfo() async =>
      await methodChannel.invokeMapMethod<String, Object?>('deviceInfo') ?? {};

  @override
  Future<Map<String, Object?>> aggregateCheck() async =>
      await methodChannel.invokeMapMethod<String, Object?>('aggregateCheck') ??
      {};

  @override
  Future<bool> scheduleTestNotification(
    int minutes, {
    bool alarmClock = false,
  }) async =>
      await methodChannel.invokeMethod<bool>('scheduleTestNotification', {
        'minutes': minutes,
        'alarmClock': alarmClock,
      }) ??
      false;

  final _stepSamples = StreamController<List<HealthStepSample>>.broadcast();

  // 결정: 네이티브 → Dart 호출 처리기는 스트림을 처음 볼 때 단다. 생성자에서 달면 바인딩 초기화 전 생성 시 실패
  @override
  Stream<List<HealthStepSample>> get stepSampleEvents {
    methodChannel.setMethodCallHandler(_onNativeCall);
    return _stepSamples.stream;
  }

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method == 'onStepSamples') {
      final maps = (call.arguments as Map)['samples'] as List;
      _stepSamples.add([
        for (final map in maps)
          HealthStepSample.fromMap(map as Map<Object?, Object?>),
      ]);
    }
    return null;
  }
}
