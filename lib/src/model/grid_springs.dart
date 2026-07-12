import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

/// Spring parameters driving the grid's motion.
///
/// Damping ratio is `damping / (2 * sqrt(stiffness * mass))`.
@immutable
class GridSprings {
  const GridSprings({
    this.reflow = defaultReflow,
    this.settle = defaultSettle,
    this.zoomTracking = defaultZoomTracking,
    this.zoomSettle = defaultZoomSettle,
    this.enterDuration = const Duration(milliseconds: 220),
    this.exitDuration = const Duration(milliseconds: 150),
  });

  /// Siblings shifting out of the way, and items moving after a data change.
  /// Slightly underdamped (ratio ~0.85) so the motion reads as lively.
  static const SpringDescription defaultReflow = SpringDescription(mass: 1, stiffness: 400, damping: 34);

  /// The dragged item snapping into its slot on release. Critically damped
  /// (ratio ~1.0) so it never overshoots the drop target.
  static const SpringDescription defaultSettle = SpringDescription(mass: 1, stiffness: 550, damping: 47);

  /// Item positions following the fingers while a pinch is in flight. Very
  /// stiff and critically damped so cards track near-1:1, while still absorbing
  /// a one-line text-rewrap height step over a couple of frames rather than
  /// snapping.
  static const SpringDescription defaultZoomTracking = SpringDescription(mass: 1, stiffness: 2000, damping: 89);

  /// The whole grid settling to the resolved column count when the pinch ends.
  /// Critically damped so the layout arrives without overshoot.
  static const SpringDescription defaultZoomSettle = SpringDescription(mass: 1, stiffness: 500, damping: 45);

  final SpringDescription reflow;
  final SpringDescription settle;

  /// Item positions during an active pinch. See [defaultZoomTracking].
  final SpringDescription zoomTracking;

  /// The zoom level settling to the resolved count on release. See
  /// [defaultZoomSettle].
  final SpringDescription zoomSettle;

  /// Fade/scale-in of newly added items.
  final Duration enterDuration;

  /// Fade/scale-out of removed items.
  final Duration exitDuration;
}
