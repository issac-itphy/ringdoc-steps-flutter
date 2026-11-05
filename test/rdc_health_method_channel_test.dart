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
            case 'readLog':
              return [
                {
                  'at': t10.millisecondsSinceEpoch,
                  'event': 'observer_fired',
                  'appState': 'background',
                  'protectedData': false,
                  'detail': {'newSamples': 1},
                },
              ];
            case 'getPlatformVersion':
              return '42';
            case 'isStepCountingAvailable':
              return false;
            case 'deviceInfo':
              return {
                'platform': 'android',
                'sdk': 36,
                'granted': ['READ_STEPS'],
              };
            case 'stepBuckets':
              return [
                {
                  'start': t10.millisecondsSinceEpoch,
                  'end': t10
                      .add(const Duration(minutes: 5))
                      .millisecondsSinceEpoch,
                  'steps': 30,
                },
              ];
          }
          return null;
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

  test('writeTestSteps는 걸음 수를 보낸다', () async {
    await platform.writeTestSteps(50);
    expect(calls.single.method, 'writeTestSteps');
    expect(calls.single.arguments, {'count': 50});
  });

  test('appendLog는 이벤트 이름을 보낸다', () async {
    await platform.appendLog('dart_main');
    expect(calls.single.arguments, {'event': 'dart_main'});
  });

  test('readLog는 Map을 HealthLogEntry로 바꾼다', () async {
    final entry = (await platform.readLog()).single;
    expect(entry.at, t10);
    expect(entry.event, 'observer_fired');
    expect(entry.appState, 'background');
    expect(entry.protectedData, isFalse);
    expect(entry.detail['newSamples'], 1);
  });

  test('isStepCountingAvailable', () async {
    expect(await platform.isStepCountingAvailable(), isFalse);
  });

  test('stepBuckets는 ms와 칸 크기(초)를 보내고 Map을 칸으로 바꾼다', () async {
    final to = t10.add(const Duration(minutes: 10));
    final buckets = await platform.stepBuckets(
      t10,
      to,
      const Duration(minutes: 5),
    );
    expect(calls.single.arguments, {
      'from': t10.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
      'sizeSec': 300,
    });
    expect(buckets.single.steps, 30);
  });

  test('deviceInfo는 기기 정보 Map을 그대로 돌려준다', () async {
    final info = await platform.deviceInfo();
    expect(info['platform'], 'android');
    expect(info['sdk'], 36);
    expect(info['granted'], ['READ_STEPS']);
  });

  test('onStepSamples를 받으면 stepSampleEvents가 샘플을 내보낸다', () async {
    final next = platform.stepSampleEvents.first;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'rdc_health',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onStepSamples', {
              'samples': [
                sample(t10, t10.add(const Duration(minutes: 1)), 50, null),
              ],
            }),
          ),
          (_) {},
        );
    expect((await next).single.count, 50);
  });
}
