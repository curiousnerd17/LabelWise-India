/// How precisely a declared value should be read.
///
/// A quantity denotes an **interval, not a point** (ADR-0027). Indian labels
/// routinely print `< 0.5 g` for trans fat and `About 4 servings` for pack
/// counts; both are declarations, and neither is a point value.
///
/// The qualifier is part of the value, not metadata beside it. Separating them
/// would guarantee a call site that compares the number and forgets the
/// qualifier.
enum Qualifier {
  /// The declared value, denoting `[v, v]`. The default.
  ///
  /// **Canonical serialised form: omit this qualifier entirely** (ADR-0027
  /// decision 5). Reading an absent qualifier yields [exact]; writing it
  /// explicitly is invalid output, not a stylistic variant, because
  /// byte-different output for identical data breaks the rule pack integrity
  /// hash, FR-PAR-02 determinism, and golden-corpus comparison.
  exact,

  /// Declared below a bound, denoting `[0, v)`. Lower bound zero by INV-01.
  ///
  /// **Domain assumption.** The zero lower bound holds because every nutrition
  /// quantity is non-negative (INV-01). It is correct for food labels and is
  /// accepted as such.
  ///
  /// It is **not** universal. Should the rule engine ever expand to a domain
  /// admitting negative quantities — Stage 3 covers cosmetics, supplements and
  /// medicines, and a future domain might carry temperatures or offsets — this
  /// bound becomes wrong, and silently so: `< -5` would be modelled as
  /// `[0, -5)`, an empty interval that makes every comparison indeterminate
  /// rather than raising anything. Revisit through a new ADR before that
  /// happens, not after.
  lessThan,

  /// Declared above a bound, denoting `(v, ∞)`.
  greaterThan,

  /// The manufacturer explicitly declines precision, denoting `[v−δ, v+δ]`.
  ///
  /// The half-width δ is rule pack data, supplied as `ApproximationDeltas`.
  approximately,
}
