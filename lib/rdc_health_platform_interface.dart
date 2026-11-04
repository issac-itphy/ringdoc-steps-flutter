import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'rdc_health_method_channel.dart';

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
}
