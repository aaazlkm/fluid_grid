import 'dart:math' as math;

import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_sliver_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Intrinsic height of item [i] — varied so measured mode has real work to do,
/// and clearly taller than the 200px column width so the square estimate is
/// visibly wrong until content is measured.
double _heightOf(int i) => 250 + (i % 4) * 50;

/// A grid of [count] variable-height items in one section. [measured] switches
/// between the measured strategy and an exact builder that returns [_heightOf].
Widget _harness({
  required int count,
  required bool measured,
  double viewportHeight = 600,
  int crossAxisCount = 2,
  Set<int>? built,
  ScrollController? controller,
  bool reorderEnabled = false,
  GridZoomConfig? zoomConfig,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(400, 600)),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: viewportHeight,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverFluidGrid<int>(
              sections: [
                GridSection<int>(
                  id: 's',
                  items: List.generate(count, (i) => i),
                ),
              ],
              idOf: (i) => i,
              crossAxisCount: crossAxisCount,
              reorderEnabled: reorderEnabled,
              zoomConfig: zoomConfig,
              itemHeight: measured
                  ? const GridItemHeight.measured()
                  : GridItemHeight.builder((i, _) => _heightOf(i)),
              itemBuilder: (context, i) {
                built?.add(i);
                return SizedBox(height: _heightOf(i), child: Text('item $i'));
              },
            ),
          ],
        ),
      ),
    ),
  ),
);

RenderSliverFluidGrid _renderObject(WidgetTester tester) => tester
    .renderObject<RenderSliverFluidGrid>(find.byType(SliverMasonryGridBody));

double _maxExtent(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable))
    .position
    .maxScrollExtent;

void main() {
  testWidgets('builds only items near the viewport, not all of them', (
    tester,
  ) async {
    final built = <int>{};
    await tester.pumpWidget(_harness(count: 400, measured: true, built: built));
    await tester.pump();

    expect(built.length, lessThan(100));
    expect(built, contains(0));
    expect(
      built.contains(399),
      isFalse,
      reason: 'the far item must never be built',
    );
    expect(_renderObject(tester).debugMaterialisedKeys.length, lessThan(100));
  });

  testWidgets(
    'scroll extent self-corrects from the estimate toward the true height',
    (tester) async {
      // Reference: the exact-mode extent for the same content and viewport.
      await tester.pumpWidget(_harness(count: 200, measured: false));
      await tester.pump();
      final reference = _maxExtent(tester);

      final controller = ScrollController();
      await tester.pumpWidget(
        _harness(count: 200, measured: true, controller: controller),
      );
      await tester.pump();
      final initial = _maxExtent(tester);

      // The first frame estimates unmeasured items as squares (200px), well below
      // their true ~325px average, so the extent starts too small.
      expect(
        (initial - reference).abs(),
        greaterThan(200),
        reason: 'estimate is visibly off at first',
      );

      // Walk the whole list through the viewport so every row gets measured.
      for (var y = 0.0; y <= _maxExtent(tester); y += 200) {
        controller.jumpTo(math.min(y, _maxExtent(tester)));
        await tester.pump();
      }
      controller.jumpTo(_maxExtent(tester));
      await tester.pumpAndSettle();

      expect(
        _maxExtent(tester),
        closeTo(reference, 2),
        reason: 'once every item is measured the extent is exact',
      );
    },
  );

  testWidgets('visible item rects match the exact-mode layout after measuring', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      _harness(count: 60, measured: true, controller: controller),
    );
    await tester.pump();

    // Scroll through everything so all heights are measured, then back to top.
    for (var y = 0.0; y <= _maxExtent(tester); y += 200) {
      controller.jumpTo(math.min(y, _maxExtent(tester)));
      await tester.pump();
    }
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    final measuredRect = tester.getRect(find.text('item 3'));

    // Same content, exact mode.
    await tester.pumpWidget(
      _harness(count: 60, measured: false, controller: controller),
    );
    await tester.pumpAndSettle();
    final exactRect = tester.getRect(find.text('item 3'));

    expect(measuredRect.top, closeTo(exactRect.top, 0.5));
    expect(measuredRect.left, closeTo(exactRect.left, 0.5));
  });

  testWidgets('a plain scroll frame settles the measure loop in a few passes', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      _harness(count: 300, measured: true, controller: controller),
    );
    await tester.pump();

    controller.jumpTo(1200);
    await tester.pump();

    expect(_renderObject(tester).debugLastMeasurePasses, lessThanOrEqualTo(3));
  });

  testWidgets('reorder works in measured mode', (tester) async {
    GridReorderResult<int>? result;
    final controller = ScrollController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 600)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 600,
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  SliverFluidGrid<int>(
                    sections: const [
                      GridSection<int>(id: 's', items: [0, 1, 2, 3]),
                    ],
                    idOf: (i) => i,
                    dragStartDelay: const Duration(milliseconds: 300),
                    itemHeight: const GridItemHeight.measured(),
                    onReorderFinished: (r) => result = r,
                    itemBuilder: (context, i) =>
                        SizedBox(height: 120, child: Text('item $i')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('item 0')),
    );
    await tester.pump(const Duration(milliseconds: 350));
    final to = tester.getCenter(find.text('item 3'));
    final from = tester.getCenter(find.text('item 0'));
    final delta = to - from;
    for (var step = 1; step <= 5; step++) {
      await gesture.moveTo(from + delta * (step / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.item, 0);
    expect(result!.toIndex, greaterThan(0));
  });

  for (final style in GridZoomStyle.values) {
    testWidgets(
      'pinch morph runs without error in measured mode (${style.name})',
      (tester) async {
        int? newCount;
        final controller = ScrollController();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(400, 600)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  height: 600,
                  child: CustomScrollView(
                    controller: controller,
                    slivers: [
                      SliverFluidGrid<int>(
                        sections: [
                          GridSection<int>(
                            id: 's',
                            items: List.generate(16, (i) => i),
                          ),
                        ],
                        idOf: (i) => i,
                        crossAxisCount: 2,
                        reorderEnabled: false,
                        zoomConfig: GridZoomConfig(
                          minCrossAxisCount: 1,
                          maxCrossAxisCount: 4,
                          style: style,
                        ),
                        onCrossAxisCountChanged: (c) => newCount = c,
                        itemHeight: const GridItemHeight.measured(),
                        itemBuilder: (context, i) =>
                            SizedBox(height: 120, child: Text('item $i')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final center = tester.getCenter(find.byType(CustomScrollView));
        final g1 = await tester.startGesture(center - const Offset(20, 0));
        final g2 = await tester.startGesture(center + const Offset(20, 0));
        await tester.pump();
        for (var step = 1; step <= 6; step++) {
          await g1.moveBy(const Offset(-14, 0));
          await g2.moveBy(const Offset(14, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g1.up();
        await g2.up();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          newCount,
          lessThan(2),
          reason: 'spreading fingers zooms out to fewer columns',
        );
      },
    );
  }
}
