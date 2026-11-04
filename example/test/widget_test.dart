import 'package:flutter_test/flutter_test.dart';

import 'package:rdc_health_example/main.dart';

void main() {
  testWidgets('시험 화면이 뜨고 권한 요청 버튼이 있다', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('rdc_health 걸음 시험'), findsOneWidget);
    expect(find.text('권한 요청'), findsOneWidget);
  });
}
