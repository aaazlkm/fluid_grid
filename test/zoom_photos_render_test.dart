import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed-height cards and zero spacing keep the endpoint layouts analytic:
/// at 2 columns (width 200) a(0,0) b(200,0) c(0,80) d(200,80); at 1 column
/// (width 400) a(0,0) b(0,80) c(0,160) d(0,240).
class _Card extends StatelessWidget {
  const _Card(this.label, {this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox(
      height: 80,
      child: ColoredBox(
        color: const Color(0xFF4CAF50),
        child: Center(child: Text(label)),
      ),
    ),
  );
}

class _Harness extends StatelessWidget {
  const _Harness({required this.crossAxisCount, this.onTapItem});

  final int crossAxisCount;
  final void Function(String item)? onTapItem;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: ListView(
            children: [
              FluidGrid<String>(
                crossAxisCount: crossAxisCount,
                reorderEnabled: false,
                zoomConfig: const GridZoomConfig(style: GridZoomStyle.photos),
                idOf: (item) => item,
                sections: const [
                  GridSection(id: 's', items: ['a', 'b', 'c', 'd']),
                ],
                itemBuilder: (context, item) => _Card(
                  item,
                  onTap: onTapItem == null ? null : () => onTapItem!(item),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A harness for REAL pinch gestures: uncontrolled like a real consumer, it
/// echoes the resolved count back in (the stateless [_Harness] drives
/// programmatic morphs only).
class _EchoHarness extends StatefulWidget {
  const _EchoHarness();

  @override
  State<_EchoHarness> createState() => _EchoHarnessState();
}

class _EchoHarnessState extends State<_EchoHarness> {
  // Starts at the range's top so a long spreading pinch crosses several
  // endpoint pairs while staying mid-morph.
  int _count = 4;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: ListView(
            children: [
              FluidGrid<String>(
                crossAxisCount: _count,
                reorderEnabled: false,
                zoomConfig: const GridZoomConfig(style: GridZoomStyle.photos),
                idOf: (item) => item,
                onCrossAxisCountChanged: (count) =>
                    setState(() => _count = count),
                sections: const [
                  GridSection(id: 's', items: ['a', 'b', 'c', 'd']),
                ],
                itemBuilder: (context, item) => _Card(item),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Like [_EchoHarness] but resting at 3 columns with a fuller (6-item) grid, so
/// a small pinch toward 4 that snaps back settles toward the pair's LOW end —
/// the aborted-zoom-out case that used to expose a pale edge strip.
class _AbortHarness extends StatefulWidget {
  const _AbortHarness();

  @override
  State<_AbortHarness> createState() => _AbortHarnessState();
}

class _AbortHarnessState extends State<_AbortHarness> {
  int _count = 3;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: ListView(
            children: [
              FluidGrid<String>(
                crossAxisCount: _count,
                reorderEnabled: false,
                zoomConfig: const GridZoomConfig(style: GridZoomStyle.photos),
                idOf: (item) => item,
                onCrossAxisCountChanged: (count) =>
                    setState(() => _count = count),
                sections: const [
                  GridSection(id: 's', items: ['a', 'b', 'c', 'd', 'e', 'f']),
                ],
                itemBuilder: (context, item) => _Card(item),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

RenderMasonryGrid _grid(WidgetTester tester) =>
    tester.renderObject<RenderMasonryGrid>(find.byType(MasonryGridBody));

Finder _slotOf(String id, ZoomSlot slot) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is GridChild && widget.id == id && widget.zoomSlot == slot,
  ),
  matching: find.byType(_Card),
);

/// Asserts the frame's core identity — each rendition's painted x-mapping has
/// its fixed point at the pair's frozen shared abscissa
/// ([RenderMasonryGrid.debugPhotosFixedX], falling back to the grab focal
/// [RenderMasonryGrid.zoomFocalX]) with `T(F) = F`, so the zoom is a pure
/// expansion about one frozen point with zero sideways translation. The fixed
/// point is reconstructed from a tile's painted rect versus its endpoint rect:
/// `s = painted.width / endpoint.width` and
/// `F = (painted.left − s·endpoint.left) / (1 − s)`; near-identity frames
/// (`s ≈ 1`) are skipped — there every point is fixed.
void _assertPaintedFixedPointIsFocal(
  WidgetTester tester, {
  required int step,
}) {
  final grid = _grid(tester);
  final focal = grid.debugPhotosFixedX ?? grid.zoomFocalX;
  for (final slot in [ZoomSlot.low, ZoomSlot.high]) {
    final endpointRects = slot == ZoomSlot.low
        ? grid.debugLowRects
        : grid.debugHighRects;
    final endpoint = endpointRects['a'];
    if (endpoint == null || endpoint.width == 0) continue;
    final painted = tester.getRect(_slotOf('a', slot));
    final s = painted.width / endpoint.width;
    if ((s - 1).abs() < 0.02) continue;
    final fixedPoint = (painted.left - s * endpoint.left) / (1 - s);
    expect(
      fixedPoint,
      moreOrLessEquals(focal, epsilon: 1.5),
      reason:
          'step $step, ${slot.name} rendition: the horizontal fixed point '
          'stays at the frozen pinch focal',
    );
  }
}

void main() {
  Future<
    ({
      double itemWidth,
      double sLow,
      double sHigh,
      Object? anchorId,
    })
  >
  startMorphTwoToOne(WidgetTester tester) async {
    await tester.pumpWidget(const _Harness(crossAxisCount: 2));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const _Harness(crossAxisCount: 1));
    // Step past the degenerate start (lowCount == highCount) into the morph.
    await tester.pump(const Duration(milliseconds: 24));

    final crossfade = _grid(tester).debugCrossfade;
    expect(crossfade.low, 1);
    expect(crossfade.high, 2);
    expect(crossfade.t, greaterThan(0));
    expect(crossfade.t, lessThan(1));
    return (
      itemWidth: crossfade.itemWidth,
      sLow: crossfade.itemWidth / crossfade.lowWidth,
      sHigh: crossfade.itemWidth / crossfade.highWidth,
      anchorId: crossfade.anchorId,
    );
  }

  testWidgets(
    'a programmatic photos morph captures an anchor and builds each item twice',
    (tester) async {
      final morph = await startMorphTwoToOne(tester);

      expect(find.byType(_Card), findsNWidgets(8));
      expect(
        morph.anchorId,
        isNotNull,
        reason: 'a programmatic morph must capture a viewport-centre anchor',
      );

      await tester.pumpAndSettle();
      expect(find.byType(_Card), findsNWidgets(4));
    },
  );

  testWidgets(
    'each canvas is rigid: painted deltas are the endpoint deltas scaled by s_K',
    (tester) async {
      final morph = await startMorphTwoToOne(tester);

      // Low canvas = the 1-column endpoint: c sits (0, 160) below a.
      final lowDelta =
          tester.getTopLeft(_slotOf('c', ZoomSlot.low)) -
          tester.getTopLeft(_slotOf('a', ZoomSlot.low));
      expect(lowDelta.dx, closeTo(0, 0.5));
      expect(lowDelta.dy, closeTo(160 * morph.sLow, 0.5));

      // High canvas = the 2-column endpoint: b sits (200, 0) right of a.
      final highDelta =
          tester.getTopLeft(_slotOf('b', ZoomSlot.high)) -
          tester.getTopLeft(_slotOf('a', ZoomSlot.high));
      expect(highDelta.dx, closeTo(200 * morph.sHigh, 0.5));
      expect(highDelta.dy, closeTo(0, 0.5));

      await tester.pumpAndSettle();
    },
  );

  testWidgets('both canvases paint tiles at the interpolated width', (
    tester,
  ) async {
    final morph = await startMorphTwoToOne(tester);

    for (final id in ['a', 'b', 'c', 'd']) {
      // getRect goes through applyPaintTransform, so it measures the painted
      // (canvas-scaled) size rather than the layout size.
      expect(
        tester.getRect(_slotOf(id, ZoomSlot.low)).width,
        moreOrLessEquals(morph.itemWidth, epsilon: 0.5),
        reason: '1-column rendition of $id paints at the interpolated width',
      );
      expect(
        tester.getRect(_slotOf(id, ZoomSlot.high)).width,
        moreOrLessEquals(morph.itemWidth, epsilon: 0.5),
        reason: '2-column rendition of $id paints at the interpolated width',
      );
    }

    await tester.pumpAndSettle();
  });

  testWidgets(
    'the two renditions of a non-anchor item sit at different positions (no per-item travel)',
    (tester) async {
      final morph = await startMorphTwoToOne(tester);

      // Pick an item that is not the anchor; under the morph style the two
      // renditions would coincide, under photos they belong to different
      // canvases and generally do not.
      final id = morph.anchorId == 'b' ? 'd' : 'b';
      final low = tester.getTopLeft(_slotOf(id, ZoomSlot.low));
      final high = tester.getTopLeft(_slotOf(id, ZoomSlot.high));
      expect(
        (low - high).distance,
        greaterThan(1),
        reason: 'canvas renditions sit at their own canvas positions',
      );

      await tester.pumpAndSettle();
    },
  );

  testWidgets('the settle lands pixel-exact on the target layout', (
    tester,
  ) async {
    await startMorphTwoToOne(tester);
    await tester.pumpAndSettle();

    expect(find.byType(_Card), findsNWidgets(4));
    expect(
      tester.getSize(find.byType(_Card).first).width,
      moreOrLessEquals(400),
    );
    expect(
      tester.getTopLeft(find.text('a')).dy,
      lessThan(tester.getTopLeft(find.text('b')).dy),
      reason: 'single column stacks the items',
    );
  });

  group('x-axis: the zoom expands about the frozen pinch focal', () {
    testWidgets(
      'the horizontal fixed point stays at the grab focal on every frame',
      (
        tester,
      ) async {
        await tester.pumpWidget(const _EchoHarness());
        await tester.pumpAndSettle();

        // Pinch near the right edge on 'd' (whose natural column swings hard
        // between layouts — the old tile-anchored canvases translated with
        // it). The canvases must instead expand about the frozen grab focal:
        // the fixed point never moves, so the page cannot drift sideways.
        const center = Offset(350, 40);
        var separation = 60.0;
        final g1 = await tester.startGesture(
          center - Offset(separation / 2, 0),
          pointer: 1,
        );
        final g2 = await tester.startGesture(
          center + Offset(separation / 2, 0),
          pointer: 2,
        );

        var morphFrames = 0;
        double? frozenFocal;
        for (var step = 1; step <= 10; step++) {
          separation += 12;
          await g1.moveTo(center - Offset(separation / 2, 0));
          await g2.moveTo(center + Offset(separation / 2, 0));
          await tester.pump(const Duration(milliseconds: 16));

          final grid = _grid(tester);
          if (grid.zoomAnchorId == null || grid.debugCrossfade.t <= 0) {
            continue;
          }
          morphFrames++;

          // The focal is captured once, when the gesture is accepted (within
          // the touch slop of the grab), and never re-targeted.
          frozenFocal ??= grid.zoomFocalX;
          expect(
            grid.zoomFocalX,
            frozenFocal,
            reason: 'step $step: the focal stays frozen for the whole gesture',
          );
          expect(
            frozenFocal,
            moreOrLessEquals(center.dx, epsilon: 20),
            reason: 'the frozen focal is (near) the grab point',
          );
          _assertPaintedFixedPointIsFocal(tester, step: step);
        }
        expect(morphFrames, greaterThanOrEqualTo(2));

        await g1.up();
        await g2.up();
        await tester.pumpAndSettle();

        expect(_grid(tester).debugCrossfade.t, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the covering canvas never reveals a blank strip at the edges', (
      tester,
    ) async {
      await tester.pumpWidget(const _EchoHarness());
      await tester.pumpAndSettle();

      // The video bug: pinning a column-flipping tile slid the whole grid past
      // the covering canvas's edge, leaving blank screen. Pinch 'd' (the worst
      // case) and assert the high canvas spans the full viewport on every
      // frame where it is solid.
      const center = Offset(350, 40);
      var separation = 60.0;
      final g1 = await tester.startGesture(
        center - Offset(separation / 2, 0),
        pointer: 1,
      );
      final g2 = await tester.startGesture(
        center + Offset(separation / 2, 0),
        pointer: 2,
      );

      var coveredFrames = 0;
      for (var step = 1; step <= 8; step++) {
        separation += 12;
        await g1.moveTo(center - Offset(separation / 2, 0));
        await g2.moveTo(center + Offset(separation / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));

        final grid = _grid(tester);
        final crossfade = grid.debugCrossfade;
        if (grid.zoomAnchorId == null || crossfade.t < kIncomingSolidAt) {
          continue;
        }

        // Reconstruct the high canvas transform from any painted high-slot
        // rect and its endpoint rect, then check its viewport span.
        final painted = tester.getRect(_slotOf('a', ZoomSlot.high));
        final endpoint = grid.debugHighRects['a']!;
        final s = painted.width / endpoint.width;
        final t0 = painted.left - s * endpoint.left;
        expect(
          t0,
          lessThanOrEqualTo(0.5),
          reason: 'step $step: the covering canvas reaches the left edge',
        );
        expect(
          t0 + s * 400,
          greaterThanOrEqualTo(399.5),
          reason: 'step $step: the covering canvas reaches the right edge',
        );
        expect(tester.takeException(), isNull);
        coveredFrames++;
      }
      expect(
        coveredFrames,
        greaterThanOrEqualTo(2),
        reason: 'sampled a real stretch of the solid morph',
      );

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      expect(_grid(tester).debugCrossfade.t, 0);
      expect(
        tester.getRect(find.byType(_Card).first).left,
        moreOrLessEquals(0, epsilon: 0.5),
      );
    });

    testWidgets(
      'the settle rests at the committed cell with no horizontal residual',
      (tester) async {
        await tester.pumpWidget(const _EchoHarness());
        await tester.pumpAndSettle();

        const center = Offset(300, 40);
        final g1 = await tester.startGesture(
          center - const Offset(30, 0),
          pointer: 1,
        );
        final g2 = await tester.startGesture(
          center + const Offset(30, 0),
          pointer: 2,
        );
        for (var step = 1; step <= 4; step++) {
          await g1.moveBy(const Offset(-6, 0));
          await g2.moveBy(const Offset(6, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g1.up();
        await g2.up();

        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull, reason: 'settle frame $i');
        }
        await tester.pumpAndSettle();

        final crossfade = _grid(tester).debugCrossfade;
        expect(crossfade.t, 0);
        // The resting layout is the committed OFFSET layout (iOS-style
        // re-anchoring): the first card sits exactly at its committed cell,
        // with no sub-cell residual from the pinch pinning.
        final offset = crossfade.lowOffsets['s'] ?? 0;
        final stride = crossfade.lowWidth;
        final firstCard = tester.getRect(find.byType(_Card).first);
        expect(
          firstCard.left,
          moreOrLessEquals(offset * stride, epsilon: 0.5),
          reason: 'card a rests at its committed cell (offset $offset)',
        );
      },
    );
  });

  group('aborted zoom-out settle', () {
    testWidgets(
      'the settle keeps expanding about the frozen grab focal despite a '
      'far-drifted finger position',
      (tester) async {
        await tester.pumpWidget(const _AbortHarness());
        await tester.pumpAndSettle();

        // Grab the top-left tile, then pinch slightly toward 4 columns while
        // sliding the fingers to the far right. Count 3 stays committed, so on
        // release it snaps back to 3 — the case that used to demand a large
        // horizontal settle pan. The canvases must keep expanding about the
        // GRAB focal (frozen; the drift never re-targets it): no drift, no
        // edge strip.
        const grab = Offset(60, 40);
        const drift = Offset(340, 40);
        final g1 = await tester.startGesture(
          grab - const Offset(30, 0),
          pointer: 1,
        );
        final g2 = await tester.startGesture(
          grab + const Offset(30, 0),
          pointer: 2,
        );
        for (var step = 1; step <= 6; step++) {
          // Shrinking the separation by only ~1px/step nudges the zoom just
          // past 3 toward 4 (t < 0.5), so a zero-velocity release snaps back
          // to 3; the focal drifts far right the whole time.
          final separation = 60 - step.toDouble();
          final focal = Offset.lerp(grab, drift, step / 6)!;
          await g1.moveTo(focal - Offset(separation / 2, 0));
          await g2.moveTo(focal + Offset(separation / 2, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g1.up();
        await g2.up();

        // The focal froze at gesture acceptance, near the grab; the long
        // rightward drift must not have re-targeted it.
        final frozenFocal = _grid(tester).zoomFocalX;
        expect(
          frozenFocal,
          lessThan(150),
          reason:
              'the focal froze near the grab (${grab.dx}), not at the '
              'drift target (${drift.dx})',
        );

        var dualFrames = 0;
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final grid = _grid(tester);
          final crossfade = grid.debugCrossfade;
          expect(tester.takeException(), isNull, reason: 'settle frame $i');
          if (crossfade.t <= 0) break;
          expect(
            grid.zoomFocalX,
            frozenFocal,
            reason: 'settle frame $i: the focal stays frozen',
          );
          _assertPaintedFixedPointIsFocal(tester, step: i);
          if (crossfade.low == 3 && crossfade.high == 4) dualFrames++;
        }
        await tester.pumpAndSettle();

        expect(
          dualFrames,
          greaterThanOrEqualTo(2),
          reason: 'the settle actually morphed toward the low level',
        );
        // The settle still lands pixel-exact on the canonical 3-column grid.
        expect(_grid(tester).debugCrossfade.t, 0);
        expect(_grid(tester).debugCrossfade.low, 3);
        expect(
          tester.getRect(find.byType(_Card).first).left,
          moreOrLessEquals(0, epsilon: 0.5),
          reason: 'the grid rests flush to the left edge',
        );
      },
    );
  });

  testWidgets('a tap mid-morph reaches exactly one copy', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(_Harness(crossAxisCount: 2, onTapItem: tapped.add));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_Harness(crossAxisCount: 1, onTapItem: tapped.add));
    await tester.pump(const Duration(milliseconds: 24));

    await tester.tap(_slotOf('a', ZoomSlot.low), warnIfMissed: false);
    expect(tapped, ['a']);

    await tester.pumpAndSettle();
  });
}
