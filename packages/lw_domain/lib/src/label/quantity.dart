import 'package:lw_domain/src/label/approximation_deltas.dart';
import 'package:lw_domain/src/label/interval.dart';
import 'package:lw_domain/src/label/qualifier.dart';
import 'package:lw_domain/src/label/rounding.dart';
import 'package:lw_domain/src/label/trilean.dart';
import 'package:lw_domain/src/label/unit.dart';

/// A declared quantity: a scaled integer, a unit, and a qualifier.
///
/// Values are **scaled integers, never doubles** (`DATA_MODEL.md` §2.1).
/// Doubles make `0.1 + 0.2 ≠ 0.3`, make equality unreliable, and turn
/// golden-corpus
/// assertions into noise that engineers learn to suppress — which is how a real
/// regression eventually gets suppressed alongside it.
///
/// A quantity denotes an **interval, not a point** (ADR-0027). It therefore
/// deliberately provides **no ordering operators and no [Comparable]
/// implementation**. There is no `<`, `>`, `<=`, `>=` or `compareTo`, because
/// every one of them would silently coerce a bound to a point value — the
/// failure MI-16 forbids. `< 0.5 g` and `< 0.6 g` genuinely cannot be ranked.
///
/// Comparison goes through [isAtMost], which returns a [Trilean] and cannot
/// pretend a straddling interval settled the question.
final class Quantity {
  const Quantity._(this.scaledValue, this.unit, this.qualifier);

  /// A quantity declared exactly, such as `2.5 g` printed as `2.5 g`.
  ///
  /// [scaledValue] is expressed in the unit's increments: `Quantity.exact(250,
  /// Unit.gram)` is 2.50 g, because [Unit.gram] tracks hundredths.
  const Quantity.exact(int scaledValue, Unit unit)
      : this._(scaledValue, unit, Qualifier.exact);

  /// A quantity declared below a bound, such as `< 0.5 g` for trans fat.
  const Quantity.lessThan(int scaledValue, Unit unit)
      : this._(scaledValue, unit, Qualifier.lessThan);

  /// A quantity declared above a bound.
  const Quantity.greaterThan(int scaledValue, Unit unit)
      : this._(scaledValue, unit, Qualifier.greaterThan);

  /// A quantity the manufacturer declared approximately, such as
  /// `About 4 servings`.
  const Quantity.approximately(int scaledValue, Unit unit)
      : this._(scaledValue, unit, Qualifier.approximately);

  /// A quantity with an explicitly supplied [qualifier].
  ///
  /// Prefer the named constructors; this exists for deserialisation, where the
  /// qualifier arrives as data.
  const Quantity.qualified(int scaledValue, Unit unit, Qualifier qualifier)
      : this._(scaledValue, unit, qualifier);

  /// The declared number, in increments of [unit].
  ///
  /// This is the value as printed on the label. It is **not** a point value:
  /// interpreting it without consulting [qualifier] is the coercion MI-16
  /// forbids. Use [boundsIn] for comparison and [isAtMost] for ordering.
  final int scaledValue;

  /// The unit of measurement, which also fixes the tracked precision.
  final Unit unit;

  /// How precisely the declared value should be read.
  final Qualifier qualifier;

  /// The declared number expressed in the dimension's base units.
  ///
  /// Exact for every unit, which is what makes cross-unit comparison — notably
  /// kilocalories against kilojoules — lossless.
  int get baseUnits => scaledValue * unit.baseUnitsPerIncrement;

  /// The interval this quantity denotes, in base units.
  ///
  /// [deltas] is consulted only for [Qualifier.approximately]; pass
  /// [ApproximationDeltas.none] when no approximate value is involved.
  Interval boundsIn(ApproximationDeltas deltas) {
    final int value = baseUnits;
    return switch (qualifier) {
      // A switch expression, so exhaustiveness is a compile-time guarantee.
      // Adding a qualifier without handling it here will not build.
      Qualifier.exact => Interval.point(value),

      // [0, v) — lower bound zero by INV-01, upper bound exclusive.
      Qualifier.lessThan => Interval(
          infimum: 0,
          infimumInclusive: true,
          supremum: value,
          supremumInclusive: false,
        ),

      // (v, infinity) — unbounded above.
      Qualifier.greaterThan => Interval(
          infimum: value,
          infimumInclusive: false,
          supremum: null,
          supremumInclusive: false,
        ),
      Qualifier.approximately => _approximateBounds(value, deltas),
    };
  }

  Interval _approximateBounds(int value, ApproximationDeltas deltas) {
    final int delta = deltas.deltaFor(unit) * unit.baseUnitsPerIncrement;
    return Interval(
      infimum: value - delta,
      infimumInclusive: true,
      supremum: value + delta,
      supremumInclusive: true,
    );
  }

