import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  final ActiveDrag _activeDrag = ActiveDrag();

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
  final ActiveDrag activeDrag;

  /// The notifier for the nearest scope, or `null` when there is none (e.g. a
  /// [CardView] used outside a board). The notifier identity is stable, so this
  /// intentionally does not register a rebuild dependency — callers listen via
  /// [ValueListenableBuilder] instead.
  static ActiveDrag? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<DragScope>()?.activeDrag;
  }

  @override
  bool updateShouldNotify(DragScope oldWidget) =>
      oldWidget.activeDrag != activeDrag;
}

/// The board's single in-flight card drag: the [CardDragData] a [CardView]
/// claimed when its drag started, or `null` when the board is idle.
class ActiveDrag extends ValueNotifier<CardDragData?> {
  ActiveDrag() : super(null);

  bool _disposed = false;

  /// Clears [claim] if it is still the active drag. For a dragged card torn
  /// down mid-drag (the board changed under the finger): Flutter never reports
  /// `onDragEnd` to an unmounted `Draggable`, so without this the board would
  /// stay locked to a drag that no longer exists. Deferred to after the frame
  /// (it is called from `dispose`, while the tree is locked) and a no-op once
  /// the scope itself is gone.
  void releaseOrphan(CardDragData claim) {
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      if (!_disposed && identical(value, claim)) {
        value = null;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
