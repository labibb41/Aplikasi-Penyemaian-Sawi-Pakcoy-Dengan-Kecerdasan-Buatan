import 'package:flutter_test/flutter_test.dart';
import 'package:semaiku/main.dart';

void main() {
  testWidgets('App renders splash screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SemaiKuApp());
    expect(find.byType(SemaiKuApp), findsOneWidget);
  });
}