  /// Whether this quantity is at most [other], as far as the declarations
  /// settle it.
  ///
  /// Returns [Trilean.indeterminate] when the intervals overlap — for example
  /// `< 0.6 g` against a threshold of `0.5 g`. That outcome is reported, never
  /// resolved by assuming a point value.
  ///
  /// Throws [ArgumentError] when the units measure different dimensions.
  Trilean isAtMost(Quantity other, ApproximationDeltas deltas) {
    if (!unit.isConvertibleTo(other.unit)) {
      throw ArgumentError(
        'Cannot compare ${unit.name} with ${other.unit.name}: '
        'different dimensions.',
      );
    }
    return boundsIn(deltas).isAtMost(other.boundsIn(deltas));
  }

  /// Whether this quantity is at least [other], as far as the declarations
  /// settle it.
  Trilean isAtLeast(Quantity other, ApproximationDeltas deltas) =>
      other.isAtMost(this, deltas);

  /// This quantity expressed in [target].
  ///
  /// Converting to a finer unit is lossless. Converting to a coarser one rounds
  /// to the target's tracked precision under the single rounding policy — which
  /// is the intended meaning of scale, not a defect.
  ///
  /// Energy conversion between kilocalories and kilojoules uses the
  /// thermochemical calorie and rounds once, here. Recording that a conversion
  /// occurred is the caller's responsibility, because provenance belongs to the
  /// pipeline stage, not to the value.
  ///
  /// Throws [ArgumentError] when [target] measures a different dimension.
  Quantity convertTo(Unit target) {
    if (!unit.isConvertibleTo(target)) {
      throw ArgumentError(
        'Cannot convert ${unit.name} to ${target.name}: different dimensions.',
      );
    }
    if (target == unit) {
      return this;
    }
    final int converted =
        divideRounded(baseUnits, target.baseUnitsPerIncrement);
    return Quantity._(converted, target, qualifier);
  }

  /// This quantity scaled by the positive ratio [numerator] / [denominator].
  ///
  /// Used for basis changes: per-100 g to per-serve is a scale by
  /// `servingSize / 100`. **Scaling by a positive constant preserves the bound
  /// direction**, so `< 0.5 g` per 100 g becomes `< 1.0 g` for a 200 g pack.
  ///
  /// Only positive ratios are permitted; a negative or zero scale would invert
  /// or collapse a bound, which no basis change ever does. Throws
  /// [ArgumentError] otherwise.
  Quantity scaledBy({required int numerator, required int denominator}) {
    if (numerator <= 0 || denominator <= 0) {
      throw ArgumentError(
        'Scale ratio must be positive; got $numerator/$denominator. '
        'A non-positive ratio would invert or collapse a declared bound.',
      );
    }
    return Quantity._(
      divideRounded(scaledValue * numerator, denominator),
      unit,
      qualifier,
    );
  }

  /// Equality includes the qualifier (ADR-0027, MI-14).
  ///
  /// `LESS_THAN 0.5 g` is not equal to `EXACT 0.5 g`. They are different
  /// declarations, and a parser that confuses them records an Error rather than
  /// a near-miss (`TEST_STRATEGY.md` §4.2).
  ///
  /// Values in different units are not equal even when they denote the same
  /// magnitude: `2.5 g` and `2500 mg` are equal only after explicit
  /// normalisation, which is a measured parser behaviour.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Quantity &&
          scaledValue == other.scaledValue &&
          unit == other.unit &&
          qualifier == other.qualifier;

  @override
  int get hashCode => Object.hash(scaledValue, unit, qualifier);

  /// A **debugging representation only. Never show this to a user.**
  ///
  /// It is not localised, not localisable, and not a display format.
  /// User-facing text resolves through message IDs in the message catalogue
  /// (FR-LOC-01,
  /// FR-LOC-05, M5); the domain holds identity, never content.
  ///
  /// The type name is deliberately kept in the output so that a leak into the
  /// UI looks obviously wrong on screen rather than passing for a formatted
  /// value. Making the wrong thing look wrong is a cheaper guard than a comment
  /// nobody reads.
  @override
  String toString() {
    final String magnitude = _formatMagnitude();
    final String suffix = unit.symbol.isEmpty ? '' : ' ${unit.symbol}';
    final String body = switch (qualifier) {
      Qualifier.exact => '$magnitude$suffix',
      Qualifier.lessThan => '< $magnitude$suffix',
      Qualifier.greaterThan => '> $magnitude$suffix',
      Qualifier.approximately => '~ $magnitude$suffix',
    };
    return 'Quantity($body)';
  }

  String _formatMagnitude() {
    if (unit.scale == 1) {
      return '$scaledValue';
    }
    final int whole = scaledValue ~/ unit.scale;
    final int fraction = scaledValue.remainder(unit.scale).abs();
    final int digits = unit.scale.toString().length - 1;
    return '$whole.${fraction.toString().padLeft(digits, '0')}';
  }
}
