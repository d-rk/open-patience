import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/move.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/presentation/sound/sound_cue.dart';

const Card _sevenSpades = Card(suit: Suit.spades, rank: 7, faceUp: true);

GameState _board() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.freecell),
  ],
);

Move _to(int pile, {bool flipMovedCards = false}) => Move(
  fromPile: 3,
  toPile: pile,
  cards: const <Card>[_sevenSpades],
  flipMovedCards: flipMovedCards,
);

void main() {
  test('a move onto a foundation is the foundation cue', () {
    expect(cueForMove(_to(2), _board()), SoundCue.foundation);
  });

  test('a stock draw or waste recycle (cards flipped in flight) is draw', () {
    expect(cueForMove(_to(1, flipMovedCards: true), _board()), SoundCue.draw);
    expect(cueForMove(_to(0, flipMovedCards: true), _board()), SoundCue.draw);
  });

  test('tableau and free-cell moves are place', () {
    expect(cueForMove(_to(3), _board()), SoundCue.place);
    expect(cueForMove(_to(4), _board()), SoundCue.place);
  });
}
