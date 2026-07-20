import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/layout/render_sliver_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _levels = [2, 6];

class _Harness extends StatefulWidget {
  const _Harness({this.onCountChanged});

  final ValueChanged<int>? onCountChanged;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _count = 6;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverFluidGrid<int>(
            crossAxisCount: _count,
            reorderEnabled: false,
            zoomConfig: const GridZoomConfig(
              zoomLevels: _levels,
              style: GridZoomStyle.photos,
            ),
            idOf: (i) => i,
            sections: [
              GridSection(id: 's', items: List.generate(120, (i) => i)),
            ],
            onCrossAxisCountChanged: (count) {
              widget.onCountChanged?.call(count);
              setState(() => _count = count);
            },
            itemHeight: GridItemHeight.builder((_, _) => 100),
            itemBuilder: (context, i) =>
                SizedBox(height: 100, child: Text('item $i')),
          ),
        ],
      ),
    ),
  );
}

RenderSliverFluidGrid _grid(WidgetTester tester) => tester
    .renderObject<RenderSliverFluidGrid>(find.byType(SliverMasonryGridBody));

void main() {
  testWidgets(
    'a sliver pinch with photos style morphs between adjacent levels and covers the canvas window',
    (tester) async {
      final reported = <int>[];
      await tester.pumpWidget(_Harness(onCountChanged: reported.add));
      await tester.pump();

      // Hold a spreading pinch mid-flight: zoom heads from 6 toward 2.
      const center = Offset(200, 300);
      final g1 = await tester.startGesture(
        center - const Offset(50, 0),
        pointer: 1,
      );
      final g2 = await tester.startGesture(
        center + const Offset(50, 0),
        pointer: 2,
      );
      for (var step = 1; step <= 5; step++) {
        await g1.moveBy(const Offset(-12, 0));
        await g2.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }

      final grid = _grid(tester);
      final crossfade = grid.debugCrossfade;
      expect(crossfade.low, 2, reason: 'levels restrict the pair to (2, 6)');
      expect(crossfade.high, 6);
      expect(crossfade.t, greaterThan(0));
      expect(crossfade.t, lessThan(1));

      // Recompute the canvases exactly as the render object does and assert
      // every id whose PAINTED rect intersects the cache window is materialised.
      final (anchorId, anchorFraction) = grid.debugZoomAnchor;
      expect(anchorId, isNotNull, reason: 'the pinch captured an anchor');
      final lowCanvas = photosCanvasTransform(
        anchorEndpointRect: grid.debugLowRects[anchorId],
        anchorLerpedRect: grid.lastLayout!.itemRects[anchorId],
        anchorFraction: anchorFraction,
        endpointWidth: crossfade.lowWidth,
        itemWidth: crossfade.itemWidth,
        focalX: grid.debugPhotosFixedX ?? grid.zoomFocalX,
      )!;

      final constraints = grid.constraints;
      final winTop = constraints.scrollOffset + constraints.cacheOrigin;
      final winBottom = winTop + constraints.remainingCacheExtent;
      final materialised = grid.debugMaterialisedKeys
          .where((key) => key.kind == FluidChildKind.item)
          .map((key) => key.id)
          .toSet();

      var canvasMattered = false;
      for (final entry in grid.debugLowRects.entries) {
        final painted = mapRectByCanvas(lowCanvas, entry.value);
        final paintedVisible =
            painted.top < winBottom && painted.bottom > winTop;
        final rawVisible =
            entry.value.top < winBottom && entry.value.bottom > winTop;
        if (paintedVisible) {
          expect(
            materialised,
            contains(entry.key),
            reason:
                'item ${entry.key} paints inside the window under the low canvas and must be materialised',
          );
          if (!rawVisible) canvasMattered = true;
        }
      }
      // The compressing canvas (s_low < 1 mid zoom-out) must have pulled at least
      // one untransformed-off-window item on screen — the case this exists for.
      expect(lowCanvas.scale, lessThan(1));
      expect(
        canvasMattered,
        isTrue,
        reason: 'the transformed window test changed the outcome for some item',
      );

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(reported, isNotEmpty);
      expect(
        _levels,
        contains(reported.last),
        reason: 'the sliver release snaps to a level',
      );
      expect(
        reported.last,
        2,
        reason: 'spreading fingers zooms out to the lower level',
      );
    },
  );

  testWidgets(
    'a full photos pinch on the sliver settles cleanly back and forth',
    (tester) async {
      final reported = <int>[];
      await tester.pumpWidget(_Harness(onCountChanged: reported.add));
      await tester.pump();

      Future<void> pinch(double direction) async {
        const center = Offset(200, 300);
        final g1 = await tester.startGesture(
          center - const Offset(50, 0),
          pointer: 1,
        );
        final g2 = await tester.startGesture(
          center + const Offset(50, 0),
          pointer: 2,
        );
        for (var step = 1; step <= 6; step++) {
          await g1.moveBy(Offset(-12 * direction, 0));
          await g2.moveBy(Offset(12 * direction, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g1.up();
        await g2.up();
        await tester.pumpAndSettle();
      }

      await pinch(1); // spread: 6 -> 2
      expect(tester.takeException(), isNull);
      await pinch(-1); // pinch: 2 -> 6
      expect(tester.takeException(), isNull);

      expect(reported, [2, 6]);
      expect(find.text('item 0'), findsOneWidget);
    },
  );
}
