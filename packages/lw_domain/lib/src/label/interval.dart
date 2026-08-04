import 'package:lw_domain/src/label/trilean.dart';

/// A closed-or-open interval over the base units of a dimension.
///
/// Produced by `Quantity.boundsIn` and consumed by comparison. Expressed in
/// base units (micrograms, microlitres, millijoules) so that comparison is
/// exact for every pair of units in a dimension, including kilocalories
/// against kilojoules.
///
/// A null [supremum] denotes an unbounded upper end, as `GREATER_THAN`
/// requires.
final class Interval {
  /// Creates an interval from its bounds in base units.
  const Interval({
    required this.infimum,
    required this.infimumInclusive,
    required this.supremum,
    required this.supremumInclusive,
  });

  /// A degenerate interval containing exactly [point].
  const Interval.point(int point)
      : infimum = point,
        infimumInclusive = true,
        supremum = point,
        supremumInclusive = true;

  /// Lower bound, in base units.
  final int infimum;

  /// Whether [infimum] is itself a member of the interval.
  final bool infimumInclusive;

  /// Upper bound in base units, or null when the interval is unbounded above.
  final int? supremum;

  /// Whether [supremum] is itself a member of the interval. Always false when
  /// [supremum] is null.
  final bool supremumInclusive;

  /// Whether this interval contains exactly one value.
  bool get isPoint =>
      supremum != null &&
      infimum == supremum &&
      infimumInclusive &&
      supremumInclusive;

  /// Whether every value in this interval is at most every value in [other].
  ///
  /// Three-valued, because overlapping declarations need not settle the
  /// question (ADR-0027).
  ///
  /// - Definitely true when `sup(this) ≤ inf(other)`. A shared endpoint still
  ///   satisfies `x ≤ y`, so inclusivity does not matter here.
  /// - Definitely false when `inf(this) > sup(other)`, or when the endpoints
  ///   are shared and at least one is exclusive — which forces `x > y`.
  /// - Indeterminate otherwise.
  Trilean isAtMost(Interval other) {
    final int? thisSupremum = supremum;
    if (thisSupremum != null && thisSupremum <= other.infimum) {
      return Trilean.definitelyTrue;
    }

    final int? otherSupremum = other.supremum;
    if (otherSupremum != null) {
      if (infimum > otherSupremum) {
        return Trilean.definitelyFalse;
      }
      final bool endpointsMeet = infimum == otherSupremum;
      final bool oneEndpointExclusive =
          !infimumInclusive || !other.supremumInclusive;
      if (endpointsMeet && oneEndpointExclusive) {
        return Trilean.definitelyFalse;
      }
    }

    return Trilean.indeterminate;
  }

  /// Whether every value in this interval is at least every value in [other].
  Trilean isAtLeast(Interval other) => other.isAtMost(this);
}
