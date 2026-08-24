import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/solve_reveal.dart';

/// Pumps a [SolveReveal] carrying a marker child, with [visible] and
/// [reduceMotion] controllable so a rebuild toggles the reveal on. The tree
/// shape is stable across rebuilds so the [SolveReveal] element (and its
/// animation state) persists and sees the false → true edge.
Widget _host({required bool visible, bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(
          child: SolveReveal(visible: visible, child: const Text('WAND')),
        ),
      ),
    ),
  );
}

double _scale(WidgetTester tester) => tester
    .widget<ScaleTransition>(
      find.byKey(const ValueKey<String>('solve-reveal-scale')),
    )
    .scale
    .value;

void main() {
  testWidgets('renders nothing while not visible', (WidgetTester tester) async {
    await tester.pumpWidget(_host(visible: false));

    expect(find.text('WAND'), findsNothing);
  });

  testWidgets('grows its child in when it becomes visible', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(visible: false));
    expect(find.text('WAND'), findsNothing);

    // The board just became solvable: flip the reveal on.
    await tester.pumpWidget(_host(visible: true));
    await tester.pump();

    // Mid-entrance the child is smaller than its resting size — it grows in.
    expect(find.text('WAND'), findsOneWidget);
    expect(_scale(tester), lessThan(1.0));

    await tester.pumpAndSettle();
    expect(_scale(tester), 1.0);
  });

  testWidgets('shows the child at full size at once under reduce-motion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(visible: false, reduceMotion: true));
    await tester.pumpWidget(_host(visible: true, reduceMotion: true));
    await tester.pump();

    // No entrance animation to play: the child lands full size immediately.
    expect(find.text('WAND'), findsOneWidget);
    expect(_scale(tester), 1.0);
  });
}
