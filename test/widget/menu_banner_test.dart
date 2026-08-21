import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/widgets/menu_banner.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('MenuBanner shows the banner asset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(const MenuBanner()));
    final Image img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<AssetImage>());
    expect(
      (img.image as AssetImage).assetName,
      'assets/images/menu_banner.png',
    );
  });

  testWidgets('MenuBanner settles (no pending timers) under reduced motion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const MenuBanner(), disableAnimations: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MenuBanner), findsOneWidget);
  });
}
