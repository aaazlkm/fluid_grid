// Each spring is a public constructor parameter backing a private field, so the
// default (a non-const withDurationAndBounce) can be resolved through a getter.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

/// Spring parameters driving the grid's motion.
///
/// Each spring is expressed with [SpringDescription.withDurationAndBounce]: a
/// settling [Duration] that sets the pace, and a `bounce` in `[-1, 1]` where 0
/// is critically damped (no overshoot), positive is bouncy (underdamped), and
/// negative is sluggish (overdamped).
///
/// The defaults are non-`const` because that factory computes stiffness/damping
/// at runtime, so each field is a nullable constructor parameter resolved to its
/// default through a getter — `const GridSprings()` still works.
@immutable
class GridSprings {
  const GridSprings({
    SpringDescription? reflow,
    SpringDescription? settle,
    SpringDescription? zoomTracking,
    SpringDescription? zoomSettle,
    this.enterDuration = const Duration(milliseconds: 220),
    this.exitDuration = const Duration(milliseconds: 150),
  }) : _reflow = reflow,
       _settle = settle,
       _zoomTracking = zoomTracking,
       _zoomSettle = zoomSettle;

  /// Siblings shifting out of the way, and items moving after a data change.
  /// Slightly bouncy (bounce 0.15, i.e. damping ratio ~0.85) so the motion
  /// reads as lively.
  static final SpringDescription defaultReflow = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 314),
    bounce: 0.15,
  );

  /// The dragged item snapping into its slot on release. Critically damped
  /// (bounce 0) so it never overshoots the drop target.
  static final SpringDescription defaultSettle = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 300),
    bounce: 0,
  );

  /// Item positions following the fingers while a pinch is in flight. Fast and
  /// critically damped so cards track near-1:1, while still absorbing a one-line
  /// text-rewrap height step over a couple of frames rather than snapping.
  static final SpringDescription defaultZoomTracking = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 140),
  );

  /// The whole grid settling to the resolved column count when the pinch ends.
  /// Critically damped (bounce 0) so the layout arrives without overshoot. The
  /// duration is the single knob for how long the settle takes.
  static final SpringDescription defaultZoomSettle = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 300),
    bounce: 0,
  );

  final SpringDescription? _reflow;

  /// Siblings shifting and data-change moves. Defaults to [defaultReflow].
  SpringDescription get reflow => _reflow ?? defaultReflow;

  final SpringDescription? _settle;

  /// The dragged item settling into its slot on drop. Defaults to
  /// [defaultSettle].
  SpringDescription get settle => _settle ?? defaultSettle;

  final SpringDescription? _zoomTracking;

  /// Item positions during an active pinch. Defaults to [defaultZoomTracking].
  SpringDescription get zoomTracking => _zoomTracking ?? defaultZoomTracking;

  final SpringDescription? _zoomSettle;

  /// The zoom level settling to the resolved count on release. Defaults to
  /// [defaultZoomSettle].
  SpringDescription get zoomSettle => _zoomSettle ?? defaultZoomSettle;

  /// Fade/scale-in of newly added items.
  final Duration enterDuration;

  /// Fade/scale-out of removed items.
  final Duration exitDuration;
}
