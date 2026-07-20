import 'dart:ui' show Offset, TextDirection;

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
    this.leadingCells = 0,
  });

  final Object id;
  final double headerHeight;
  final double footerHeight;
  final double emptyExtent;

  /// The section's committed cell alignment (see
  /// `GridSectionSpec.leadingCells`), so drop candidates are evaluated against
  /// the same offset layout the grid is resting in.
  final int leadingCells;
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
/// slot is evaluated by where the dragged item would actually end up, and the
/// closest is chosen. Cross-section drops and empty sections need no special
/// case: an empty section simply contributes its single index-0 candidate.
///
/// The result is exact. Rather than re-solving the whole grid per candidate
/// (which is quadratic in the item count), it exploits masonry's forward
/// column scan: the dragged item's rect for candidate `(section, k)` depends
/// only on the column-bottom state after that section's first `k` base items —
/// the items after it, and every other section, leave the dragged rect
/// untouched. So each section is packed once, snapshotting the running column
/// state, and every candidate is then evaluated in `O(crossAxisCount)`. Total
/// cost is linear in the item count, so the grid stays responsive at thousands
/// of items.
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

  final count = template.crossAxisCount;
  final columnWidth = template.columnWidth;
  final spacing = template.mainAxisSpacing;
  final crossSpacing = template.crossAxisSpacing;
  final isRtl = template.textDirection == TextDirection.rtl;

  // Mirrors computeMasonryLayout's column x-origin, so candidate rects match the
  // real solver's placement exactly (including RTL).
  double xOf(int column) {
    final stride = columnWidth + crossSpacing;
    if (isRtl) return template.width - template.padding.right - columnWidth - column * stride;
    return template.padding.left + column * stride;
  }

  // The shortest column (ties to the lowest index), matching the solver.
  int shortestColumn(List<double> columnBottoms) {
    var column = 0;
    for (var c = 1; c < count; c++) {
      if (columnBottoms[c] < columnBottoms[column] - precisionErrorTolerance) column = c;
    }
    return column;
  }

  final draggedHeight = heights[draggedId] ?? 0;
  final draggedCentre = draggedTopLeft + Offset(columnWidth / 2, draggedHeight / 2);

  InsertionCandidate? best;
  var bestDistance = double.infinity;
  var currentDistance = double.infinity;

  var y = template.padding.top;
  for (final section in sections) {
    final sectionChrome = chromeById[section.id];
    final headerHeight = sectionChrome?.headerHeight ?? 0;
    final footerHeight = sectionChrome?.footerHeight ?? 0;
    final contentTop = y + headerHeight;

    // Absolute column bottoms, seeded a spacing above the content top so the
    // first item in each column lands exactly at contentTop.
    final columnBottoms = List<double>.filled(count, contentTop - spacing);

    // Committed cell alignment: block the leading columns exactly like the
    // solver (phantom copies of the section's first item). In the hypothetical
    // orderings, the first item is the dragged one when it drops at index 0 of
    // an empty section; otherwise it is the base first item. Either way the
    // dragged item's CANDIDATE rect is seed-height-independent (the blocked
    // bottoms always sit below the unblocked seeds), so one seeding serves the
    // whole prefix scan.
    final blocked = normalizeLeadingCells(
      sectionChrome?.leadingCells ?? 0,
      count,
    );
    if (blocked > 0) {
      final seedHeight = section.itemIds.isNotEmpty ? (heights[section.itemIds.first] ?? 0) : draggedHeight;
      for (var c = 0; c < blocked; c++) {
        columnBottoms[c] = contentTop + seedHeight;
      }
    }

    for (var index = 0; index <= section.itemIds.length; index++) {
      // Candidate: drop the dragged item into the current prefix state. In the
      // real solve, items after `index` are placed below it and never move it.
      final dropColumn = shortestColumn(columnBottoms);
      final top = columnBottoms[dropColumn] + spacing;
      final rectCentre = Offset(
        xOf(dropColumn) + columnWidth / 2,
        top + draggedHeight / 2,
      );
      final distance = (rectCentre - draggedCentre).distance;
      final candidate = InsertionCandidate(sectionId: section.id, index: index);

      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
      if (candidate == current) currentDistance = distance;

      // Advance the prefix state by this section's actual base item.
      if (index < section.itemIds.length) {
        final itemColumn = shortestColumn(columnBottoms);
        final itemTop = columnBottoms[itemColumn] + spacing;
        columnBottoms[itemColumn] = itemTop + (heights[section.itemIds[index]] ?? 0);
      }
    }

    // Advance past this section using its BASE layout (the dragged item is not
    // in it) so the next section's content top matches the real solve.
    final double contentBottom;
    if (section.itemIds.isEmpty) {
      contentBottom = contentTop + (sectionChrome?.emptyExtent ?? 0);
    } else {
      contentBottom = columnBottoms.reduce((a, b) => a > b ? a : b);
    }
    y = contentBottom + footerHeight;
  }

  // Hold the current slot until a challenger is meaningfully closer, so the
  // grid does not flap between two near-equidistant slots.
  if (current != null && currentDistance.isFinite && currentDistance - bestDistance <= hysteresis) {
    return current;
  }
  return best;
}
