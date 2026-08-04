/// The result of comparing two intervals.
///
/// Comparison of qualified quantities is three-valued, not boolean: overlapping
/// declarations may simply not settle the question (ADR-0027).
///
/// [indeterminate] is **not** a failure. It records that the label declared a
/// bound and the comparison cannot conclude — which is different from the
/// comparison concluding negatively, and must never be conflated with it.
enum Trilean {
  /// The comparison holds for every value in both intervals.
  definitelyTrue,

  /// The comparison holds for no value in either interval.
  definitelyFalse,

  /// The intervals overlap; the declarations do not settle the comparison.
  indeterminate;

  /// The logical negation, exchanging the two definite outcomes and leaving
  /// [indeterminate] unchanged.
  Trilean get negated => switch (this) {
        Trilean.definitelyTrue => Trilean.definitelyFalse,
        Trilean.definitelyFalse => Trilean.definitelyTrue,
        Trilean.indeterminate => Trilean.indeterminate,
      };
}
