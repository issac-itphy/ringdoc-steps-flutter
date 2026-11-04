import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'rdc_health_platform_interface.dart';

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
}
