// 시뮬레이터나 실기기에서 HealthKit 권한(걸음 읽기, 쓰기)을 한 번 허용한 뒤 실행한다.
// fvm flutter test integration_test/step_events_test.dart -d <기기 ID>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rdc_health/rdc_health.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('테스트 걸음을 쓰면 stepSampleEvents로 Flutter에 도착한다', (_) async {
    final health = RdcHealth();
    await health.enableBackgroundDelivery();
    // 다른 샘플과 섞이지 않게 흔치 않은 걸음 수로 구분
    final arrived = health.stepSampleEvents
        .firstWhere((samples) => samples.any((s) => s.count == 37))
        .timeout(const Duration(seconds: 30));

    await health.writeTestSteps(37);

    final samples = await arrived;
    expect(samples.any((s) => s.count == 37), isTrue);
    final log = await health.readLog();
    expect(log.any((e) => e.event == 'observer_fired'), isTrue);
  });
}
