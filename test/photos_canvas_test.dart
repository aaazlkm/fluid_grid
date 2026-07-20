import 'dart:ui';

import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/model/grid_zoom_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 2-column-ish endpoint layout: the anchor tile and one neighbour.
  const anchorRect = Rect.fromLTWH(0, 100, 200, 200);
  const otherRect = Rect.fromLTWH(208, 300, 200, 200);
  const fraction = Offset(0.5, 0.25);
  const focalX = 130.0;

  group('photosCanvasTransform', () {
    test('x is anchored at the focal, y on the anchor tile', () {
      const lerped = Rect.fromLTWH(30, 140, 150, 150);
      final canvas = photosCanvasTransform(
        anchorEndpointRect: anchorRect,
        anchorLerpedRect: lerped,
        anchorFraction: fraction,
        endpointWidth: 200,
        itemWidth: 150,
        focalX: focalX,
      )!;

      // The focal x is the horizontal fixed point: T(focalX) == focalX.
      expect(canvas.anchorK.dx, focalX);
      expect(canvas.anchorStar.dx, focalX);
      // y anchors on the tile: endpoint fraction point maps to the lerped one.
      expect(canvas.anchorK.dy, anchorRect.top + fraction.dy * 200);
      expect(canvas.anchorStar.dy, lerped.top + fraction.dy * 150);
      expect(canvas.scale, moreOrLessEquals(150 / 200));
    });

    test(
      'is the identity at the morph endpoint (itemWidth == endpointWidth, lerped == endpoint)',
      () {
        final canvas = photosCanvasTransform(
          anchorEndpointRect: anchorRect,
          anchorLerpedRect: anchorRect,
          anchorFraction: fraction,
          endpointWidth: 200,
          itemWidth: 200,
          focalX: focalX,
        )!;
        expect(canvas.scale, 1);
        expect(canvas.anchorK, canvas.anchorStar);
        expect(mapRectByCanvas(canvas, otherRect), otherRect);
      },
    );

    test('returns null when the anchor data is incomplete', () {
      expect(
        photosCanvasTransform(
          anchorEndpointRect: null,
          anchorLerpedRect: anchorRect,
          anchorFraction: fraction,
          endpointWidth: 200,
          itemWidth: 150,
          focalX: focalX,
        ),
        isNull,
      );
      expect(
        photosCanvasTransform(
          anchorEndpointRect: anchorRect,
          anchorLerpedRect: null,
          anchorFraction: fraction,
          endpointWidth: 200,
          itemWidth: 150,
          focalX: focalX,
        ),
        isNull,
      );
      expect(
        photosCanvasTransform(
          anchorEndpointRect: anchorRect,
          anchorLerpedRect: anchorRect,
          anchorFraction: fraction,
          endpointWidth: 0,
          itemWidth: 150,
          focalX: focalX,
        ),
        isNull,
      );
    });
  });

  group('photosCanvasGeometry', () {
    test('offsets are rigid: the delta between two items scales by s_K', () {
      const lerped = Rect.fromLTWH(30, 140, 150, 150);

      ({Offset offset, double scale}) geometryOf(Rect rect) => photosCanvasGeometry(
        endpointRect: rect,
        anchorEndpointRect: anchorRect,
        anchorLerpedRect: lerped,
        anchorFraction: fraction,
        endpointWidth: 200,
        itemWidth: 150,
        focalX: focalX,
      )!;

      final a = geometryOf(anchorRect);
      final b = geometryOf(otherRect);
      final expectedDelta = (otherRect.topLeft - anchorRect.topLeft) * (150 / 200);
      expect((b.offset - a.offset - expectedDelta).distance, lessThan(1e-9));
      expect(a.scale, moreOrLessEquals(150 / 200));
      expect(b.scale, moreOrLessEquals(150 / 200));
    });

    test('painted tile width equals the interpolated width', () {
      const lerped = Rect.fromLTWH(30, 140, 150, 150);
      final g = photosCanvasGeometry(
        endpointRect: otherRect,
        anchorEndpointRect: anchorRect,
        anchorLerpedRect: lerped,
        anchorFraction: fraction,
        endpointWidth: 200,
        itemWidth: 150,
        focalX: focalX,
      )!;
      expect(otherRect.width * g.scale, moreOrLessEquals(150));
    });

    test('returns null without an item rect or anchor data', () {
      expect(
        photosCanvasGeometry(
          endpointRect: null,
          anchorEndpointRect: anchorRect,
          anchorLerpedRect: anchorRect,
          anchorFraction: fraction,
          endpointWidth: 200,
          itemWidth: 150,
          focalX: focalX,
        ),
        isNull,
      );
      expect(
        photosCanvasGeometry(
          endpointRect: otherRect,
          anchorEndpointRect: null,
          anchorLerpedRect: anchorRect,
          anchorFraction: fraction,
          endpointWidth: 200,
          itemWidth: 150,
          focalX: focalX,
        ),
        isNull,
      );
    });
  });

  group('focal x-anchoring', () {
    // A mid-morph 2->1 pair on a 400-wide grid: low = 1 column (width 400),
    // high = 2 columns (width 196), item width interpolated.
    const width = 400.0;
    const lowAnchorRect = Rect.fromLTWH(0, 0, 400, 400);
    const highAnchorRect = Rect.fromLTWH(204, 0, 196, 196);
    const lerpedAnchorRect = Rect.fromLTWH(100, 0, 300, 300);
    const itemWidth = 300.0;

    ({Offset anchorK, Offset anchorStar, double scale}) canvasFor({
      required Rect endpointRect,
      required double endpointWidth,
      required double focal,
    }) => photosCanvasTransform(
      anchorEndpointRect: endpointRect,
      anchorLerpedRect: lerpedAnchorRect,
      anchorFraction: fraction,
      endpointWidth: endpointWidth,
      itemWidth: itemWidth,
      focalX: focal,
    )!;

    double mapX(
      ({Offset anchorK, Offset anchorStar, double scale}) canvas,
      double x,
    ) => canvas.anchorStar.dx + (x - canvas.anchorK.dx) * canvas.scale;

    test('the focal x is the fixed point of BOTH canvases at any t', () {
      for (final focal in [0.0, 130.0, 400.0]) {
        final low = canvasFor(
          endpointRect: lowAnchorRect,
          endpointWidth: 400,
          focal: focal,
        );
        final high = canvasFor(
          endpointRect: highAnchorRect,
          endpointWidth: 196,
          focal: focal,
        );
        expect(mapX(low, focal), moreOrLessEquals(focal));
        expect(mapX(high, focal), moreOrLessEquals(focal));
      }
    });

    test(
      'the covering (high) canvas always spans the viewport: no blank strip',
      () {
        // s_high = 300 / 196 > 1 and the focal lies inside the viewport, so
        // T(0) <= 0 and T(width) >= width structurally — no clamp needed.
        for (final focal in [0.0, 130.0, 250.0, 400.0]) {
          final high = canvasFor(
            endpointRect: highAnchorRect,
            endpointWidth: 196,
            focal: focal,
          );
          expect(high.scale, greaterThan(1));
          expect(mapX(high, 0), lessThanOrEqualTo(0));
          expect(mapX(high, width), greaterThanOrEqualTo(width));
        }
      },
    );

    test('changing the anchor tile rects never moves the x mapping', () {
      // The anchor tile only anchors y; x depends solely on the focal and the
      // scale, so a different anchor rect maps every x identically.
      final a = canvasFor(
        endpointRect: highAnchorRect,
        endpointWidth: 196,
        focal: 130,
      );
      final b = photosCanvasTransform(
        anchorEndpointRect: const Rect.fromLTWH(0, 392, 196, 196),
        anchorLerpedRect: const Rect.fromLTWH(50, 500, 300, 300),
        anchorFraction: fraction,
        endpointWidth: 196,
        itemWidth: itemWidth,
        focalX: 130,
      )!;
      for (final x in [0.0, 130.0, 333.0, 400.0]) {
        expect(mapX(a, x), moreOrLessEquals(mapX(b, x)));
      }
    });
  });

  group('photosPairFixedX', () {
    // A 2->1 pair on a 400-wide grid, anchor in the RIGHT column: the
    // fraction-matching abscissa is the shared right edge (x = 400), where the
    // anchor tile's fractional position is 1 in both endpoint layouts.
    const gridWidth = 400.0;
    const lowWidth = 400.0;
    const highWidth = 196.0;
    const lowAnchor = Rect.fromLTWH(0, 100, lowWidth, lowWidth);
    const highAnchor = Rect.fromLTWH(204, 300, highWidth, highWidth);

    test('is the abscissa whose anchor fraction matches in both layouts', () {
      final fixedX = photosPairFixedX(
        anchorLowRect: lowAnchor,
        anchorHighRect: highAnchor,
        lowWidth: lowWidth,
        highWidth: highWidth,
        gridWidth: gridWidth,
      )!;
      expect(fixedX, moreOrLessEquals(400));
      expect(
        (fixedX - lowAnchor.left) / lowWidth,
        moreOrLessEquals((fixedX - highAnchor.left) / highWidth),
      );
    });

    test(
      'anchoring both canvases at it makes the anchor renditions coincide '
      'with the lerped anchor rect at every t',
      () {
        final fixedX = photosPairFixedX(
          anchorLowRect: lowAnchor,
          anchorHighRect: highAnchor,
          lowWidth: lowWidth,
          highWidth: highWidth,
          gridWidth: gridWidth,
        )!;
        for (final f in [
          Offset.zero,
          const Offset(0.5, 0.25),
          const Offset(1, 1),
        ]) {
          for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            final itemWidth = lowWidth + (highWidth - lowWidth) * t;
            final lerped = Rect.lerp(lowAnchor, highAnchor, t)!;
            final low = photosCanvasTransform(
              anchorEndpointRect: lowAnchor,
              anchorLerpedRect: lerped,
              anchorFraction: f,
              endpointWidth: lowWidth,
              itemWidth: itemWidth,
              focalX: fixedX,
            )!;
            final high = photosCanvasTransform(
              anchorEndpointRect: highAnchor,
              anchorLerpedRect: lerped,
              anchorFraction: f,
              endpointWidth: highWidth,
              itemWidth: itemWidth,
              focalX: fixedX,
            )!;
            final lowMapped = mapRectByCanvas(low, lowAnchor);
            final highMapped = mapRectByCanvas(high, highAnchor);
            for (final pair in [
              (lowMapped, lerped),
              (highMapped, lerped),
            ]) {
              expect(
                (pair.$1.topLeft - pair.$2.topLeft).distance,
                lessThan(1e-6),
                reason: 'fraction $f, t $t',
              );
              expect(pair.$1.width, moreOrLessEquals(pair.$2.width));
              expect(pair.$1.height, moreOrLessEquals(pair.$2.height));
            }
          }
        }
      },
    );

    test('clamps to the grid width', () {
      final fixedX = photosPairFixedX(
        anchorLowRect: const Rect.fromLTWH(10, 0, 100, 100),
        anchorHighRect: const Rect.fromLTWH(200, 0, 50, 50),
        lowWidth: 100,
        highWidth: 50,
        gridWidth: 300,
      );
      // Raw value is 390 — outside the 300-wide grid.
      expect(fixedX, 300);
    });

    test('returns null on missing rects or degenerate widths', () {
      expect(
        photosPairFixedX(
          anchorLowRect: null,
          anchorHighRect: highAnchor,
          lowWidth: lowWidth,
          highWidth: highWidth,
          gridWidth: gridWidth,
        ),
        isNull,
      );
      expect(
        photosPairFixedX(
          anchorLowRect: lowAnchor,
          anchorHighRect: null,
          lowWidth: lowWidth,
          highWidth: highWidth,
          gridWidth: gridWidth,
        ),
        isNull,
      );
      expect(
        photosPairFixedX(
          anchorLowRect: lowAnchor,
          anchorHighRect: highAnchor,
          lowWidth: 200,
          highWidth: 200,
          gridWidth: gridWidth,
        ),
        isNull,
      );
      expect(
        photosPairFixedX(
          anchorLowRect: lowAnchor,
          anchorHighRect: highAnchor,
          lowWidth: 0,
          highWidth: highWidth,
          gridWidth: gridWidth,
        ),
        isNull,
      );
    });
  });

  group('mapRectByCanvas', () {
    test('scales the rect uniformly around the anchor', () {
      final canvas = photosCanvasTransform(
        anchorEndpointRect: anchorRect,
        anchorLerpedRect: const Rect.fromLTWH(30, 140, 150, 150),
        anchorFraction: fraction,
        endpointWidth: 200,
        itemWidth: 150,
        focalX: focalX,
      )!;
      final mapped = mapRectByCanvas(canvas, otherRect);
      expect(mapped.width, moreOrLessEquals(otherRect.width * canvas.scale));
      expect(mapped.height, moreOrLessEquals(otherRect.height * canvas.scale));
      expect(
        mapped.topLeft,
        canvas.anchorStar + (otherRect.topLeft - canvas.anchorK) * canvas.scale,
      );
    });
  });

  group('morphBlurSigma', () {
    test('is zero for a fully opaque rendition (crisp resting levels)', () {
      expect(morphBlurSigma(GridZoomStyle.morph, 1), 0);
    });

    test('grows linearly with transparency, peaking at full transparency', () {
      expect(morphBlurSigma(GridZoomStyle.morph, 0), kMorphBlurMaxSigma);
      expect(
        morphBlurSigma(GridZoomStyle.morph, 0.5),
        moreOrLessEquals(kMorphBlurMaxSigma / 2),
      );
      expect(
        morphBlurSigma(GridZoomStyle.morph, 0.75),
        moreOrLessEquals(kMorphBlurMaxSigma / 4),
      );
    });

    test('never blurs the photos style', () {
      expect(morphBlurSigma(GridZoomStyle.photos, 0), 0);
      expect(morphBlurSigma(GridZoomStyle.photos, 0.5), 0);
    });

    test('clamps an out-of-range alpha', () {
      expect(morphBlurSigma(GridZoomStyle.morph, 1.5), 0);
      expect(morphBlurSigma(GridZoomStyle.morph, -0.5), kMorphBlurMaxSigma);
    });
  });
}
