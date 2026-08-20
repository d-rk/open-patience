import 'package:flutter/material.dart' hide Card;

import '../core/card.dart';

/// The payload a dragged card carries: enough for a drop target to describe the
/// intended move (`from` pile + the index of the grabbed card) without the
/// widget ever deciding legality.
class CardDragData {
  const CardDragData({required this.fromPile, required this.cardIndex});

  final int fromPile;
  final int cardIndex;
}

/// A single, purely-presentational playing card. Renders [card]'s face (or back
/// when face down) and — when interactive props are supplied — forwards taps,
/// double-taps and drags as callbacks. It contains no rules: the parent turns
/// these callbacks into [GameEvent]s.
class CardView extends StatelessWidget {
  const CardView({
    required this.card,
    required this.size,
    this.dragData,
    this.dragStack,
    this.onTap,
    this.onDoubleTap,
    super.key,
  });

  static const double aspectRatio = 1.4;

  final Card card;
  final Size size;

  /// When non-null and [card] is face up, the card can be dragged.
  final CardDragData? dragData;

  /// The whole face-up group being dragged, for stacked drag feedback. Defaults
  /// to just this card.
  final List<Card>? dragStack;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final Widget face = CardFace(card: card, size: size);

    Widget child = face;
    if (onTap != null || onDoubleTap != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: child,
      );
    }

    if (card.faceUp && dragData != null) {
      final List<Card> stack = dragStack ?? <Card>[card];
      return Draggable<CardDragData>(
        data: dragData,
        dragAnchorStrategy: childDragAnchorStrategy,
        feedback: _DragFeedback(cards: stack, size: size),
        childWhenDragging: Opacity(opacity: 0.3, child: face),
        child: child,
      );
    }
    return child;
  }
}

/// The static visual of a card — a rounded rectangle with a rank and suit for a
/// face-up card, or a patterned back for a face-down one. `const`-friendly and
/// wrapped in [Semantics] so screen readers (and widget tests) can find it.
class CardFace extends StatelessWidget {
  const CardFace({required this.card, required this.size, super.key});

  final Card card;
  final Size size;

  static const List<String> _rankLabels = <String>[
    '',
    'A',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    'J',
    'Q',
    'K',
  ];

  static const Map<Suit, String> _suitGlyphs = <Suit, String>{
    Suit.clubs: '♣',
    Suit.diamonds: '♦',
    Suit.hearts: '♥',
    Suit.spades: '♠',
  };

  static const Map<Suit, String> _suitNames = <Suit, String>{
    Suit.clubs: 'clubs',
    Suit.diamonds: 'diamonds',
    Suit.hearts: 'hearts',
    Suit.spades: 'spades',
  };

  static const List<String> _rankNames = <String>[
    '',
    'ace',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'jack',
    'queen',
    'king',
  ];

  String get _semanticLabel => card.faceUp
      ? '${_rankNames[card.rank]} of ${_suitNames[card.suit]}'
      : 'face-down card';

  @override
  Widget build(BuildContext context) {
    final double radius = size.width * 0.1;
    if (!card.faceUp) {
      return Semantics(
        label: _semanticLabel,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: const Color(0xFF1B5E9B),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white70, width: 1.5),
          ),
          child: Center(
            child: Icon(
              Icons.pattern,
              size: size.width * 0.5,
              color: Colors.white24,
            ),
          ),
        ),
      );
    }

    final Color color = card.isRed
        ? const Color(0xFFC62828)
        : const Color(0xFF212121);
    final String label = _rankLabels[card.rank];
    final String glyph = _suitGlyphs[card.suit]!;

    return Semantics(
      label: _semanticLabel,
      child: Container(
        width: size.width,
        height: size.height,
        padding: EdgeInsets.all(size.width * 0.06),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0xFFBDBDBD)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$label$glyph',
              style: TextStyle(
                color: color,
                fontSize: size.width * 0.26,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  glyph,
                  style: TextStyle(color: color, fontSize: size.width * 0.44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.cards, required this.size});

  final List<Card> cards;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final double gap = size.height * 0.28;
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: size.width,
        height: size.height + gap * (cards.length - 1),
        child: Stack(
          children: <Widget>[
            for (int i = 0; i < cards.length; i++)
              Positioned(
                top: gap * i,
                child: CardFace(card: cards[i], size: size),
              ),
          ],
        ),
      ),
    );
  }
}
