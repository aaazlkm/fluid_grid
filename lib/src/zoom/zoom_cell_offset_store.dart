/// Per-column-count leading-cell offsets for the photos zoom's iOS-style grid
/// re-anchoring.
///
/// iOS Photos does not return the pinched photo to its canonical column: the
/// incoming layout is the canonical layout offset by an integer number of
/// cells so the anchor lands in the cell nearest the fingers, and that offset
/// PERSISTS in the resting layout. This store holds those offsets, keyed by
/// column count so a morph's two endpoints each read their own alignment:
///
/// - At rest exactly one count's entry exists (the committed one).
/// - During a morph the entering endpoint's count gets a freshly chosen offset
///   (see the coordinator's delta chooser); the outgoing endpoint keeps its
///   stored entry, so the morph starts snap-free.
/// - On settle, [commit] drops every other count's entry — the committed
///   offset becomes the new resting alignment. Because offsets are re-derived
///   per count and normalized by the solver, a stale "offset 4" can never leak
///   into a 3-column layout.
///
/// Owned by the coordinator and shared (by identity) with both render objects,
/// which stamp the offsets into their solver specs. Mutations are picked up on
/// the next layout — every mutation site already invalidates layout.
class ZoomCellOffsetStore {
  final Map<int, Map<Object, int>> _byCount = {};

  /// The per-section offsets for [count]; empty (canonical) when none stored.
  Map<Object, int> forCount(int count) => _byCount[count] ?? const {};

  /// The offset of [sectionId] at [count]; 0 (canonical) when none stored.
  int of(int count, Object sectionId) => _byCount[count]?[sectionId] ?? 0;

  /// Whether [count] has been assigned an alignment (canonical counts as
  /// assigned) since the last commit/clear that dropped it. Lets the
  /// coordinator tell a first entry into the morph pair from a RE-entry after
  /// an intra-frame zoom flap — a re-entering count must keep its alignment.
  bool contains(int count) => _byCount.containsKey(count);

  /// Whether any count carries a stored alignment.
  bool get isEmpty => _byCount.isEmpty;

  /// Assigns one [delta] to every section in [sectionIds] at [count] —
  /// broadcasting a single delta is what keeps all sections mutually aligned,
  /// matching the iOS behavior.
  void assignUniform(int count, int delta, Iterable<Object> sectionIds) {
    _byCount[count] = {for (final id in sectionIds) id: delta};
  }

  /// Stores canonical alignment (no offsets) for [count]. The count still
  /// [contains] an entry afterwards — canonical is an assignment, not an
  /// absence.
  void assignCanonical(int count) {
    _byCount[count] = {};
  }

  /// Settles on [count]: its entry becomes the only resting alignment and
  /// every other count's tentative entry is dropped.
  void commit(int count) {
    _byCount.removeWhere((key, value) => key != count);
  }

  /// Drops offsets of sections that left the data.
  ///
  /// A count whose offsets all belonged to departed sections is pruned
  /// entirely (its alignment referenced nothing that survives). Canonical
  /// assignments — stored as an empty map by [assignCanonical] — are section
  /// agnostic and are KEPT, so [contains] stays true for them across a
  /// reconcile and a re-entering canonical count is not treated as new.
  void retainSections(bool Function(Object sectionId) keep) {
    _byCount.removeWhere((count, offsets) {
      if (offsets.isEmpty) return false; // canonical assignment — preserve.
      offsets.removeWhere((sectionId, offset) => !keep(sectionId));
      return offsets.isEmpty; // every section left — the alignment is stale.
    });
  }

  /// Forgets everything (e.g. when the allowed zoom levels change at rest).
  void clear() => _byCount.clear();
}
