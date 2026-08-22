import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/theme/widgets.dart';

void main() {
  testWidgets('MenuWidthLimit caps its child width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuWidthLimit(
            child: SizedBox(
              key: Key('child'),
              height: 10,
              width: double.infinity,
            ),
          ),
        ),
      ),
    );
    final Size size = tester.getSize(find.byKey(const Key('child')));
    expect(size.width, lessThanOrEqualTo(520));
  });
}
