// 실제 플러그인으로 비교 표와 기록 화면이 열리는지 본다. 권한 없이도 돈다.
// fvm flutter test integration_test/screens_test.dart -d <기기 ID>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rdc_health/rdc_health.dart';
import 'package:rdc_health_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 화면의 비동기 조회가 끝날 때까지 기다린다
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('비교 표와 기록 화면이 열린다', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('비교 표'));
    await tester.pumpAndSettle();
    final header = find.text('시각   CoreMotion   HK iPhone 등   HK Watch');
    await pumpUntilFound(tester, header);
    expect(header, findsOneWidget);
    if (!await RdcHealth().isStepCountingAvailable()) {
      final unavailable = find.text('CoreMotion: 사용 불가(걸음 센서 없음)');
      await pumpUntilFound(tester, unavailable);
      expect(unavailable, findsOneWidget);
    }

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록 보기'));
    await tester.pumpAndSettle();
    final bootstrap = find.textContaining('bootstrap');
    await pumpUntilFound(tester, bootstrap);
    expect(find.widgetWithText(AppBar, '기록'), findsOneWidget);
    expect(bootstrap, findsWidgets);
  });
}
