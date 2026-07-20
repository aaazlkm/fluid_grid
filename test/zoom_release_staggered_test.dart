import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:fluid_grid/src/layout/render_sliver_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for the "switchThreshold is not working" bug: on real hardware
/// the two fingers never lift in the same frame, and the trailing finger drags
/// a px or two while lifting. That restarted the scale recognizer after its
/// first end, spawning a phantom one-finger pinch session whose own release
/// re-resolved by nearest-level and overwrote the travel-threshold commit the
/// real release had just made — every deliberate pinch sprang back.
///
/// Both harnesses pinch 3 -> zoom 2.5 (t = 0.75, far past the default 0.1
/// threshold) and release STAGGERED: first finger up, the second moves 2 px,
/// then lifts. The release must commit to 1 exactly once.

class _SliverHarness extends StatefulWidget {
  const _SliverHarness({required this.onResolved});
  final void Function(int) onResolved;
  @override
  State<_SliverHarness> createState() => _SliverHarnessState();
}

class _SliverHarnessState extends State<_SliverHarness> {
  int _count = 3;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverFluidGrid<String>(
            crossAxisCount: _count,
            crossAxisSpacing: 1,
            mainAxisSpacing: 1,
            padding: const EdgeInsets.symmetric(horizontal: 1),
            idOf: (item) => item,
            zoomConfig: const GridZoomConfig(
              zoomLevels: [1, 3, 5, 9, 11, 13, 15],
              style: GridZoomStyle.photos,
            ),
            onCrossAxisCountChanged: (count) {
              widget.onResolved(count);
              setState(() => _count = count);
            },
            itemHeight: GridItemHeight.builder((item, itemWidth) => itemWidth),
            sections: [
              GridSection(
                id: 'device',
                items: [for (var i = 0; i < 30; i++) 'p$i'],
              ),
            ],
            itemBuilder: (context, item) => const ColoredBox(color: Color(0xFF4CAF50)),
          ),
        ],
      ),
    ),
  );
}

class _BoxHarness extends StatefulWidget {
  const _BoxHarness({required this.onResolved});
  final void Function(int) onResolved;
  @override
  State<_BoxHarness> createState() => _BoxHarnessState();
}

class _BoxHarnessState extends State<_BoxHarness> {
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
                zoomConfig: const GridZoomConfig(
                  zoomLevels: [1, 3],
                  style: GridZoomStyle.photos,
                ),
                idOf: (item) => item,
                onCrossAxisCountChanged: (count) {
                  widget.onResolved(count);
                  setState(() => _count = count);
                },
                sections: const [
                  GridSection(id: 's', items: ['a', 'b', 'c', 'd', 'e', 'f']),
                ],
                itemBuilder: (context, item) => AspectRatio(
                  aspectRatio: 1,
                  child: ColoredBox(
                    color: const Color(0xFF4CAF50),
                    child: Center(child: Text(item)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Spreads a wide pinch from [center] until the zoom sits at t = 0.75 in the
/// (1, 3) pair, holds, then releases staggered: the first finger lifts, the
/// second drags 2 px before lifting — the realistic lift-off every device
/// produces.
Future<void> _pinchAndReleaseStaggered(
  WidgetTester tester, {
  required Offset center,
}) async {
  // Wide start so the +60px spread clears the recognizer's span slop early
  // and lands on scale 1.2 (zoom 3 / 1.2 = 2.5).
  var separation = 300.0;
  final g1 = await tester.startGesture(
    center - Offset(separation / 2, 0),
    pointer: 1,
  );
  final g2 = await tester.startGesture(
    center + Offset(separation / 2, 0),
    pointer: 2,
  );

  for (var step = 1; step <= 10; step++) {
    separation += 6;
    await g1.moveTo(center - Offset(separation / 2, 0));
    await g2.moveTo(center + Offset(separation / 2, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  for (var i = 0; i < 6; i++) {
    await g1.moveBy(Offset.zero);
    await g2.moveBy(Offset.zero);
    await tester.pump(const Duration(milliseconds: 16));
  }

  await g1.up();
  await g2.moveBy(const Offset(2, 0));
  await tester.pump(const Duration(milliseconds: 8));
  await g2.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'sliver: a staggered lift keeps the travel-threshold commit',
    (tester) async {
      final resolved = <int>[];
      await tester.pumpWidget(_SliverHarness(onResolved: resolved.add));
      await tester.pumpAndSettle();

      final grid = tester.renderObject<RenderSliverFluidGrid>(
        find.byType(SliverMasonryGridBody),
      );
      await _pinchAndReleaseStaggered(tester, center: const Offset(200, 300));

      expect(
        resolved,
        [1],
        reason:
            'the deliberate pinch commits exactly once; the phantom '
            'one-finger session after the first lift must not re-resolve',
      );
      expect(grid.debugCrossfade.t, 0);
      expect(grid.debugCrossfade.low, 1);
    },
  );

  testWidgets('box: a staggered lift keeps the travel-threshold commit', (
    tester,
  ) async {
    final resolved = <int>[];
    await tester.pumpWidget(_BoxHarness(onResolved: resolved.add));
    await tester.pumpAndSettle();

    final grid = tester.renderObject<RenderMasonryGrid>(
      find.byType(MasonryGridBody),
    );
    await _pinchAndReleaseStaggered(tester, center: const Offset(200, 100));

    expect(resolved, [1]);
    expect(grid.debugCrossfade.t, 0);
    expect(grid.debugCrossfade.low, 1);
  });
}
