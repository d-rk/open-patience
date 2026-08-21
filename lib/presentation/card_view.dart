import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../core/card.dart';
import '../ui/theme/game_fonts.dart';
import '../ui/theme/game_motion.dart';
import '../ui/theme/game_palette.dart';
import 'card_back_pattern.dart';
import 'drag_scope.dart';

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
      final ValueNotifier<CardDragData?>? activeDrag = DragScope.maybeOf(
        context,
      );
      if (activeDrag == null) {
        return _draggable(stack, child, null);
      }
      return ValueListenableBuilder<CardDragData?>(
        valueListenable: activeDrag,
        builder: (BuildContext context, CardDragData? active, _) =>
            _draggable(stack, child, activeDrag, active),
      );
    }
    return child;
  }

  /// Builds the draggable card, coordinating with the board's [activeDrag] so
  /// only one drag runs at a time and the whole moving stack lifts away
  /// cleanly, leaving no ghost behind in the pile.
  Widget _draggable(
    List<Card> stack,
    Widget child,
    ValueNotifier<CardDragData?>? activeDrag, [
    CardDragData? active,
  ]) {
    // While dragging, the moving cards ride in the floating feedback and leave
    // no ghost behind — the source slot is simply empty. A same-size, invisible
    // box keeps the pile's layout footprint unchanged.
    final Widget placeholder = SizedBox.fromSize(size: size);

    if (active != null && active.fromPile == dragData!.fromPile) {
      // A card in this same pile is being dragged. Everything from the grabbed
      // card down rides along, so it becomes an inert, empty placeholder; the
      // grabbed card itself is handled by its own `childWhenDragging` below.
      if (dragData!.cardIndex > active.cardIndex) {
        return IgnorePointer(child: placeholder);
      }
    }

    // A different card is mid-drag: lock this one so a second finger can't
    // start a concurrent drag.
    final bool locked =
        active != null &&
        !(active.fromPile == dragData!.fromPile &&
            active.cardIndex == dragData!.cardIndex);

    return Draggable<CardDragData>(
      data: dragData,
      maxSimultaneousDrags: locked ? 0 : 1,
      // Center the grabbed card on the finger. Flutter always hit-tests drop
      // targets at the pointer, so pinning the card's center there makes drops
      // land where the card *looks* like it is — far more forgiving than
      // aiming with a finger that leads the card by wherever it was grabbed.
      dragAnchorStrategy:
          (
            Draggable<Object> draggable,
            BuildContext context,
            Offset position,
          ) => Offset(size.width / 2, size.height / 2),
      feedback: _DragFeedback(cards: stack, size: size),
      childWhenDragging: placeholder,
      onDragStarted: () => activeDrag?.value = dragData,
      onDragEnd: (_) => activeDrag?.value = null,
      child: locked ? IgnorePointer(child: child) : child,
    );
  }
}

/// Wraps a card's whole widget subtree ([child]) and runs a short Y-axis flip
/// whenever the card's `faceUp` changes. It is placed at a `faceUp`-invariant
/// position — the immediate child of the board's per-card `AnimatedPositioned`
/// (keyed by the physical card) — so it *persists* across the
/// [CardFace]↔[CardView] swap that a draw or tableau reveal triggers, and can
/// therefore see the orientation change in `didUpdateWidget` and animate it.
///
/// During the first half of the turn (angle `0 → π/2`) it shows the *prior*
/// face — reconstructed as a [CardFace] from the cached previous [card] — and
/// at the edge-on midpoint swaps to [child] (the new face), which completes the
/// turn `−π/2 → 0`. At rest the wrapping [Transform] is the identity, so it
/// never disturbs hit-testing, taps or drag feedback (flips only happen on a
/// draw / reveal, never mid-drag). Honors the OS reduce-motion setting via
/// [GameMotion.resolve]: a zero duration snaps straight to the new face with no
/// rotation and no stuck frame.
class CardFlip extends StatefulWidget {
  const CardFlip({
    required Key key,
    required this.card,
    required this.size,
    required this.child,
  }) : super(key: key);

  final Card card;
  final Size size;
  final Widget child;

  @override
  State<CardFlip> createState() => _CardFlipState();
}

class _CardFlipState extends State<CardFlip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The card as it was before the in-progress flip started, used to paint the
  /// outgoing face during the first half of the turn. Null when not flipping.
  Card? _fromCard;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant CardFlip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.card.faceUp != oldWidget.card.faceUp) {
      _fromCard = oldWidget.card;
      _controller.duration = GameMotion.resolve(
        GameMotion.flip,
        reduceMotion: MediaQuery.of(context).disableAnimations,
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final Card? fromCard = _fromCard;
        double angle = 0;
        Widget shown = child!;
        if (_controller.isAnimating && fromCard != null) {
          final double t = GameMotion.flipCurve.transform(_controller.value);
          if (t < 0.5) {
            // Outgoing (prior) face turning away: 0 → π/2.
            angle = t * math.pi;
            shown = CardFace(card: fromCard, size: widget.size);
          } else {
            // Incoming (new) face completing the turn: −π/2 → 0.
            angle = (t - 1) * math.pi;
          }
        }
        return Transform(
          key: const Key('cardFlip'),
          alignment: Alignment.center,
          transform: Matrix4.rotationY(angle),
          child: shown,
        );
      },
    );
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
    final double radius = size.width * 0.12;
    if (!card.faceUp) {
      final double innerInset = size.width * 0.05;
      final double patternInset = size.width * 0.085;
      return Semantics(
        label: _semanticLabel,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: GamePalette.gold, width: 2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                GamePalette.feltGreenDark,
                GamePalette.feltGreenMid,
              ],
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Colors.black26,
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Thin inner gold hairline; the gradient shows through the band
              // between it and the outer border.
              Padding(
                padding: EdgeInsets.all(innerInset),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius - innerInset),
                    border: Border.all(
                      color: GamePalette.gold.withValues(alpha: 0.55),
                      width: 1,
                    ),
                  ),
                ),
              ),
              // Fine diamond-and-pip texture, kept strictly inside the inner
              // hairline and clipped to the rounded corners.
              Padding(
                padding: EdgeInsets.all(patternInset),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius - patternInset),
                  child: CardBackPattern(
                    size: Size(
                      size.width - 2 * patternInset,
                      size.height - 2 * patternInset,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final Color color = card.isRed ? GamePalette.cardRed : GamePalette.cardInk;
    final String label = _rankLabels[card.rank];
    final String glyph = _suitGlyphs[card.suit]!;

    final Widget index = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontFamily: GameFonts.card,
            color: color,
            fontSize: size.width * 0.28,
            fontWeight: FontWeight.w700,
            height: 0.9,
          ),
        ),
        Text(
          glyph,
          style: TextStyle(
            color: color,
            fontSize: size.width * 0.22,
            height: 0.9,
          ),
        ),
      ],
    );

    return Semantics(
      label: _semanticLabel,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: GamePalette.cardFace,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: <Widget>[
            // Faint center pip.
            Center(
              child: Text(
                glyph,
                style: TextStyle(
                  color: color.withValues(alpha: 0.14),
                  fontSize: size.width * 0.7,
                ),
              ),
            ),
            Positioned(
              top: size.width * 0.08,
              left: size.width * 0.1,
              child: index,
            ),
            // Mirrored bottom-right index.
            Positioned(
              bottom: size.width * 0.08,
              right: size.width * 0.1,
              child: Transform.rotate(angle: 3.14159, child: index),
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
