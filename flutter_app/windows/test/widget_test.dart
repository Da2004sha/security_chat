import 'package:flutter_test/flutter_test.dart';

import 'package:secure_corp_chat/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    expect(find.text('Защищённый чат'), findsOneWidget);
  });
}
