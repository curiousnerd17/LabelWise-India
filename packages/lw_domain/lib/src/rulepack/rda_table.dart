import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/rulepack/pack_ids.dart';

/// One gazetted daily-value denominator.
///
/// `DATA_MODEL.md` §7.5. Held as data rather than as a Dart constant because
/// these are **regulation, and regulation changes** (A5, R5) — and because
/// NFR-MNT-06 makes a denominator appearing as a literal in Dart a violation
/// rather than a shortcut.
final class RdaDenominator {
  /// Records a denominator.
  RdaDenominator({
    required this.constantId,
    required this.nutrient,
    required this.value,
    required List<SourceId> sourceRefs,
  }) : sourceRefs = List<SourceId>.unmodifiable(sourceRefs) {
    if (sourceRefs.isEmpty) {
      throw ArgumentError.value(
        constantId.value,
        'sourceRefs',
        'A gazetted constant with no citation is indistinguishable from a '
            'number somebody remembered.',
      );
    }
  }

  /// Stable key, such as `const.rda.sodium`.
  final ConstantId constantId;

  /// The nutrient this denominator divides.
  final NutrientId nutrient;

  /// The daily value, as a scaled-integer quantity.
  final Quantity value;

  /// Where the figure comes from. Never empty.
  final List<SourceId> sourceRefs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RdaDenominator &&
          constantId == other.constantId &&
          nutrient == other.nutrient &&
          value == other.value &&
          _sameRefs(other.sourceRefs);

  bool _sameRefs(List<SourceId> other) {
    if (sourceRefs.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (sourceRefs[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        constantId,
        nutrient,
        value,
        Object.hashAll(sourceRefs),
      );

  @override
  String toString() => 'RdaDenominator(${nutrient.name} = $value)';
}

/// The FSSAI daily-value denominators (FR-L1-04).
///
/// **This table holds the numbers; it performs no arithmetic.** Percent-RDA is
/// Layer 1 work and is not part of this milestone.
final class RdaTable {
  /// Records the table, indexing by nutrient.
  ///
  /// Throws [ArgumentError] when two denominators claim the same nutrient. Two
  /// values for one divisor is not a preference to resolve; it is a pack defect
  /// that would make every percentage silently depend on ordering.
  RdaTable(List<RdaDenominator> denominators)
      : denominators = List<RdaDenominator>.unmodifiable(denominators),
        _byNutrient = _index(denominators);

  static Map<NutrientId, RdaDenominator> _index(
    List<RdaDenominator> denominators,
  ) {
    final Map<NutrientId, RdaDenominator> index =
        <NutrientId, RdaDenominator>{};
    for (final RdaDenominator d in denominators) {
      if (index.containsKey(d.nutrient)) {
        throw ArgumentError.value(
          d.nutrient.name,
          'denominators',
          'Duplicate denominator for this nutrient.',
        );
      }
      index[d.nutrient] = d;
    }
    return index;
  }

  /// Every denominator, in pack order.
  final List<RdaDenominator> denominators;

  final Map<NutrientId, RdaDenominator> _byNutrient;

  /// The denominator for [nutrient], or null when the pack declares none.
  ///
  /// Null is expected and correct for the seven nutrients FSSAI sets no daily
  /// value for. Layer 1 reports "no daily value is gazetted for this nutrient",
  /// which is a different statement from "this nutrient is absent" — FR-ERR-03
  /// again, one level up.
  RdaDenominator? operator [](NutrientId nutrient) => _byNutrient[nutrient];

  /// Whether [nutrient] has a gazetted denominator.
  bool contains(NutrientId nutrient) => _byNutrient.containsKey(nutrient);

  /// How many denominators the pack declares.
  int get length => denominators.length;

  @override
  String toString() => 'RdaTable(${denominators.length} denominators)';
}
