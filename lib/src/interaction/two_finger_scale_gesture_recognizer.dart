import 'package:flutter/gestures.dart';

/// A [ScaleGestureRecognizer] that only claims the arena for a genuine
/// two-finger pinch, leaving single-finger scrolling to an ancestor list.
class TwoFingerScaleGestureRecognizer extends ScaleGestureRecognizer {
  TwoFingerScaleGestureRecognizer({required this.canStart});

  final bool Function() canStart;

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && (pointerCount < 2 || !canStart())) {
      return;
    }
    super.resolve(disposition);
  }
}
