import 'package:flutter_test/flutter_test.dart';

import 'package:saveduk/app.dart';

void main() {
  testWidgets('SaveDuk app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SaveDukApp());
    expect(find.text('SAVE//DUK'), findsOneWidget);
  });
}
