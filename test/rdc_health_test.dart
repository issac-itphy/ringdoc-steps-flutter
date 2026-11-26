import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rdc_health/rdc_health.dart';
import 'package:rdc_health/rdc_health_method_channel.dart';
import 'package:rdc_health/rdc_health_platform_interface.dart';

// 결정: implements 대신 extends. 플랫폼 메서드가 늘어나도 이 Mock을 고치지 않아도 됨
class MockRdcHealthPlatform extends RdcHealthPlatform
    with MockPlatformInterfaceMixin {
  final calls = <String>[];

  @override
  Future<HealthAvailability> availability() async =>
      HealthAvailability.needsInstall;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool?> stepPermissionGranted() async => null;

  @override
  Future<void> enable(String userId) async => calls.add('enable:$userId');

  @override
  Future<void> setActive(bool active) async => calls.add('setActive:$active');

  @override
  Future<void> disable() async => calls.add('disable');

  @override
  Future<List<MoveSegment>> moveSegments(DateTime from, DateTime to) async => [
    MoveSegment(start: from, end: to, steps: 60, source: 'recording'),
  ];

  @override
  Future<List<HourlySteps>> hourlySteps(DateTime from, DateTime to) async => [
    HourlySteps(hourStart: from, steps: 7),
  ];

  @override
  Future<void> setBackgroundHandler(Future<void> Function() handler) async =>
      calls.add('setBackgroundHandler');
}

void main() {
  final RdcHealthPlatform initialPlatform = RdcHealthPlatform.instance;

  test('$MethodChannelRdcHealth is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelRdcHealth>());
  });

  test('RdcHealth는 9개 호출을 플랫폼으로 넘긴다', () async {
    final fake = MockRdcHealthPlatform();
    RdcHealthPlatform.instance = fake;
    final health = RdcHealth();
    final t = DateTime(2026, 11, 5, 10);

    expect(await health.availability(), HealthAvailability.needsInstall);
    expect(await health.requestPermissions(), isTrue);
    expect(await health.stepPermissionGranted(), isNull);
    await health.enable('u1');
    await health.setActive(true);
    await health.disable();
    expect((await health.moveSegments(t, t)).single.steps, 60);
    expect((await health.hourlySteps(t, t)).single.steps, 7);
    await health.setBackgroundHandler(() async {});
    expect(fake.calls, [
      'enable:u1',
      'setActive:true',
      'disable',
      'setBackgroundHandler',
    ]);
  });
}
