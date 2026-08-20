import 'package:equatable/equatable.dart';

/// The four French-deck suits.
enum Suit { clubs, diamonds, hearts, spades }

/// The two suit colours. Alternating colour is a core solitaire stacking rule.
enum SuitColor { red, black }

/// The lowest rank (Ace).
const int aceRank = 1;

/// The highest rank (King).
const int kingRank = 13;

/// An immutable playing card: a [suit], an integer [rank] in `1..13`
/// (Ace = 1, King = 13), and whether it is currently [faceUp].
///
/// Value object with structural equality via [Equatable] so that two cards
/// with the same suit, rank and orientation are considered equal — this is
/// what lets undo tests assert an exact prior snapshot.
class Card extends Equatable {
  const Card({required this.suit, required this.rank, this.faceUp = false})
    : assert(rank >= aceRank && rank <= kingRank, 'rank must be 1..13');

  factory Card.fromJson(Map<String, dynamic> json) {
    return Card(
      suit: Suit.values[json['s'] as int],
      rank: json['r'] as int,
      faceUp: json['u'] as bool,
    );
  }

  final Suit suit;
  final int rank;
  final bool faceUp;

  /// The colour of this card, derived from its [suit].
  SuitColor get color => (suit == Suit.hearts || suit == Suit.diamonds)
      ? SuitColor.red
      : SuitColor.black;

  /// Whether this card is a red suit (hearts or diamonds).
  bool get isRed => color == SuitColor.red;

  /// Whether this card is a black suit (clubs or spades).
  bool get isBlack => color == SuitColor.black;

  /// A copy of this card turned face up.
  Card get faceUpCard => faceUp ? this : copyWith(faceUp: true);

  /// A copy of this card turned face down.
  Card get faceDownCard => faceUp ? copyWith(faceUp: false) : this;

  Card copyWith({Suit? suit, int? rank, bool? faceUp}) {
    return Card(
      suit: suit ?? this.suit,
      rank: rank ?? this.rank,
      faceUp: faceUp ?? this.faceUp,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    's': suit.index,
    'r': rank,
    'u': faceUp,
  };

  @override
  List<Object?> get props => <Object?>[suit, rank, faceUp];

  @override
  bool get stringify => true;
}
