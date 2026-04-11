import 'package:crm/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows login action', (WidgetTester tester) async {
    await tester.pumpWidget(const CrmApp());
    await tester.pumpAndSettle();

    expect(find.text('Открыть рабочее пространство'), findsOneWidget);
  });
}
