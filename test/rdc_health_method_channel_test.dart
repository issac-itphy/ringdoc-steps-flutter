import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rdc_health/rdc_health.dart';
import 'package:rdc_health/rdc_health_method_channel.dart';

import 'models_test.dart' show t10;

// 최상위 함수여야 콜백 핸들을 얻을 수 있다
@pragma('vm:entry-point')
Future<void> topLevelHandler() async {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelRdcHealth();
  const channel = MethodChannel('rdc_health');
  final calls = <MethodCall>[];
  Object? availabilityReply = 'available';
  Object? permissionReply = true;
  Object? stepPermissionReply = true;
  final t11 = t10.add(const Duration(hours: 1));

  setUp(() {
    calls.clear();
    availabilityReply = 'available';
    permissionReply = true;
    stepPermissionReply = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'availability':
              return availabilityReply;
            case 'requestPermissions':
              return permissionReply;
            case 'stepPermissionGranted':
              return stepPermissionReply;
            case 'moveSegments':
              return [
                {
                  'start': t10.millisecondsSinceEpoch,
                  'end': t10
                      .add(const Duration(minutes: 5))
                      .millisecondsSinceEpoch,
                  'steps': 62,
                  'source': 'healthKit',
                },
              ];
            case 'hourlySteps':
              return [
                {'hourStart': t10.millisecondsSinceEpoch, 'steps': 410},
              ];
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('availability는 문자열을 enum으로 바꾸고 모르는 값은 unsupported', () async {
    expect(await platform.availability(), HealthAvailability.available);
    availabilityReply = 'needsInstall';
    expect(await platform.availability(), HealthAvailability.needsInstall);
    availabilityReply = 'brandNew';
    expect(await platform.availability(), HealthAvailability.unsupported);
    availabilityReply = null;
    expect(await platform.availability(), HealthAvailability.unsupported);
  });

  test('requestPermissions는 null이면 false', () async {
    expect(await platform.requestPermissions(), isTrue);
    permissionReply = null;
    expect(await platform.requestPermissions(), isFalse);
  });

  test('stepPermissionGranted는 true/false를 그대로, iOS의 null도 그대로 돌려준다', () async {
    expect(await platform.stepPermissionGranted(), isTrue);
    stepPermissionReply = false;
    expect(await platform.stepPermissionGranted(), isFalse);
    stepPermissionReply = null;
    expect(await platform.stepPermissionGranted(), isNull);
    expect(calls.map((c) => c.method), everyElement('stepPermissionGranted'));
  });

  test('enable, setActive, disable은 이름과 인자를 보낸다', () async {
    await platform.enable('u1');
    await platform.setActive(false);
    await platform.disable();
    expect(calls.map((c) => c.method), ['enable', 'setActive', 'disable']);
    expect(calls[0].arguments, {'userId': 'u1'});
    expect(calls[1].arguments, {'active': false});
    expect(calls[2].arguments, isNull);
  });

  test('moveSegments는 ms 범위를 보내고 Map을 구간으로 바꾼다', () async {
    final list = await platform.moveSegments(t10, t11);
    expect(calls.single.arguments, {
      'from': t10.millisecondsSinceEpoch,
      'to': t11.millisecondsSinceEpoch,
    });
    expect(list.single.steps, 62);
    expect(list.single.source, 'healthKit');
  });

  test('hourlySteps는 ms 범위를 보내고 Map을 시간별 걸음으로 바꾼다', () async {
    final list = await platform.hourlySteps(t10, t11);
    expect(calls.single.method, 'hourlySteps');
    expect(calls.single.arguments, {
      'from': t10.millisecondsSinceEpoch,
      'to': t11.millisecondsSinceEpoch,
    });
    expect(list.single.hourStart, t10);
    expect(list.single.steps, 410);
  });

  test('setBackgroundHandler는 최상위 함수의 핸들 둘을 보낸다', () async {
    await platform.setBackgroundHandler(topLevelHandler);
    final args = calls.single.arguments as Map;
    expect(calls.single.method, 'setBackgroundHandler');
    expect(args['dispatcherHandle'], isA<int>());
    expect(args['handlerHandle'], isA<int>());
  });

  test('setBackgroundHandler는 클로저면 ArgumentError', () {
    expect(
      () => platform.setBackgroundHandler(() async {}),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  test('네이티브가 run을 부르면 등록한 핸들러가 돈다', () async {
    ranHandler = false;
    await platform.setBackgroundHandler(markingHandler);
    final handle = (calls.single.arguments as Map)['handlerHandle'];
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'rdc_health/background',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('run', {'handlerHandle': handle}),
          ),
          (_) {},
        );
    expect(ranHandler, isTrue);
  });
}

var ranHandler = false;

@pragma('vm:entry-point')
Future<void> markingHandler() async {
  ranHandler = true;
}
