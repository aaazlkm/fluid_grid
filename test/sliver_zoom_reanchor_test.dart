import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_sliver_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sliver-side coverage of iOS-style cell re-anchoring: a pinch commits a
/// persistent leading-cell offset, and the lazy machinery (materialisation,
/// measured mode) keeps working on the shifted grid.
///
/// Geometry: width 400, zero spacing/padding, fixed 100-high tiles, levels
/// [3, 4, 5] starting at 4 (column width 100 → 133.33 at 3 columns).
class _Harness extends StatefulWidget {
  const _Harness({
    this.itemCount = 24,
    this.measured = false,
    this.controller,
  });

  final int itemCount;
  final bool measured;
  final ScrollController? controller;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _count = 4;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 600)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 600,
          child: CustomScrollView(
            controller: widget.controller,
            slivers: [
              SliverFluidGrid<int>(
                crossAxisCount: _count,
                reorderEnabled: false,
                zoomConfig: const GridZoomConfig(
                  style: GridZoomStyle.photos,
                  zoomLevels: [3, 4, 5],
                ),
                idOf: (i) => i,
                onCrossAxisCountChanged: (count) =>
                    setState(() => _count = count),
                sections: [
                  GridSection(
                    id: 's',
                    items: List.generate(widget.itemCount, (i) => i),
                  ),
                ],
                itemHeight: widget.measured
                    ? const GridItemHeight.measured()
                    : GridItemHeight.builder((_, _) => 100),
                itemBuilder: (context, i) =>
                    SizedBox(height: 100, child: Text('item $i')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

RenderSliverFluidGrid _grid(WidgetTester tester) => tester
    .renderObject<RenderSliverFluidGrid>(find.byType(SliverMasonryGridBody));

/// Pinch-spreads around [center] so the zoom crosses 4 → 3 columns. With
/// [driftTo], the recognizer is first warmed up with a symmetric
/// spread-and-return (so the anchor is captured at [center], not mid-drift)
/// and the focal then slides to [driftTo] over the first 60% of the steps
/// while the morph is in flight.
Future<void> _pinchTo3Columns(
  WidgetTester tester, {
  required Offset center,
  Offset? driftTo,
}) async {
  final g1 = await tester.startGesture(
    center - const Offset(30, 0),
    pointer: 7,
  );
  final g2 = await tester.startGesture(
    center + const Offset(30, 0),
    pointer: 8,
  );
  if (driftTo != null) {
    for (final separation in [80.0, 100.0, 80.0, 60.0]) {
      await g1.moveTo(center - Offset(separation / 2, 0));
      await g2.moveTo(center + Offset(separation / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  final steps = driftTo == null ? 8 : 10;
  for (var step = 1; step <= steps; step++) {
    final to = driftTo == null ? 160.0 : 78.0;
    final separation = 60 + (to - 60) * step / steps;
    final focal = driftTo == null
        ? center
        : Offset.lerp(center, driftTo, (step / (steps * 0.6)).clamp(0.0, 1.0))!;
    await g1.moveTo(focal - Offset(separation / 2, 0));
    await g2.moveTo(focal + Offset(separation / 2, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a sliver pinch commits a persistent offset: the resting grid is the '
    'canonical layout shifted by whole cells, leading cells blank',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      // Grab item 3 (right edge at 4 columns, canonical column 0 at 3).
      await _pinchTo3Columns(tester, center: const Offset(350, 50));

      final crossfade = _grid(tester).debugCrossfade;
      expect(crossfade.t, 0);
      final offset = crossfade.lowOffsets['s'];
      expect(offset, isNotNull);
      expect(offset, isNot(0));

      // Every visible tile rests at canonical cell i + offset — item 0 has
      // moved off column 0, leaving the leading cells blank. Rows are read
      // through the viewport: the y-pinning may have scrolled during the
      // pinch, but the whole grid stays cell-aligned.
      const stride = 400 / 3;
      final scrolled = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      for (var i = 0; i < 9; i++) {
        final cell = i + offset!;
        final topLeft = tester.getTopLeft(find.text('item $i'));
        expect(
          topLeft.dx,
          moreOrLessEquals((cell % 3) * stride, epsilon: 0.5),
          reason: 'item $i rests in column ${cell % 3}',
        );
        expect(
          topLeft.dy,
          moreOrLessEquals((cell ~/ 3) * 100.0 - scrolled, epsilon: 0.5),
          reason: 'item $i rests in row ${cell ~/ 3}',
        );
      }
    },
  );

  testWidgets(
    'laziness survives the offset: the trailing wrap-row materialises at its '
    'shifted cell and no phantom children appear',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_Harness(itemCount: 90, controller: controller));
      await tester.pumpAndSettle();

      await _pinchTo3Columns(tester, center: const Offset(350, 50));
      final offset = _grid(tester).debugCrossfade.lowOffsets['s'];
      expect(offset, isNot(0));

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      // The last item sits in the trailing partial row created by the shift.
      final cell = 89 + offset!;
      const stride = 400 / 3;
      final topLeft = tester.getTopLeft(find.text('item 89'));
      expect(topLeft.dx, moreOrLessEquals((cell % 3) * stride, epsilon: 0.5));

      // Lazy: the top of the grid is not built at the bottom, and every
      // materialised child corresponds to a real item.
      expect(find.text('item 0'), findsNothing);
      final itemKeys = _grid(
        tester,
      ).debugMaterialisedKeys.where((key) => key.kind == FluidChildKind.item);
      for (final key in itemKeys) {
        expect(key.id, isA<int>());
        expect(key.id as int, inInclusiveRange(0, 89));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a sliver drift leaves the tile in its entry cell (no live re-flow)',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      // Grab item 3 at (350, 50), slide the fingers to (150, 50) mid-morph.
      // The entry cell is fixed at the grab, so the resting grid does NOT
      // re-flow to follow the fingers — the grid never slides sideways.
      await _pinchTo3Columns(
        tester,
        center: const Offset(350, 50),
        driftTo: const Offset(150, 50),
      );

      final crossfade = _grid(tester).debugCrossfade;
      expect(crossfade.low, 3);
      expect(crossfade.t, 0);
      const stride = 400 / 3;
      final left = tester.getTopLeft(find.text('item 3')).dx;
      // Rests under the INITIAL fingers (350), not the drift target (150).
      expect(left - 1, lessThanOrEqualTo(350));
      expect(left + stride + 1, greaterThanOrEqualTo(350));
      expect(
        left <= 150 && 150 <= left + stride,
        isFalse,
        reason: 'the tile did not follow the fingers to the drift target',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a measured-mode drift still converges in a few measure passes',
    (tester) async {
      await tester.pumpWidget(const _Harness(measured: true));
      await tester.pumpAndSettle();

      await _pinchTo3Columns(
        tester,
        center: const Offset(350, 50),
        driftTo: const Offset(150, 50),
      );

      final grid = _grid(tester);
      expect(grid.debugCrossfade.t, 0);
      expect(grid.debugLastMeasurePasses, lessThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'measured mode converges on an offset grid in a few measure passes',
    (tester) async {
      await tester.pumpWidget(const _Harness(measured: true));
      await tester.pumpAndSettle();

      await _pinchTo3Columns(tester, center: const Offset(350, 50));

      final grid = _grid(tester);
      expect(grid.debugCrossfade.t, 0);
      expect(grid.debugCrossfade.lowOffsets['s'], isNot(0));
      expect(
        grid.debugLastMeasurePasses,
        lessThanOrEqualTo(3),
        reason: 'the measure → re-solve loop still reaches a fixpoint',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
