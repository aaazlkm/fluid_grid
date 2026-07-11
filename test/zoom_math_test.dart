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
      expect(zoomLevelForScale(scale: 2, baseZoom: 2, config: config), moreOrLessEquals(1));
      // A gentle spread lands between counts.
      expect(zoomLevelForScale(scale: 4 / 3, baseZoom: 2, config: config), moreOrLessEquals(1.5));
    });

    test('pinching in raises the column count', () {
      expect(zoomLevelForScale(scale: 2 / 3, baseZoom: 2, config: config), moreOrLessEquals(3));
    });

    test('crossing multiple counts in one gesture stays continuous', () {
      final z = zoomLevelForScale(scale: 0.5, baseZoom: 2, config: config);
      expect(z, moreOrLessEquals(4));
    });

    test('a positive factor rubber-bands rather than hard-clamping past the maximum', () {
      const rubber = GridZoomConfig(rubberBandFactor: 0.15);
      // baseZoom/scale would be 8, well past max 4.
      final z = zoomLevelForScale(scale: 0.25, baseZoom: 2, config: rubber);
      expect(z, greaterThan(4), reason: 'overshoots the edge');
      expect(z, lessThan(5), reason: 'but only softly');
    });

    test('a positive factor rubber-bands past the minimum', () {
      const rubber = GridZoomConfig(rubberBandFactor: 0.15);
      final z = zoomLevelForScale(scale: 8, baseZoom: 2, config: rubber);
      expect(z, lessThan(1));
      expect(z, greaterThan(0));
    });

    test('the default is a hard stop: pinching past the range moves nothing', () {
      expect(zoomLevelForScale(scale: 8, baseZoom: 2, config: config), 1.0);
      expect(zoomLevelForScale(scale: 0.25, baseZoom: 2, config: config), 4.0);
      expect(zoomLevelForScale(scale: 0.1, baseZoom: 2, config: config), 4.0);
    });

    test('continues from a fractional base when a pinch starts mid-settle', () {
      // Re-pinching while the previous settle is at z = 2.4 must not snap the
      // grid to an integer on the first update.
      expect(zoomLevelForScale(scale: 1, baseZoom: 2.4, config: config), moreOrLessEquals(2.4));
      expect(zoomLevelForScale(scale: 1.2, baseZoom: 2.4, config: config), moreOrLessEquals(2));
    });
  });

  group('resolveZoomRelease', () {
    test('a gentle release snaps to the nearest count', () {
      expect(resolveZoomRelease(zoomLevel: 2.4, scaleVelocity: 0, config: config), 2);
      expect(resolveZoomRelease(zoomLevel: 2.6, scaleVelocity: 0, config: config), 3);
    });

    test('a fast spread commits to fewer columns even below the halfway point', () {
      // zoom 2.8 would round to 3, but a strong outward fling drops to 2.
      expect(resolveZoomRelease(zoomLevel: 2.8, scaleVelocity: 3, config: config), 2);
    });

    test('a fast pinch commits to more columns even past the halfway point', () {
      // zoom 2.2 would round to 2, but a strong inward fling climbs to 3.
      expect(resolveZoomRelease(zoomLevel: 2.2, scaleVelocity: -3, config: config), 3);
    });

    test('a slow velocity below the threshold still snaps to nearest', () {
      expect(resolveZoomRelease(zoomLevel: 2.2, scaleVelocity: 0.5, config: config), 2);
    });

    test('clamps the resolved count to the range', () {
      expect(resolveZoomRelease(zoomLevel: 4.6, scaleVelocity: 0, config: config), 4);
      expect(resolveZoomRelease(zoomLevel: 0.6, scaleVelocity: 0, config: config), 1);
      // A fling that would overshoot the edge is clamped.
      expect(resolveZoomRelease(zoomLevel: 1.2, scaleVelocity: 3, config: config), 1);
    });
  });

  group('anchorFractionForPoint', () {
    test('is unclamped outside the rect', () {
      const rect = Rect.fromLTWH(100, 100, 200, 100);
      final fraction = anchorFractionForPoint(anchorRect: rect, localPoint: const Offset(50, 350));
      expect(fraction.dx, lessThan(0));
      expect(fraction.dy, greaterThan(1));
    });

    test('round-trips a point inside the rect', () {
      const rect = Rect.fromLTWH(100, 100, 200, 100);
      const point = Offset(180, 140);
      final fraction = anchorFractionForPoint(anchorRect: rect, localPoint: point);
      expect(Offset(rect.left + fraction.dx * rect.width, rect.top + fraction.dy * rect.height), point);
    });
  });
}
