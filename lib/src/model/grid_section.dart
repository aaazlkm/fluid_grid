import 'package:flutter/widgets.dart';

/// A group of items rendered together, optionally framed by a header and a
/// footer that span the full content width.
@immutable
class GridSection<T> {
  const GridSection({
    required this.id,
    required this.items,
    this.header,
    this.footer,
    this.collapseWhenEmpty = false,
    this.emptyDropExtent = 64,
  });

  /// Stable identity of the section. Reported back in the reorder result.
  final Object id;

  /// Items in display order.
  final List<T> items;

  final Widget? header;
  final Widget? footer;

  /// When the section holds no items, animate the header and footer down to a
  /// zero extent. Suppressed while a drag is in flight so the section stays a
  /// visible drop target even as its last item leaves.
  final bool collapseWhenEmpty;

  /// Height of the drop zone kept under the header while the section is empty
  /// during a drag, so an empty section can still be dropped into.
  final double emptyDropExtent;
}
