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
}
