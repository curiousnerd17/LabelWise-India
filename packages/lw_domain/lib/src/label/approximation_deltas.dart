import 'package:lw_domain/src/label/unit.dart';

/// Per-unit half-widths for the interval denoted by `Qualifier.approximately`.
///
/// Held as rule pack data rather than a constant (P10, ADR-0027), so the values
/// are tunable from corpus calibration without a code change. Infrastructure
/// builds this from `rulepack/rules/confidence.json`; the domain only consumes
/// it.
///
/// This is also why `APPROXIMATELY` widens INV-10's effective tolerance without
/// a special case: the interval simply is wider.
final class ApproximationDeltas {
  /// Creates a delta table from a per-unit map of increment half-widths.
  ///
  /// Each value is expressed in that unit's own increments, so a delta of 50
  /// for [Unit.count] (scale 100) means ±0.5 servings.
  const ApproximationDeltas(Map<Unit, int> deltasByUnit)
      : _deltasByUnit = deltasByUnit;

  /// A table with no entries.
  ///
  /// Sufficient wherever no `APPROXIMATELY` value is involved. Requesting a
  /// delta from it throws, which is correct: an approximate value whose delta
  /// has not been supplied cannot be bounded, and guessing one would invent
  /// precision the rule pack did not authorise.
  static const ApproximationDeltas none = ApproximationDeltas(<Unit, int>{});

  final Map<Unit, int> _deltasByUnit;

  /// The half-width for [unit], in that unit's increments.
  ///
  /// Throws [StateError] when no delta is configured. This is a programming
  /// error — the caller must resolve deltas from the rule pack before bounding
  /// an approximate quantity — not an expected condition.
  int deltaFor(Unit unit) {
    final int? delta = _deltasByUnit[unit];
    if (delta == null) {
      throw StateError(
        'No approximation delta configured for ${unit.name}. '
        'Approximate quantities cannot be bounded without one; supply the '
        'rule pack value rather than assuming a default.',
      );
    }
    return delta;
  }

  /// Whether a delta is configured for [unit].
  bool hasDeltaFor(Unit unit) => _deltasByUnit.containsKey(unit);
}
