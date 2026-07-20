import 'dart:ui';

import 'package:fluid_grid/src/model/grid_zoom_config.dart';
import 'package:fluid_grid/src/zoom/zoom_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = GridZoomConfig();

  group('zoomLevelForScale', () {
    test('scale of 1 leaves the zoom at the base count', () {
      expect(zoomLevelForScale(scale: 1, baseZoom: 2, config: config), 2);
    });

    test('pinching out lowers the column count', () {
      // Doubling the card size (scale 2) halves the columns.
      expect(
        zoomLevelForScale(scale: 2, baseZoom: 2, config: config),
        moreOrLessEquals(1),
      );
      // A gentle spread lands between counts.
      expect(
        zoomLevelForScale(scale: 4 / 3, baseZoom: 2, config: config),
        moreOrLessEquals(1.5),
      );
    });

    test('pinching in raises the column count', () {
      expect(
        zoomLevelForScale(scale: 2 / 3, baseZoom: 2, config: config),
        moreOrLessEquals(3),
      );
    });

    test('crossing multiple counts in one gesture stays continuous', () {
      final z = zoomLevelForScale(scale: 0.5, baseZoom: 2, config: config);
      expect(z, moreOrLessEquals(4));
    });

    test(
      'a positive factor rubber-bands rather than hard-clamping past the maximum',
      () {
        const rubber = GridZoomConfig(rubberBandFactor: 0.15);
        // baseZoom/scale would be 8, well past max 4.
        final z = zoomLevelForScale(scale: 0.25, baseZoom: 2, config: rubber);
        expect(z, greaterThan(4), reason: 'overshoots the edge');
        expect(z, lessThan(5), reason: 'but only softly');
      },
    );

    test('a positive factor rubber-bands past the minimum', () {
      const rubber = GridZoomConfig(rubberBandFactor: 0.15);
      final z = zoomLevelForScale(scale: 8, baseZoom: 2, config: rubber);
      expect(z, lessThan(1));
      expect(z, greaterThan(0));
    });

    test(
      'the default is a hard stop: pinching past the range moves nothing',
      () {
        expect(zoomLevelForScale(scale: 8, baseZoom: 2, config: config), 1.0);
        expect(
          zoomLevelForScale(scale: 0.25, baseZoom: 2, config: config),
          4.0,
        );
        expect(zoomLevelForScale(scale: 0.1, baseZoom: 2, config: config), 4.0);
      },
    );

    test('continues from a fractional base when a pinch starts mid-settle', () {
      // Re-pinching while the previous settle is at z = 2.4 must not snap the
      // grid to an integer on the first update.
      expect(
        zoomLevelForScale(scale: 1, baseZoom: 2.4, config: config),
        moreOrLessEquals(2.4),
      );
      expect(
        zoomLevelForScale(scale: 1.2, baseZoom: 2.4, config: config),
        moreOrLessEquals(2),
      );
    });

    test('scale of 1 preserves an already-rubber-banded overshoot', () {
      // A second pinch that begins before an edge overshoot has settled starts
      // from an out-of-range base. The first update (scale 1) must hold that
      // value, not re-band it back under the fingers.
      const rubber = GridZoomConfig(rubberBandFactor: 0.15);
      expect(zoomLevelForScale(scale: 1, baseZoom: 4.12, config: rubber), 4.12);
    });
  });

  group('resolveZoomRelease', () {
    test('a gentle release snaps to the nearest count', () {
      expect(
        resolveZoomRelease(zoomLevel: 2.4, scaleVelocity: 0, config: config),
        2,
      );
      expect(
        resolveZoomRelease(zoomLevel: 2.6, scaleVelocity: 0, config: config),
        3,
      );
    });

    test(
      'a fast spread commits to fewer columns even below the halfway point',
      () {
        // zoom 2.8 would round to 3, but a strong outward fling drops to 2.
        expect(
          resolveZoomRelease(zoomLevel: 2.8, scaleVelocity: 3, config: config),
          2,
        );
      },
    );

    test(
      'a fast pinch commits to more columns even past the halfway point',
      () {
        // zoom 2.2 would round to 2, but a strong inward fling climbs to 3.
        expect(
          resolveZoomRelease(zoomLevel: 2.2, scaleVelocity: -3, config: config),
          3,
        );
      },
    );

    test('a slow velocity below the threshold still snaps to nearest', () {
      expect(
        resolveZoomRelease(zoomLevel: 2.2, scaleVelocity: 0.5, config: config),
        2,
      );
    });

    test('clamps the resolved count to the range', () {
      expect(
        resolveZoomRelease(zoomLevel: 4.6, scaleVelocity: 0, config: config),
        4,
      );
      expect(
        resolveZoomRelease(zoomLevel: 0.6, scaleVelocity: 0, config: config),
        1,
      );
      // A fling that would overshoot the edge is clamped.
      expect(
        resolveZoomRelease(zoomLevel: 1.2, scaleVelocity: 3, config: config),
        1,
      );
    });
  });

  group('resolveZoomRelease switchThreshold (directional travel)', () {
    // A 3-column step: the pair (2, 4) for the plain range and the levels
    // config below both have a step of 2, so t = 0.3 is zoom 2.6 / 3.6 and
    // t = 0.7 is zoom 3.4 / 4.4.
    const plain = GridZoomConfig(
      minCrossAxisCount: 1,
      maxCrossAxisCount: 6,
      switchThreshold: 0.3,
    );
    const levels = GridZoomConfig(
      zoomLevels: [1, 3, 5, 9],
      switchThreshold: 0.3,
    );

    test('zooming toward more columns switches after 30% of the step', () {
      // Plain: start at 3, pinch toward 4. Past 30% (t = 0.4, zoom 3.4) it
      // commits; short of it (t = 0.2, zoom 3.2) it stays on 3.
      expect(
        resolveZoomRelease(
          zoomLevel: 3.4,
          baseZoom: 3,
          scaleVelocity: 0,
          config: plain,
        ),
        4,
      );
      expect(
        resolveZoomRelease(
          zoomLevel: 3.2,
          baseZoom: 3,
          scaleVelocity: 0,
          config: plain,
        ),
        3,
      );
      // Levels: start at 3, pinch toward 5 (step 2). t = 0.4 is zoom 3.8,
      // t = 0.2 is zoom 3.4.
      expect(
        resolveZoomRelease(
          zoomLevel: 3.8,
          baseZoom: 3,
          scaleVelocity: 0,
          config: levels,
        ),
        5,
      );
      expect(
        resolveZoomRelease(
          zoomLevel: 3.4,
          baseZoom: 3,
          scaleVelocity: 0,
          config: levels,
        ),
        3,
      );
    });

    test('zooming toward fewer columns switches after 30% of the step', () {
      // Symmetric: start at 4/5, spread toward the lower level. It commits once
      // the zoom has travelled 30% of the way down (t <= 0.7).
      expect(
        resolveZoomRelease(
          zoomLevel: 3.6,
          baseZoom: 4,
          scaleVelocity: 0,
          config: plain,
        ),
        3,
      );
      expect(
        resolveZoomRelease(
          zoomLevel: 3.9,
          baseZoom: 4,
          scaleVelocity: 0,
          config: plain,
        ),
        4,
      );
      // Levels: start at 5, spread toward 3 (step 2). t = 0.6 is zoom 4.2,
      // t = 0.8 is zoom 4.6.
      expect(
        resolveZoomRelease(
          zoomLevel: 4.2,
          baseZoom: 5,
          scaleVelocity: 0,
          config: levels,
        ),
        3,
      );
      expect(
        resolveZoomRelease(
          zoomLevel: 4.6,
          baseZoom: 5,
          scaleVelocity: 0,
          config: levels,
        ),
        5,
      );
    });

    test('a fling still overrides the threshold', () {
      // Barely moved toward 5, but a hard inward fling commits to it anyway.
      expect(
        resolveZoomRelease(
          zoomLevel: 3.1,
          baseZoom: 3,
          scaleVelocity: -3,
          config: levels,
        ),
        5,
      );
      // Well past 30% toward 5, but a hard outward fling drops back to 3.
      expect(
        resolveZoomRelease(
          zoomLevel: 4.5,
          baseZoom: 3,
          scaleVelocity: 3,
          config: levels,
        ),
        3,
      );
    });

    test('a mid-pair start (re-pinch during a settle) measures TRAVEL', () {
      // Start mid-pair at zoom 2.5 (pair (1, 3), step 2, threshold 0.3 = 0.6
      // zoom units). Barely moving (2.5 -> 2.4, travel 0.05 of the step) must
      // NOT commit — it springs back to the level nearest the start (3), even
      // though the release position is 70% of the way toward 1.
      expect(
        resolveZoomRelease(
          zoomLevel: 2.4,
          baseZoom: 2.5,
          scaleVelocity: 0,
          config: levels,
        ),
        3,
      );
      // Deliberate travel from the same start (2.5 -> 1.8, travel 0.35 of the
      // step) commits toward 1.
      expect(
        resolveZoomRelease(
          zoomLevel: 1.8,
          baseZoom: 2.5,
          scaleVelocity: 0,
          config: levels,
        ),
        1,
      );
      // And the same travel back UP commits toward 3.
      expect(
        resolveZoomRelease(
          zoomLevel: 2.2,
          baseZoom: 1.5,
          scaleVelocity: 0,
          config: levels,
        ),
        3,
      );
    });

    test('a sweep across pairs measures travel inside the release pair', () {
      // A single gesture from 1 up into the (3, 5) pair: stopping just past 3
      // (zoom 3.2, 10% of the step into the pair) rests on 3 — the long travel
      // from 1 must not overshoot to 5.
      expect(
        resolveZoomRelease(
          zoomLevel: 3.2,
          baseZoom: 1,
          scaleVelocity: 0,
          config: levels,
        ),
        3,
      );
      // Travelling well into the pair (zoom 3.8, 40% of the step) commits 5.
      expect(
        resolveZoomRelease(
          zoomLevel: 3.8,
          baseZoom: 1,
          scaleVelocity: 0,
          config: levels,
        ),
        5,
      );
    });

    test('a threshold of 1.0 only switches on reaching the next level', () {
      const sticky = GridZoomConfig(
        zoomLevels: [1, 3, 5, 9],
        switchThreshold: 1,
      );
      // 90% of the way toward 5 is not enough — springs back to 3.
      expect(
        resolveZoomRelease(
          zoomLevel: 4.8,
          baseZoom: 3,
          scaleVelocity: 0,
          config: sticky,
        ),
        3,
      );
    });
  });

  group('anchorFractionForPoint', () {
    test('is unclamped outside the rect', () {
      const rect = Rect.fromLTWH(100, 100, 200, 100);
      final fraction = anchorFractionForPoint(
        anchorRect: rect,
        localPoint: const Offset(50, 350),
      );
      expect(fraction.dx, lessThan(0));
      expect(fraction.dy, greaterThan(1));
    });

    test('round-trips a point inside the rect', () {
      const rect = Rect.fromLTWH(100, 100, 200, 100);
      const point = Offset(180, 140);
      final fraction = anchorFractionForPoint(
        anchorRect: rect,
        localPoint: point,
      );
      expect(
        Offset(
          rect.left + fraction.dx * rect.width,
          rect.top + fraction.dy * rect.height,
        ),
        point,
      );
    });
  });

  group('levelNeighbors', () {
    const levels = [1, 3, 5, 9];

    test('null levels fall back to floor/ceil, matching today exactly', () {
      final fractional = levelNeighbors(3.7, null);
      expect(fractional.low, 3);
      expect(fractional.high, 4);
      expect(fractional.t, moreOrLessEquals(0.7));
      expect(levelNeighbors(4, null), (low: 4, high: 4, t: 0.0));
      // The >= 1 clamp survives.
      final belowOne = levelNeighbors(0.4, null);
      expect(belowOne.low, 1);
      expect(belowOne.high, 1);
    });

    test('a fractional zoom morphs between the two adjacent levels', () {
      final n = levelNeighbors(3.7, levels);
      expect(n.low, 3);
      expect(n.high, 5);
      expect(n.t, moreOrLessEquals((3.7 - 3) / (5 - 3)));
    });

    test('a non-level integer sits mid-pair, not on its own layout', () {
      final n = levelNeighbors(4, levels);
      expect(n.low, 3);
      expect(n.high, 5);
      expect(n.t, moreOrLessEquals(0.5));
    });

    test('exactly on a level collapses to the single-solve fast path', () {
      expect(levelNeighbors(5, levels), (low: 5, high: 5, t: 0.0));
      expect(levelNeighbors(1, levels), (low: 1, high: 1, t: 0.0));
      expect(levelNeighbors(9, levels), (low: 9, high: 9, t: 0.0));
    });

    test('overshoot beyond the last level extrapolates on the end pair', () {
      final n = levelNeighbors(9.3, levels);
      expect(n.low, 5);
      expect(n.high, 9);
      expect(n.t, greaterThan(1));
    });

    test('undershoot below the first level extrapolates on the first pair', () {
      final n = levelNeighbors(0.9, levels);
      expect(n.low, 1);
      expect(n.high, 3);
      expect(n.t, lessThan(0));
    });

    test('a single level is always at rest on itself', () {
      expect(levelNeighbors(7.2, const [5]), (low: 5, high: 5, t: 0.0));
    });
  });

  group('resolveZoomRelease with zoomLevels', () {
    const config = GridZoomConfig(zoomLevels: [1, 3, 5, 9]);

    test('a gentle release snaps to the nearest level', () {
      expect(
        resolveZoomRelease(zoomLevel: 3.7, scaleVelocity: 0, config: config),
        3,
      );
      expect(
        resolveZoomRelease(zoomLevel: 4.2, scaleVelocity: 0, config: config),
        5,
      );
      expect(
        resolveZoomRelease(zoomLevel: 7.5, scaleVelocity: 0, config: config),
        9,
      );
    });

    test(
      'an exact tie between levels goes to the higher one, like round()',
      () {
        expect(
          resolveZoomRelease(zoomLevel: 4, scaleVelocity: 0, config: config),
          5,
        );
      },
    );

    test(
      'a fast spread commits to the lower level even past the halfway point',
      () {
        expect(
          resolveZoomRelease(zoomLevel: 4.9, scaleVelocity: 3, config: config),
          3,
        );
      },
    );

    test(
      'a fast pinch commits to the higher level even below the halfway point',
      () {
        expect(
          resolveZoomRelease(zoomLevel: 3.1, scaleVelocity: -3, config: config),
          5,
        );
      },
    );

    test(
      'a fling during rubber-band overshoot still lands on the end level',
      () {
        expect(
          resolveZoomRelease(zoomLevel: 9.4, scaleVelocity: 3, config: config),
          9,
        );
        expect(
          resolveZoomRelease(zoomLevel: 0.8, scaleVelocity: -3, config: config),
          1,
        );
      },
    );
  });

  group('zoomLevelForScale with zoomLevels', () {
    test('rubber-bands against the level range, not min/max', () {
      // min/max deliberately narrower than the levels to prove precedence.
      const config = GridZoomConfig(
        maxCrossAxisCount: 4,
        zoomLevels: [1, 3, 5, 9],
        rubberBandFactor: 0.15,
      );
      final z = zoomLevelForScale(scale: 0.25, baseZoom: 5, config: config);
      // baseZoom/scale = 20, past the last level 9: soft overshoot beyond 9.
      expect(z, greaterThan(9));
      expect(z, lessThan(10));
    });

    test('the default hard stop clamps at the level range edges', () {
      const config = GridZoomConfig(zoomLevels: [1, 3, 5, 9]);
      expect(zoomLevelForScale(scale: 0.25, baseZoom: 5, config: config), 9);
      expect(zoomLevelForScale(scale: 8, baseZoom: 3, config: config), 1);
    });
  });
}
