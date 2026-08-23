import 'card.dart';
import 'game_rules.dart';
import 'game_state.dart';
import 'move.dart';
import 'pile.dart';

/// Greedily auto-finishes [state] under [rules]: repeatedly send any card whose
/// top is a legal foundation move to that foundation, cycling the stock (via
/// [GameRules.advanceStock]) when nothing else is playable, until the game is
/// won or progress stalls.
///
/// Returns the ordered list of moves that wins, or `null` if the board cannot
/// be trivially finished this way. Operates on a clone; [state] is not mutated.
/// The returned moves, applied in order to a board equal to [state], reproduce
/// the winning trajectory.
List<Move>? solveGreedy(GameState state, GameRules rules) {
  final GameState work = state.copy();
  final List<Move> solution = <Move>[];
  int cyclesSinceProgress = 0;
  // Secondary safety net against a logic error; a real solve is < 200 moves.
  const int hardCap = 100000;

  for (int ops = 0; ops < hardCap; ops++) {
    if (rules.isWon(work)) {
      return solution;
    }
    final Move? foundationMove = _nextFoundationMove(work, rules);
    if (foundationMove != null) {
      work.applyMove(foundationMove);
      solution.add(foundationMove);
      cyclesSinceProgress = 0;
      continue;
    }
    final Move? cycle = rules.advanceStock(work);
    if (cycle == null) {
      return null;
    }
    // A stock draw/recycle keeps the stock+waste total constant, so two full
    // passes over it with no foundation move means the loop is stuck.
    final int deckLeft = _stockPlusWaste(work);
    if (cyclesSinceProgress > 2 * deckLeft + 2) {
      return null;
    }
    work.applyMove(cycle);
    solution.add(cycle);
    cyclesSinceProgress++;
  }
  return null;
}

/// The first legal single-card move onto a foundation, scanning piles in
/// canonical order, or `null` if none exists.
Move? _nextFoundationMove(GameState state, GameRules rules) {
  for (int from = 0; from < state.piles.length; from++) {
    final Pile pile = state.pileAt(from);
    if (pile.isEmpty || pile.kind == PileKind.foundation) {
      continue;
    }
    for (final int to in rules.autoTargets(state, from)) {
      if (state.pileAt(to).kind == PileKind.foundation) {
        return Move(fromPile: from, toPile: to, cards: <Card>[pile.topCard!]);
      }
    }
  }
  return null;
}

int _stockPlusWaste(GameState state) {
  int total = 0;
  for (final Pile pile in state.piles) {
    if (pile.kind == PileKind.stock || pile.kind == PileKind.waste) {
      total += pile.length;
    }
  }
  return total;
}
