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
    return DragScope(activeDrag: _activeDrag, child: widget.child);
  }
}

/// Exposes the board's active-drag notifier to [CardView]s below it.
class DragScope extends InheritedWidget {
  const DragScope({required this.activeDrag, required super.child, super.key});

  /// The card currently being dragged, or `null` when the board is idle.
  final ValueNotifier<CardDragData?> activeDrag;

  /// The notifier for the nearest scope, or `null` when there is none (e.g. a
  /// [CardView] used outside a board). The notifier identity is stable, so this
  /// intentionally does not register a rebuild dependency — callers listen via
  /// [ValueListenableBuilder] instead.
  static ValueNotifier<CardDragData?>? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<DragScope>()?.activeDrag;
  }

  @override
  bool updateShouldNotify(DragScope oldWidget) =>
      oldWidget.activeDrag != activeDrag;
}
