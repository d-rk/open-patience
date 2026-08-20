import '../card.dart';

/// Shared stacking predicates used by every tableau-based variant. Extracted
/// only because the rule is genuinely identical across Klondike and FreeCell.

/// Whether [cards] (bottom-most of the group first) form a single face-up run
/// that descends by one rank each step and strictly alternates colour — the
/// classic tableau sequence. A single face-up card trivially qualifies.
bool isMovableSequence(List<Card> cards) {
  if (cards.isEmpty) {
    return false;
  }
  for (int i = 0; i < cards.length; i++) {
    if (!cards[i].faceUp) {
      return false;
    }
  }
  for (int i = 0; i < cards.length - 1; i++) {
    final Card lower = cards[i];
    final Card upper = cards[i + 1];
    if (lower.rank != upper.rank + 1 || lower.color == upper.color) {
      return false;
    }
  }
  return true;
}

/// Whether [moving] may land on tableau top card [onto]: opposite colour and
/// exactly one rank lower.
bool stacksOnTableau(Card moving, Card onto) {
  return moving.color != onto.color && onto.rank == moving.rank + 1;
}

/// Whether [card] may advance a foundation whose current top is [foundationTop]
/// (`null` when the foundation is empty — only an Ace may start it).
bool stacksOnFoundation(Card card, Card? foundationTop) {
  if (foundationTop == null) {
    return card.rank == aceRank;
  }
  return card.suit == foundationTop.suit && card.rank == foundationTop.rank + 1;
}
