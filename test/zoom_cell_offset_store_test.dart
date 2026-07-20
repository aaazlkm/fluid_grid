import 'package:fluid_grid/src/zoom/zoom_cell_offset_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts canonical everywhere', () {
    final store = ZoomCellOffsetStore();
    expect(store.isEmpty, isTrue);
    expect(store.forCount(3), isEmpty);
    expect(store.of(3, 's'), 0);
  });

  test('assignUniform broadcasts one delta to every section at one count', () {
    final store = ZoomCellOffsetStore()..assignUniform(5, 2, ['a', 'b']);
    expect(store.of(5, 'a'), 2);
    expect(store.of(5, 'b'), 2);
    expect(store.of(5, 'c'), 0, reason: 'unknown sections read canonical');
    expect(store.of(3, 'a'), 0, reason: 'other counts stay canonical');
  });

  test('commit keeps only the settled count', () {
    final store = ZoomCellOffsetStore()
      ..assignUniform(3, 1, ['s'])
      ..assignUniform(5, 4, ['s'])
      ..commit(5);
    expect(store.of(5, 's'), 4);
    expect(
      store.of(3, 's'),
      0,
      reason: 'the tentative endpoint entry is dropped',
    );
  });

  test('assignCanonical clears one count without touching others', () {
    final store = ZoomCellOffsetStore()
      ..assignUniform(3, 1, ['s'])
      ..assignUniform(5, 2, ['s'])
      ..assignCanonical(3);
    expect(store.of(3, 's'), 0);
    expect(store.of(5, 's'), 2);
  });

  test('retainSections drops departed sections and empty counts', () {
    final store = ZoomCellOffsetStore()
      ..assignUniform(5, 2, ['a', 'b'])
      ..retainSections((id) => id == 'a');
    expect(store.of(5, 'a'), 2);
    expect(store.of(5, 'b'), 0);

    store.retainSections((id) => false);
    expect(store.isEmpty, isTrue);
  });

  test('clear forgets everything', () {
    final store = ZoomCellOffsetStore()
      ..assignUniform(5, 2, ['a'])
      ..clear();
    expect(store.isEmpty, isTrue);
  });
}
