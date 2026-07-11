import 'package:flutter/foundation.dart';

/// The items of one section after a reorder, in their new display order.
@immutable
class GridSectionItems<T> {
  const GridSectionItems({required this.sectionId, required this.items});

  final Object sectionId;
  final List<T> items;
}

/// Describes a completed drag: which item moved, where it came from, where it
/// landed, and the resulting ordering of every section.
@immutable
class GridReorderResult<T> {
  const GridReorderResult({
    required this.item,
    required this.fromSectionId,
    required this.fromIndex,
    required this.toSectionId,
    required this.toIndex,
    required this.sections,
  });

  final T item;

  final Object fromSectionId;
  final int fromIndex;

  final Object toSectionId;
  final int toIndex;

  /// Every section in its original order, carrying its post-drop item list.
  final List<GridSectionItems<T>> sections;

  /// Whether the item landed in a different section than it started in.
  bool get movedAcrossSections => fromSectionId != toSectionId;

  /// The post-drop items of [sectionId], or an empty list if unknown.
  List<T> itemsOf(Object sectionId) {
    for (final section in sections) {
      if (section.sectionId == sectionId) return section.items;
    }
    return const [];
  }
}
