import 'dart:ui' show Offset;

import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:flutter/foundation.dart';

/// A section's item order, with the dragged item already removed.
@immutable
class SectionOrder {
  const SectionOrder({required this.id, required this.itemIds});

  final Object id;
  final List<Object> itemIds;
}

/// A section's non-item extents, needed to replay the solver faithfully.
@immutable
class SectionChrome {
  const SectionChrome({
    required this.id,
    this.headerHeight = 0,
    this.footerHeight = 0,
    this.emptyExtent = 0,
  });

  final Object id;
  final double headerHeight;
  final double footerHeight;
  final double emptyExtent;
}

/// A slot the dragged item could occupy.
@immutable
class InsertionCandidate {
  const InsertionCandidate({required this.sectionId, required this.index});

  final Object sectionId;
  final int index;

  @override
  bool operator ==(Object other) => other is InsertionCandidate && other.sectionId == sectionId && other.index == index;

  @override
  int get hashCode => Object.hash(sectionId, index);

  @override
  String toString() => 'InsertionCandidate($sectionId, $index)';
}

/// Finds the slot whose resulting position sits closest to where the dragged
/// item currently floats.
///
/// A masonry grid gives no usable inverse of position-to-index: inserting an
/// item at index `k` re-flows the column assignment of everything after it, so
/// "which card am I hovering, before or after its midpoint" produces slots that
/// do not match where the item would actually land. Instead every candidate
/// slot is evaluated by running the real solver on that hypothetical ordering
/// and measuring where the dragged item would end up. Cross-section drops and
/// empty sections need no special case: an empty section simply contributes its
/// single index-0 candidate.
///
/// With items in the tens this is a few thousand floating-point operations per
/// frame, and it is exact.
InsertionCandidate? resolveInsertion({
  required List<SectionOrder> sections,
  required List<SectionChrome> chrome,
  required Map<Object, double> heights,
  required Object draggedId,
  required Offset draggedTopLeft,
  required GridLayoutSpec template,
  InsertionCandidate? current,
  double hysteresis = 8,
}) {
  final chromeById = {for (final entry in chrome) entry.id: entry};

  GridLayoutSpec specFor(List<SectionOrder> orders) => GridLayoutSpec(
    width: template.width,
    crossAxisCount: template.crossAxisCount,
    crossAxisSpacing: template.crossAxisSpacing,
    mainAxisSpacing: template.mainAxisSpacing,
    padding: template.padding,
    textDirection: template.textDirection,
    sections: [
      for (final order in orders)
        GridSectionSpec(
          id: order.id,
          items: [
            for (final itemId in order.itemIds) GridItemSpec(id: itemId, height: heights[itemId] ?? 0),
          ],
          headerHeight: chromeById[order.id]?.headerHeight ?? 0,
          footerHeight: chromeById[order.id]?.footerHeight ?? 0,
          emptyExtent: order.itemIds.isEmpty ? (chromeById[order.id]?.emptyExtent ?? 0) : 0,
        ),
    ],
  );

  final draggedHeight = heights[draggedId] ?? 0;
  final draggedCentre = draggedTopLeft + Offset(template.columnWidth / 2, draggedHeight / 2);

  InsertionCandidate? best;
  var bestDistance = double.infinity;
  var currentDistance = double.infinity;

  for (final section in sections) {
    for (var index = 0; index <= section.itemIds.length; index++) {
      final hypothetical = [
        for (final other in sections)
          SectionOrder(
            id: other.id,
            itemIds: other.id == section.id ? ([...other.itemIds]..insert(index, draggedId)) : other.itemIds,
          ),
      ];

      final rect = computeMasonryLayout(specFor(hypothetical)).itemRects[draggedId];
      if (rect == null) continue;

      final distance = (rect.center - draggedCentre).distance;
      final candidate = InsertionCandidate(sectionId: section.id, index: index);

      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
      if (candidate == current) currentDistance = distance;
    }
  }

  // Hold the current slot until a challenger is meaningfully closer, so the
  // grid does not flap between two near-equidistant slots.
  if (current != null && currentDistance.isFinite && currentDistance - bestDistance <= hysteresis) {
    return current;
  }
  return best;
}
