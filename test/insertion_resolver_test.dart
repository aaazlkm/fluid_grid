import 'package:fluid_grid/src/drag/insertion_resolver.dart';
import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// width 216, no padding -> content 216; (216 - 8) / 2 = 104 per column.
const _template = GridLayoutSpec(
  width: 216,
  sections: [],
  crossAxisSpacing: 8,
  mainAxisSpacing: 8,
  padding: EdgeInsets.zero,
);

const _heights = {'a': 40.0, 'b': 40.0, 'c': 40.0, 'x': 40.0};

InsertionCandidate? resolve({
  required List<SectionOrder> sections,
  required Offset draggedTopLeft,
  List<SectionChrome> chrome = const [],
  InsertionCandidate? current,
}) => resolveInsertion(
  sections: sections,
  chrome: chrome,
  heights: _heights,
  draggedId: 'x',
  draggedTopLeft: draggedTopLeft,
  template: _template,
  current: current,
);

void main() {
  group('single section', () {
    final sections = [
      const SectionOrder(id: 's', itemIds: ['a', 'b', 'c']),
    ];

    test('resolves to the first slot when dragged over the top-left cell', () {
      final candidate = resolve(
        sections: sections,
        draggedTopLeft: Offset.zero,
      );
      expect(candidate, const InsertionCandidate(sectionId: 's', index: 0));
    });

    test('resolves to a late slot when dragged below the existing items', () {
      final candidate = resolve(
        sections: sections,
        draggedTopLeft: const Offset(112, 48),
      );
      expect(candidate, isNotNull);
      expect(candidate!.sectionId, 's');
      expect(candidate.index, greaterThanOrEqualTo(2));
    });

    test(
      'the trailing slot wins when dragged past the last item in its column',
      () {
        // Three items fill column 0 twice and column 1 once, so the final slot is
        // the one that lands in column 1. Dragging to the bottom-right picks it.
        final candidate = resolve(
          sections: sections,
          draggedTopLeft: const Offset(112, 1000),
        );
        expect(candidate, const InsertionCandidate(sectionId: 's', index: 3));
      },
    );

    test(
      'the column, not just the row, decides between two slots at the same height',
      () {
        // Index 2 and index 3 both place the item at y=48; they differ only in
        // column. Dragging to the bottom-left must therefore choose index 2.
        final candidate = resolve(
          sections: sections,
          draggedTopLeft: const Offset(0, 1000),
        );
        expect(candidate, const InsertionCandidate(sectionId: 's', index: 2));
      },
    );
  });

  group('hysteresis', () {
    final sections = [
      const SectionOrder(id: 's', itemIds: ['a', 'b']),
    ];

    test(
      'holds the current slot when a challenger is only marginally closer',
      () {
        // Sits essentially on the boundary between slot 0 and slot 1.
        const boundary = Offset(56, 0);
        final withoutCurrent = resolve(
          sections: sections,
          draggedTopLeft: boundary,
        );
        final other = withoutCurrent == const InsertionCandidate(sectionId: 's', index: 0) ? const InsertionCandidate(sectionId: 's', index: 1) : const InsertionCandidate(sectionId: 's', index: 0);

        final held = resolve(
          sections: sections,
          draggedTopLeft: boundary,
          current: other,
        );
        expect(
          held,
          other,
          reason: 'the incumbent slot should survive a near tie',
        );
      },
    );

    test('yields the slot once a challenger is clearly closer', () {
      final candidate = resolve(
        sections: sections,
        draggedTopLeft: const Offset(0, 1000),
        current: const InsertionCandidate(sectionId: 's', index: 0),
      );
      expect(candidate, const InsertionCandidate(sectionId: 's', index: 2));
    });
  });

  group('multiple sections', () {
    final sections = [
      const SectionOrder(id: 'top', itemIds: ['a']),
      const SectionOrder(id: 'bottom', itemIds: ['b']),
    ];

    test('drags into the upper section when hovering it', () {
      final candidate = resolve(
        sections: sections,
        draggedTopLeft: Offset.zero,
      );
      expect(candidate!.sectionId, 'top');
    });

    test('drags into the lower section when hovering below it', () {
      final candidate = resolve(
        sections: sections,
        draggedTopLeft: const Offset(0, 200),
      );
      expect(candidate!.sectionId, 'bottom');
    });

    test('an empty section still offers its index-0 slot', () {
      final withEmptyTop = [
        const SectionOrder(id: 'top', itemIds: []),
        const SectionOrder(id: 'bottom', itemIds: ['b']),
      ];
      const chrome = [
        SectionChrome(id: 'top', headerHeight: 20, emptyExtent: 64),
        SectionChrome(id: 'bottom'),
      ];

      // Hovering inside the empty top section's reserved drop extent.
      final candidate = resolve(
        sections: withEmptyTop,
        chrome: chrome,
        draggedTopLeft: const Offset(0, 24),
      );

      expect(candidate, const InsertionCandidate(sectionId: 'top', index: 0));
    });

    test('accounts for header height when deciding the section', () {
      const chrome = [
        SectionChrome(id: 'top'),
        SectionChrome(id: 'bottom', headerHeight: 100),
      ];

      // Just under the top section's single 40px row, but the bottom section's
      // tall header pushes its first slot down to y=140.
      final candidate = resolve(
        sections: sections,
        chrome: chrome,
        draggedTopLeft: const Offset(0, 45),
      );

      expect(candidate!.sectionId, 'top');
    });
  });

  group('leadingCells', () {
    // With leadingCells: 1 at 2 columns, the resting layout is
    // a=(112,0), b=(0,48), c=(112,48) — column 0 of row 0 is blank.
    final sections = [
      const SectionOrder(id: 's', itemIds: ['a', 'b', 'c']),
    ];
    const chrome = [SectionChrome(id: 's', leadingCells: 1)];

    test(
      'hovering the leading blank cell picks the slot below it, not index 0',
      () {
        // Index 0 sits at the offset column (112, 0); index 1 wraps to (0, 48).
        final candidate = resolve(
          sections: sections,
          chrome: chrome,
          draggedTopLeft: Offset.zero,
        );
        expect(candidate, const InsertionCandidate(sectionId: 's', index: 1));
      },
    );

    test('hovering the offset first cell picks index 0', () {
      final candidate = resolve(
        sections: sections,
        chrome: chrome,
        draggedTopLeft: const Offset(112, 0),
      );
      expect(candidate, const InsertionCandidate(sectionId: 's', index: 0));
    });

    test('leadingCells beyond the column count normalizes', () {
      // 3 mod 2 == 1: identical to the plain offset-1 case.
      const wrapped = [SectionChrome(id: 's', leadingCells: 3)];
      final candidate = resolve(
        sections: sections,
        chrome: wrapped,
        draggedTopLeft: Offset.zero,
      );
      expect(candidate, const InsertionCandidate(sectionId: 's', index: 1));
    });

    test(
      'an empty section with a dormant offset still offers its index-0 slot',
      () {
        final withEmptyTop = [
          const SectionOrder(id: 'top', itemIds: []),
          const SectionOrder(id: 'bottom', itemIds: ['b']),
        ];
        const offsetChrome = [
          SectionChrome(id: 'top', emptyExtent: 64, leadingCells: 1),
          SectionChrome(id: 'bottom'),
        ];

        final candidate = resolve(
          sections: withEmptyTop,
          chrome: offsetChrome,
          draggedTopLeft: const Offset(112, 8),
        );

        expect(candidate, const InsertionCandidate(sectionId: 'top', index: 0));
      },
    );
  });
}
