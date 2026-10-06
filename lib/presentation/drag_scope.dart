import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'card_view.dart';

/// Shares the single in-flight card drag across the whole board so cards can
/// coordinate: the moving stack dims itself and, while a drag is active, no
/// other card may start a second (multi-touch) drag. Owns the notifier and
/// exposes it to descendants via an [InheritedWidget].
class DragScopeHost extends StatefulWidget {
  const DragScopeHost({required this.child, super.key});

  final Widget child;

  @override
  State<DragScopeHost> createState() => _DragScopeHostState();
}

class _DragScopeHostState extends State<DragScopeHost> {
  final ValueNotifier<CardDragData?> _activeDrag = ValueNotifier<CardDragData?>(
    null,
  );

  @override
  void dispose() {
    _activeDrag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragScope(
      activeDrag: _activeDrag,
      begin: _begin,
      end: _end,
      child: widget.child,
    );
  }

  void _begin(CardDragData drag) {
    _activeDrag.value = drag;
  }

  /// Flutter reports a drag's end even after the dragged card has left the
  /// tree (see `Draggable.onDraggableCanceled`), so it can also arrive after
  /// this scope has gone — when there is no board left to unlock.
  void _end() {
    if (!mounted) {
      return;
    }
    _activeDrag.value = null;
  }
}

/// Exposes the board's active drag to [CardView]s below it.
class DragScope extends InheritedWidget {
  const DragScope({
    required this.activeDrag,
    required this.begin,
    required this.end,
    required super.child,
    super.key,
  });

  /// The card currently being dragged, or `null` when the board is idle.
  final ValueListenable<CardDragData?> activeDrag;

  /// Marks [CardDragData] as the board's one in-flight drag.
  final void Function(CardDragData drag) begin;

  /// Clears the in-flight drag. Must be driven by a drag-end signal Flutter
  /// guarantees even for a card removed mid-drag (`onDragCompleted` /
  /// `onDraggableCanceled`, not `onDragEnd`), or the board stays locked.
  final VoidCallback end;

  /// The nearest scope, or `null` when there is none (e.g. a [CardView] used
  /// outside a board). The notifier identity is stable, so this intentionally
  /// does not register a rebuild dependency — callers listen via
  /// [ValueListenableBuilder] instead.
  static DragScope? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<DragScope>();
  }

  @override
  bool updateShouldNotify(DragScope oldWidget) =>
      oldWidget.activeDrag != activeDrag;
}
