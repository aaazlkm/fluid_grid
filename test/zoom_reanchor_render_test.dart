import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// iOS-style cell re-anchoring: a pinch on a column-flipping tile re-flows the
/// entering layout by whole cells so the tile lands in the cell nearest the
/// fingers, and that offset persists in the resting layout.
///
/// Geometry: width 400, 12 fixed-height (80) tiles, zero spacing/padding,
/// levels [3, 4, 5] starting at 4. Tile i3 is the canonical column-flipper:
/// right edge (col 3, left 300) at 4 columns, left edge (col 0) at 3.
class _Tile extends StatelessWidget {
  const _Tile(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 80,
    child: ColoredBox(
      color: const Color(0xFF4CAF50),
      child: Center(child: Text(label)),
    ),
  );
}

class _Harness extends StatefulWidget {
  const _Harness({super.key, this.onReorderFinished});

  final void Function(GridReorderResult<String> result)? onReorderFinished;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int count = 4;
  List<String> items = [for (var i = 0; i < 12; i++) 'i$i'];

  void setCount(int value) => setState(() => count = value);

  void setItems(List<String> value) => setState(() => items = value);

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
                crossAxisCount: count,
                reorderEnabled: widget.onReorderFinished != null,
                dragStartDelay: Duration.zero,
                zoomConfig: const GridZoomConfig(
                  style: GridZoomStyle.photos,
                  zoomLevels: [3, 4, 5],
                ),
                idOf: (item) => item,
                onCrossAxisCountChanged: (value) => setState(() => count = value),
                onReorderFinished: widget.onReorderFinished,
                sections: [GridSection(id: 's', items: items)],
                itemBuilder: (context, item) => _Tile(item),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

RenderMasonryGrid _grid(WidgetTester tester) => tester.renderObject<RenderMasonryGrid>(find.byType(MasonryGridBody));

/// The painted rect of [id]'s tile. During a crossfade two copies exist; for
/// the ANCHOR both are pinned to the same fraction point and painted at the
/// same interpolated width, so either copy measures the same thing.
Rect _tileRect(WidgetTester tester, String id) => tester.getRect(find.widgetWithText(_Tile, id).first);

/// Scale gestures accept only after a pointer travels past the touch slop,
/// so with an asymmetric (drifting) gesture the anchor would be captured
/// mid-drift, at an unpredictable focal. This symmetric spread-and-return
/// exceeds the slop while keeping the focal at [center] the whole time, so
/// acceptance — and the anchor capture — happen exactly where the test's
/// geometry assumes.
Future<void> _warmUp(
  WidgetTester tester,
  TestGesture g1,
  TestGesture g2, {
  required Offset center,
  required double from,
}) async {
  for (final separation in [from + 20, from + 40, from + 20, from]) {
    await g1.moveTo(center - Offset(separation / 2, 0));
    await g2.moveTo(center + Offset(separation / 2, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Runs a two-finger pinch around [center], interpolating finger separation
/// [from] → [to] over [steps] frames. Calls [onFrame] after each pump. When
/// [firstMoveCenter] is set, the very first update jumps the focal point there
/// (the fingers move together sideways), exercising entering-count deltas
/// chosen from a focal far from the grab point. When [driftTo] is set, the
/// focal slides there over the first 60% of the steps — sideways finger travel
/// DURING the morph, while the crossfade is still mid-flight.
Future<void> _pinch(
  WidgetTester tester, {
  required Offset center,
  required double from,
  required double to,
  int steps = 8,
  Offset? firstMoveCenter,
  Offset? driftTo,
  void Function(int step)? onFrame,
}) async {
  final g1 = await tester.startGesture(
    center - Offset(from / 2, 0),
    pointer: 7,
  );
  final g2 = await tester.startGesture(
    center + Offset(from / 2, 0),
    pointer: 8,
  );
  if (driftTo != null) {
    await _warmUp(tester, g1, g2, center: center, from: from);
  }
  for (var step = 1; step <= steps; step++) {
    final separation = from + (to - from) * step / steps;
    var focal = firstMoveCenter ?? center;
    if (driftTo != null) {
      focal = Offset.lerp(
        center,
        driftTo,
        (step / (steps * 0.6)).clamp(0.0, 1.0),
      )!;
    }
    await g1.moveTo(focal - Offset(separation / 2, 0));
    await g2.moveTo(focal + Offset(separation / 2, 0));
    await tester.pump(const Duration(milliseconds: 16));
    onFrame?.call(step);
  }
  await g1.up();
  await g2.up();
}

void main() {
  testWidgets(
    'sweep regression: cycling pinches on a column-flipping tile keep it near '
    'the fingers instead of sweeping edge to edge',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      // Grab i3 (right edge at 4 columns, canonical left edge at 3) and cycle
      // zoom in / zoom out three times. Before re-anchoring the tile's painted
      // left swept nearly the full width (0 ↔ 300); with it, the entering
      // layouts re-flow so the tile stays in the cell under the fingers.
      const center = Offset(350, 40);
      final lefts = <double>[];
      var previous = _tileRect(tester, 'i3').left;
      void sample(int _) {
        final left = _tileRect(tester, 'i3').left;
        lefts.add(left);
        expect(
          (left - previous).abs(),
          lessThan(80),
          reason: 'the tile never jumps by nearly a column in a single frame',
        );
        previous = left;
      }

      for (var cycle = 0; cycle < 3; cycle++) {
        // Zoom in: 4 → 3 columns.
        await _pinch(
          tester,
          center: center,
          from: 60,
          to: 160,
          onFrame: sample,
        );
        await tester.pumpAndSettle();
        sample(0);
        // Zoom out: 3 → 4 columns (higher counts need a stronger contraction).
        await _pinch(
          tester,
          center: center,
          from: 160,
          to: 60,
          onFrame: sample,
        );
        await tester.pumpAndSettle();
        sample(0);
      }

      final min = lefts.reduce((a, b) => a < b ? a : b);
      final max = lefts.reduce((a, b) => a > b ? a : b);
      expect(
        max - min,
        lessThan(1.5 * (400 / 3)),
        reason:
            'painted left stays within ~a column of the fingers '
            '(was ~full-width before re-anchoring)',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the settled layout is the canonical layout shifted by the committed '
    'cell offset, with the anchor resting under the fingers',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      const center = Offset(350, 40);
      await _pinch(tester, center: center, from: 60, to: 160);
      await tester.pumpAndSettle();

      final grid = _grid(tester);
      final crossfade = grid.debugCrossfade;
      expect(crossfade.t, 0);

      // The pinch settles on 3 columns with a non-zero committed offset: i3's
      // canonical column is 0, but the fingers were over the right part of the
      // screen.
      final offset = crossfade.lowOffsets['s'];
      expect(offset, isNotNull);
      expect(offset, isNot(0));

      // The anchor rests in the cell under the fingers.
      final anchorRect = _tileRect(tester, 'i3');
      expect(anchorRect.left - 1, lessThanOrEqualTo(center.dx));
      expect(anchorRect.right + 1, greaterThanOrEqualTo(center.dx));

      // Every tile sits exactly on the canonical 3-column layout shifted by
      // `offset` cells: item i occupies cell i + offset.
      const stride = 400 / 3;
      for (var i = 0; i < 12; i++) {
        final cell = i + offset!;
        final rect = _tileRect(tester, 'i$i');
        expect(
          rect.left,
          moreOrLessEquals((cell % 3) * stride, epsilon: 0.5),
          reason: 'i$i rests in column ${cell % 3}',
        );
        expect(
          rect.top,
          moreOrLessEquals((cell ~/ 3) * 80.0, epsilon: 0.5),
          reason: 'i$i rests in row ${cell ~/ 3}',
        );
      }
    },
  );

  testWidgets(
    'an edge finger clamps the target column instead of wrapping to the '
    'opposite edge',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      // Grab i3 near its left edge (fraction ≈ 0.4) then slide the fingers to
      // the right edge of the screen while spreading. The raw target column
      // rounds past the last column; without the clamp-before-mod it wraps to
      // column 0 and the tile snaps to the LEFT edge while the fingers sit at
      // the RIGHT edge.
      await _pinch(
        tester,
        center: const Offset(340, 40),
        firstMoveCenter: const Offset(390, 40),
        from: 60,
        to: 160,
      );
      await tester.pumpAndSettle();

      final crossfade = _grid(tester).debugCrossfade;
      expect(crossfade.t, 0);
      final rect = _tileRect(tester, 'i3');
      expect(
        rect.left,
        greaterThan(200),
        reason: 'the tile rests in the rightmost column, not wrapped to 0',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a re-pinch mid-settle keeps the committed count frozen (no cell jump)',
    (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      const center = Offset(350, 40);
      var previous = _tileRect(tester, 'i3').left;
      void sample(int _) {
        final left = _tileRect(tester, 'i3').left;
        expect(
          (left - previous).abs(),
          lessThan(80),
          reason: 'no single-frame cell jump across the re-pinch',
        );
        previous = left;
      }

      await _pinch(tester, center: center, from: 60, to: 160, onFrame: sample);
      // Only a few settle frames: the morph is still collapsing when the second
      // pinch lands.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        sample(0);
      }
      await _pinch(tester, center: center, from: 160, to: 60, onFrame: sample);
      await tester.pumpAndSettle();
      sample(0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a small pinch that settles back on the starting level leaves the resting '
    'layout canonical',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      // Spread by 10%: zoom 4 → ≈3.6, which is still nearest 4, so the grid
      // springs back. The briefly-entered count-3 offset must not leak into
      // the resting 4-column layout.
      await _pinch(tester, center: const Offset(350, 40), from: 60, to: 66);
      await tester.pumpAndSettle();

      final crossfade = _grid(tester).debugCrossfade;
      expect(crossfade.low, 4);
      expect(crossfade.t, 0);
      expect(crossfade.lowOffsets['s'] ?? 0, 0);
      expect(_tileRect(tester, 'i0').left, moreOrLessEquals(0, epsilon: 0.5));
      expect(_tileRect(tester, 'i3').left, moreOrLessEquals(300, epsilon: 0.5));
    },
  );

  testWidgets(
    'an external crossAxisCount change morphs back to the canonical layout',
    (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: key));
      await tester.pumpAndSettle();

      // Commit a non-zero offset at 3 columns.
      await _pinch(tester, center: const Offset(350, 40), from: 60, to: 160);
      await tester.pumpAndSettle();
      expect(_grid(tester).debugCrossfade.lowOffsets['s'], isNot(0));

      // A programmatic change has no fingers to serve: the entering count is
      // canonical.
      key.currentState!.setCount(4);
      await tester.pump();
      await tester.pumpAndSettle();

      final crossfade = _grid(tester).debugCrossfade;
      expect(crossfade.low, 4);
      expect(crossfade.t, 0);
      expect(crossfade.lowOffsets['s'] ?? 0, 0);
      expect(_tileRect(tester, 'i0').left, moreOrLessEquals(0, epsilon: 0.5));
    },
  );

  testWidgets('the committed offset persists across a data update', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    await tester.pumpAndSettle();

    await _pinch(tester, center: const Offset(350, 40), from: 60, to: 160);
    await tester.pumpAndSettle();
    final offset = _grid(tester).debugCrossfade.lowOffsets['s'];
    expect(offset, isNot(0));
    final restingLeft = _tileRect(tester, 'i0').left;

    // Append an item: the section survives reconciliation, so its offset (and
    // therefore every resting position) is retained — like iOS, where the
    // shifted alignment persists library-wide.
    key.currentState!.setItems([
      for (var i = 0; i < 13; i++) 'i$i',
    ]);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(_grid(tester).debugCrossfade.lowOffsets['s'], offset);
    expect(
      _tileRect(tester, 'i0').left,
      moreOrLessEquals(restingLeft, epsilon: 0.5),
    );
    // The new item continues the shifted flow: cell 12 + offset.
    final cell = 12 + offset!;
    const stride = 400 / 3;
    expect(
      _tileRect(tester, 'i12').left,
      moreOrLessEquals((cell % 3) * stride, epsilon: 0.5),
    );
  });

  testWidgets('reordering on an offset resting grid reports plain indices', (
    tester,
  ) async {
    GridReorderResult<String>? result;
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(key: key, onReorderFinished: (r) => result = r),
    );
    await tester.pumpAndSettle();

    await _pinch(tester, center: const Offset(350, 40), from: 60, to: 160);
    await tester.pumpAndSettle();
    final offset = _grid(tester).debugCrossfade.lowOffsets['s'];
    expect(offset, isNot(0));

    // Drag i0 onto i2's resting cell: the resolver must interpret the drop
    // against the OFFSET layout, yielding index 2 (a canonical-minded resolver
    // would misread the shifted columns).
    final from = _tileRect(tester, 'i0').center;
    final to = _tileRect(tester, 'i2').center;
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 32));
    // Move in small steps so the drag recognizer and resolver track the path.
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(Offset.lerp(from, to, step / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.toIndex, 2);
  });

  group('sideways finger travel mid-pinch does not re-flow the grid', () {
    // Geometry reminder: at 3 columns the stride is 400/3 ≈ 133.3. The
    // re-anchor cell is chosen ONCE, as the endpoint enters (from the grab
    // focal); sliding the fingers afterward no longer re-flows the incoming
    // grid. Live retargeting was removed with the horizontal pan — without the
    // pan to absorb a mid-morph re-flow it would snap the grid sideways, the
    // very movement this fix exists to remove. Separations stay in [60, 78] so
    // the zoom holds inside the (3, 4) pair while the focal drifts.

    testWidgets(
      'a right-to-left drift leaves the tile in its entry cell, under the '
      'INITIAL fingers — no snap',
      (tester) async {
        await tester.pumpWidget(const _Harness());
        await tester.pumpAndSettle();

        // Grab i3 at (350, 40) — the entry delta targets its column — then
        // slide the fingers to (150, 40) while the morph is in flight.
        const grab = Offset(350, 40);
        const drift = Offset(150, 40);
        var previous = _tileRect(tester, 'i3').left;
        await _pinch(
          tester,
          center: grab,
          driftTo: drift,
          from: 60,
          to: 78,
          steps: 10,
          onFrame: (_) {
            final left = _tileRect(tester, 'i3').left;
            expect(
              (left - previous).abs(),
              lessThan(40),
              reason: 'the grid never snaps sideways as the fingers drift',
            );
            previous = left;
          },
        );
        await tester.pumpAndSettle();

        final grid = _grid(tester);
        expect(grid.debugCrossfade.low, 3);
        expect(grid.debugCrossfade.t, 0);
        // The tile rests under the INITIAL fingers (350), NOT dragged to the
        // drift target (150) — the entry cell holds.
        final rect = _tileRect(tester, 'i3');
        expect(rect.left - 1, lessThanOrEqualTo(grab.dx));
        expect(rect.right + 1, greaterThanOrEqualTo(grab.dx));
        expect(
          rect.left <= drift.dx && drift.dx <= rect.right,
          isFalse,
          reason: 'the tile did not follow the fingers to the drift target',
        );
      },
    );

    testWidgets(
      'a left-to-right drift likewise leaves the entry cell in place',
      (tester) async {
        await tester.pumpWidget(const _Harness());
        await tester.pumpAndSettle();

        // Grab i1 at (150, 40) and slide to (350, 40); the entry cell is fixed
        // at the grab.
        const grab = Offset(150, 40);
        const drift = Offset(350, 40);
        await _pinch(
          tester,
          center: grab,
          driftTo: drift,
          from: 60,
          to: 78,
          steps: 10,
        );
        await tester.pumpAndSettle();

        final grid = _grid(tester);
        expect(grid.debugCrossfade.low, 3);
        expect(grid.debugCrossfade.t, 0);
        final rect = _tileRect(tester, 'i1');
        expect(rect.left - 1, lessThanOrEqualTo(grab.dx));
        expect(rect.right + 1, greaterThanOrEqualTo(grab.dx));
        expect(
          rect.left <= drift.dx && drift.dx <= rect.right,
          isFalse,
          reason: 'the tile did not follow the fingers to the drift target',
        );
      },
    );

    testWidgets('a reversing focal jitter leaves the entry cell unchanged', (
      tester,
    ) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      // Enter the morph on i3 (its entry cell is fixed at the grab), then
      // jitter the focal between 240 and 260 across a cell boundary. With live
      // retargeting removed, none of this re-flows the grid.
      const center = Offset(350, 40);
      final g1 = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 7,
      );
      final g2 = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 8,
      );
      await _warmUp(tester, g1, g2, center: center, from: 60);
      for (var step = 1; step <= 4; step++) {
        final separation = 60 + 12 * step / 4;
        await g1.moveTo(center - Offset(separation / 2, 0));
        await g2.moveTo(center + Offset(separation / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Baseline first: the entry delta chosen when the pair was entered.
      final offsets = <int>[_grid(tester).debugCrossfade.lowOffsets['s'] ?? 0];
      for (var step = 0; step < 8; step++) {
        final focal = Offset(step.isEven ? 240 : 260, 40);
        await g1.moveTo(focal - const Offset(36, 0));
        await g2.moveTo(focal + const Offset(36, 0));
        await tester.pump(const Duration(milliseconds: 16));
        offsets.add(_grid(tester).debugCrossfade.lowOffsets['s'] ?? 0);
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      var transitions = 0;
      for (var i = 1; i < offsets.length; i++) {
        if (offsets[i] != offsets[i - 1]) transitions++;
      }
      expect(
        transitions,
        0,
        reason:
            'the entry cell holds: a jittering focal never re-flows the '
            'grid: $offsets',
      );
    });

    testWidgets(
      'the committed count is never re-flowed by a drifting pinch',
      (tester) async {
        await tester.pumpWidget(const _Harness());
        await tester.pumpAndSettle();

        final highOffsets = <int>{};
        await _pinch(
          tester,
          center: const Offset(350, 40),
          driftTo: const Offset(150, 40),
          from: 60,
          to: 78,
          steps: 10,
          onFrame: (_) {
            final crossfade = _grid(tester).debugCrossfade;
            if (crossfade.high == 4) {
              highOffsets.add(crossfade.highOffsets['s'] ?? 0);
            }
          },
        );
        await tester.pumpAndSettle();

        expect(
          highOffsets,
          {0},
          reason: 'the resting 4-column canvas stays canonical on every frame',
        );
      },
    );

    testWidgets(
      'a drifting reversal back to the committed count restores its layout '
      'unchanged',
      (tester) async {
        await tester.pumpWidget(const _Harness());
        await tester.pumpAndSettle();

        // Head toward 3 columns, then contract back toward 4 while drifting:
        // the candidate for retargeting is the committed count, which stays
        // frozen, so the grid returns to the canonical 4-column layout.
        const center = Offset(350, 40);
        final g1 = await tester.startGesture(
          center - const Offset(30, 0),
          pointer: 7,
        );
        final g2 = await tester.startGesture(
          center + const Offset(30, 0),
          pointer: 8,
        );
        await _warmUp(tester, g1, g2, center: center, from: 60);
        for (var step = 1; step <= 4; step++) {
          final separation = 60 + 16 * step / 4;
          await g1.moveTo(center - Offset(separation / 2, 0));
          await g2.moveTo(center + Offset(separation / 2, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        for (var step = 1; step <= 6; step++) {
          // Ends at separation 58 → zoom ≈ 4.14, which settles back on 4.
          final separation = 76 - 18 * step / 6;
          final focal = Offset.lerp(center, const Offset(150, 40), step / 6)!;
          await g1.moveTo(focal - Offset(separation / 2, 0));
          await g2.moveTo(focal + Offset(separation / 2, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g1.up();
        await g2.up();
        await tester.pumpAndSettle();

        final crossfade = _grid(tester).debugCrossfade;
        expect(crossfade.low, 4);
        expect(crossfade.t, 0);
        expect(crossfade.lowOffsets['s'] ?? 0, 0);
        expect(_tileRect(tester, 'i0').left, moreOrLessEquals(0, epsilon: 0.5));
      },
    );
  });
}
