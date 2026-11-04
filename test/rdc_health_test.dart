import 'package:flutter_test/flutter_test.dart';
import 'package:rdc_health/rdc_health.dart';
import 'package:rdc_health/rdc_health_platform_interface.dart';
import 'package:rdc_health/rdc_health_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockRdcHealthPlatform
    with MockPlatformInterfaceMixin
    implements RdcHealthPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final RdcHealthPlatform initialPlatform = RdcHealthPlatform.instance;

  test('$MethodChannelRdcHealth is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelRdcHealth>());
  });

  test('getPlatformVersion', () async {
    RdcHealth rdcHealthPlugin = RdcHealth();
    MockRdcHealthPlatform fakePlatform = MockRdcHealthPlatform();
    RdcHealthPlatform.instance = fakePlatform;

    expect(await rdcHealthPlugin.getPlatformVersion(), '42');
  });
}
