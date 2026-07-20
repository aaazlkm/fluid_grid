import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression for the photos-style ghost: mid-morph, the incoming rendition of
/// the pinched (anchor) tile drifted sideways from the outgoing one because the
/// canvases' shared horizontal fixed point was the raw finger x, whose
/// fractional position inside the anchor tile differs between the endpoint
/// layouts. With the fraction-matching abscissa ([photosPairFixedX]) as the
/// fixed point, the anchor's two renditions must coincide — both axes — on
/// every morph frame, including the 3→1 pair where no cell shift is possible.
class _SquareTile extends StatelessWidget {
  const _SquareTile(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: ColoredBox(
      color: const Color(0xFF4CAF50),
      child: Center(child: Text(label)),
    ),
  );
}

/// Uncontrolled like a real consumer: echoes the resolved count back in so a
/// real pinch gesture drives the morph. Square tiles keep the endpoint heights
/// aspect-preserved (the device-photos-gallery shape the bug was filmed on).
class _EchoHarness extends StatefulWidget {
  const _EchoHarness();

  @override
  State<_EchoHarness> createState() => _EchoHarnessState();
}

class _EchoHarnessState extends State<_EchoHarness> {
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
                onCrossAxisCountChanged: (count) => setState(() => _count = count),
                sections: const [
                  GridSection(id: 's', items: ['a', 'b', 'c', 'd', 'e', 'f']),
                ],
                itemBuilder: (context, item) => _SquareTile(item),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

RenderMasonryGrid _grid(WidgetTester tester) => tester.renderObject<RenderMasonryGrid>(find.byType(MasonryGridBody));

Finder _slotOf(String id, ZoomSlot slot) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is GridChild && widget.id == id && widget.zoomSlot == slot,
  ),
  matching: find.byType(_SquareTile),
);

void main() {
  testWidgets(
    "photos: the anchor tile's two renditions coincide throughout a 3→1 morph",
    (tester) async {
      await tester.pumpWidget(const _EchoHarness());
      await tester.pumpAndSettle();

      // Pinch OFF-centre (over column 0/1, away from every fraction-matching
      // abscissa of the pair) — the exact case whose finger-x fixed point used
      // to ghost the anchor sideways by ~1.5 px per px of finger offset.
      const center = Offset(100, 60);
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
      for (var step = 1; step <= 10; step++) {
        separation += 14;
        await g1.moveTo(center - Offset(separation / 2, 0));
        await g2.moveTo(center + Offset(separation / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));

        final grid = _grid(tester);
        final anchorId = grid.zoomAnchorId;
        final crossfade = grid.debugCrossfade;
        if (anchorId == null || crossfade.t <= 0 || crossfade.t >= 1) {
          continue;
        }
        morphFrames++;

        final low = tester.getRect(_slotOf(anchorId as String, ZoomSlot.low));
        final high = tester.getRect(_slotOf(anchorId, ZoomSlot.high));
        expect(
          (low.topLeft - high.topLeft).distance,
          lessThan(0.5),
          reason:
              'step $step (t ${crossfade.t.toStringAsFixed(3)}): the anchor '
              "tile's incoming and outgoing renditions must coincide",
        );
        expect(low.width, moreOrLessEquals(high.width, epsilon: 0.5));
        expect(low.height, moreOrLessEquals(high.height, epsilon: 0.5));
        expect(
          low.width,
          moreOrLessEquals(crossfade.itemWidth, epsilon: 0.5),
          reason: 'both renditions paint at the interpolated width',
        );
      }
      expect(
        morphFrames,
        greaterThanOrEqualTo(2),
        reason: 'sampled a real stretch of the morph',
      );

      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      expect(_grid(tester).debugCrossfade.t, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
