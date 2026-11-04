import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdc_health/rdc_health_method_channel.dart';

import 'models_test.dart' show sample, t10;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelRdcHealth platform = MethodChannelRdcHealth();
  const MethodChannel channel = MethodChannel('rdc_health');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          calls.add(methodCall);
          switch (methodCall.method) {
            case 'requestHealthKitAuthorization':
              return true;
            case 'healthStepSamples':
              return [
                sample(t10, t10.add(const Duration(minutes: 5)), 120, 'Watch'),
              ];
          }
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('requestHealthKitAuthorization', () async {
    expect(await platform.requestHealthKitAuthorization(), isTrue);
  });

  test('healthStepSamples는 ms 인자를 보내고 Map을 샘플로 바꾼다', () async {
    final t11 = t10.add(const Duration(hours: 1));
    final samples = await platform.healthStepSamples(t10, t11);
    expect(calls.single.arguments, {
      'from': t10.millisecondsSinceEpoch,
      'to': t11.millisecondsSinceEpoch,
    });
    expect(samples.single.count, 120);
    expect(samples.single.isWatch, isTrue);
  });
}
