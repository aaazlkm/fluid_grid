import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Starts a drag after [delay], losing the pointer to an ancestor scrollable if
/// the user scrolls first and to a tap recognizer if they release first.
class DragStartListener extends StatelessWidget {
  const DragStartListener({
    required this.child,
    required this.onStart,
    required this.delay,
    required this.enabled,
    super.key,
  });

  final Widget child;
  final Drag? Function(Offset globalPosition) onStart;
  final Duration delay;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return RawGestureDetector(
      gestures: {
        DelayedMultiDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              DelayedMultiDragGestureRecognizer
            >(
              () => DelayedMultiDragGestureRecognizer(delay: delay),
              (instance) => instance.onStart = onStart,
            ),
      },
      child: child,
    );
  }
}
