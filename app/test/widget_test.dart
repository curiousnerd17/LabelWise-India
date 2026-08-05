import 'package:flutter_test/flutter_test.dart';

import 'package:labelwise/main.dart';

void main() {
  testWidgets('LabelWise app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const LabelWiseApp());

    expect(find.text('LabelWise India MVP'), findsOneWidget);
  });
}