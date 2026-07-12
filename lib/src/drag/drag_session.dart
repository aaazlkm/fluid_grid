import 'dart:ui' show Offset, VoidCallback;

import 'package:fluid_grid/src/drag/insertion_resolver.dart';
import 'package:flutter/gestures.dart';

enum DragPhase {
  /// The pointer is down and the item tracks it.
  dragging,

  /// The pointer is up and the item springs into its slot. The working order is
  /// frozen so the grid does not flicker before the parent echoes the new data.
  settling,
}

/// Everything known about the drag in flight.
class DragSession<T> {
  DragSession({
    required this.id,
    required this.item,
    required this.fromSectionId,
    required this.fromIndex,
    required this.grabOffset,
    required this.pointer,
    required this.contentWidth,
    required this.crossAxisCount,
    required this.hypothesis,
  });

  final Object id;
  final T item;
  final Object fromSectionId;
  final int fromIndex;

  /// Pointer position minus the item's top-left, captured at lift and held
  /// constant so the item stays put under the finger.
  final Offset grabOffset;

  /// Content width at lift. A change means the grid was resized and all cached
  /// geometry is stale.
  final double contentWidth;

  /// Column count at lift. Content width alone is count-independent, so a column
  /// change (e.g. a zoom while dragging) would slip past the width check.
  final int crossAxisCount;

  Offset pointer;
  InsertionCandidate hypothesis;
  DragPhase phase = DragPhase.dragging;

  bool get isActive => phase == DragPhase.dragging;
}

/// Bridges the gesture recognizer's [Drag] contract to plain callbacks.
class GridDrag extends Drag {
  GridDrag({required this.onUpdate, required this.onEnd, required this.onCancel});

  final void Function(Offset globalPosition) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.globalPosition);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onCancel();
}
