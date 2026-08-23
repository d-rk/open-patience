import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/presentation/board_geometry.dart';
import 'package:open_patience/presentation/board_sequence.dart';
import 'package:open_patience/ui/theme/game_motion.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

GameState _dealt() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 5)]),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, 8)]),
    for (int i = 0; i < 5; i++) Pile(kind: PileKind.tableau),
  ],
);

void main() {
  test('DealSequence matches the first render', () {
    expect(const DealSequence().matches(null, _dealt()), isTrue);
  });

  test('DealSequence does not match an ordinary move', () {
    final GameState a = _dealt();
    expect(const DealSequence().matches(a, a), isFalse);
  });

  test('later cards in deal order get longer delays', () {
    const DealSequence s = DealSequence();
    final BoardGeometry g = BoardGeometry.resolve(
      game: _dealt(),
      width: 400,
      height: 800,
      shortestSide: 400,
      isLandscape: false,
      wasteVisibleCount: 1,
    );
    final Duration d5 = s.delayFor(const CardKey(Suit.spades, 5), g);
    final Duration d8 = s.delayFor(const CardKey(Suit.hearts, 8), g);
    expect(d5, isNot(equals(d8)));
    expect(s.totalFor(g), greaterThanOrEqualTo(GameMotion.move));
  });

  test('deal total scales to the animated-card count, not a fixed 52', () {
    const DealSequence s = DealSequence();
    final BoardGeometry g = BoardGeometry.resolve(
      game: _dealt(),
      width: 400,
      height: 800,
      shortestSide: 400,
      isLandscape: false,
      wasteVisibleCount: 1,
    );
    // _dealt lays out only its two tableau cards (empty stock/waste/foundations
    // show as slots), so the controller is sized for those, not a full deck.
    final Duration expected =
        GameMotion.dealStagger * (g.cards.length - 1) + GameMotion.move;
    expect(s.totalFor(g), expected);
    final Duration fullDeck = GameMotion.dealStagger * 51 + GameMotion.move;
    expect(s.totalFor(g), lessThan(fullDeck));
  });

  test('WinSequence pulse starts and returns to rest scale', () {
    const WinSequence w = WinSequence();
    expect(w.pulseAt(Duration.zero), closeTo(1.0, 0.001));
    expect(w.pulseAt(w.total), closeTo(1.0, 0.02));
    expect(w.pulseAt(w.total ~/ 2), greaterThan(1.0));
  });
}
