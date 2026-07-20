import 'dart:math';

import 'package:fluid_grid/src/drag/insertion_resolver.dart';
import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The original, obviously-correct O(n^2) resolver: for every candidate slot it
/// solves the whole grid on that hypothetical ordering and measures where the
/// dragged item lands. The optimized [resolveInsertion] must agree with it on
/// every input.
InsertionCandidate? bruteForceResolve({
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
          leadingCells: chromeById[order.id]?.leadingCells ?? 0,
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

      final rect = computeMasonryLayout(
        specFor(hypothetical),
      ).itemRects[draggedId];
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

  if (current != null && currentDistance.isFinite && currentDistance - bestDistance <= hysteresis) {
    return current;
  }
  return best;
}

void main() {
  test(
    'optimized resolveInsertion matches the brute-force solver on random inputs',
    () {
      final random = Random(20260713);
      var draggedId = 0;

      for (var trial = 0; trial < 4000; trial++) {
        final sectionCount = 1 + random.nextInt(4);
        final heights = <Object, double>{};
        final sections = <SectionOrder>[];
        final chrome = <SectionChrome>[];

        var nextItem = 0;
        for (var s = 0; s < sectionCount; s++) {
          final itemCount = random.nextInt(9); // 0..8, including empty sections
          final itemIds = <Object>[];
          for (var i = 0; i < itemCount; i++) {
            final id = 'i${nextItem++}';
            itemIds.add(id);
            heights[id] = 10.0 + random.nextInt(120);
          }
          final sectionId = 's$s';
          sections.add(SectionOrder(id: sectionId, itemIds: itemIds));
          chrome.add(
            SectionChrome(
              id: sectionId,
              headerHeight: random.nextBool() ? random.nextInt(60).toDouble() : 0,
              footerHeight: random.nextBool() ? random.nextInt(40).toDouble() : 0,
              emptyExtent: random.nextInt(80).toDouble(),
              // Half the trials rest on a re-anchored (offset) layout; values
              // beyond crossAxisCount exercise normalization.
              leadingCells: random.nextBool() ? random.nextInt(6) : 0,
            ),
          );
        }

        // The dragged item has a fresh id not present in any section.
        final dragged = 'x${draggedId++}';
        heights[dragged] = 10.0 + random.nextInt(120);

        final template = GridLayoutSpec(
          width: 120.0 + random.nextInt(400),
          sections: const [],
          crossAxisCount: 1 + random.nextInt(4),
          crossAxisSpacing: random.nextInt(16).toDouble(),
          mainAxisSpacing: random.nextInt(16).toDouble(),
          padding: EdgeInsets.only(
            left: random.nextInt(24).toDouble(),
            right: random.nextInt(24).toDouble(),
            top: random.nextInt(24).toDouble(),
          ),
          textDirection: random.nextBool() ? TextDirection.ltr : TextDirection.rtl,
        );

        final draggedTopLeft = Offset(
          (random.nextDouble() - 0.1) * template.width,
          random.nextDouble() * 1200,
        );

        // Exercise the hysteresis path on ~half the trials with a random current.
        InsertionCandidate? current;
        if (random.nextBool()) {
          final s = random.nextInt(sectionCount);
          current = InsertionCandidate(
            sectionId: 's$s',
            index: random.nextInt(sections[s].itemIds.length + 1),
          );
        }

        final expected = bruteForceResolve(
          sections: sections,
          chrome: chrome,
          heights: heights,
          draggedId: dragged,
          draggedTopLeft: draggedTopLeft,
          template: template,
          current: current,
        );
        final actual = resolveInsertion(
          sections: sections,
          chrome: chrome,
          heights: heights,
          draggedId: dragged,
          draggedTopLeft: draggedTopLeft,
          template: template,
          current: current,
        );

        expect(
          actual,
          expected,
          reason:
              'trial $trial: sections=${sections.map((s) => s.itemIds.length).toList()} '
              'count=${template.crossAxisCount} rtl=${template.textDirection == TextDirection.rtl} '
              'current=$current',
        );
      }
    },
  );
}
