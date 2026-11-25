// 실기기에서 네이티브 구현이 availability에 답하는지만 본다(G1b/G1c 이후).
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:rdc_health/rdc_health.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('availability test', (WidgetTester tester) async {
    expect(await RdcHealth().availability(), isA<HealthAvailability>());
  });
}
