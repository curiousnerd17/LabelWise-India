import 'package:lw_domain/src/label/dimension.dart';

/// A unit of measurement, with its tracked precision.
///
/// **Scale is a property of the unit, never of a value** (ADR-0021). Carrying
/// scale on each quantity permitted two same-unit values with different
/// scales — an illegal state whose failure mode was a silently wrong
/// comparison.
///
/// Scales are deliberately one or two orders finer than any label declares, so
/// that intermediate arithmetic (per-100 g → per-serve → per-pack) does not
/// accumulate rounding error before the single rounding step at presentation.
/// `DATA_MODEL.md` §2.3.
enum Unit {
  /// Grams. Tracked to 0.01 g.
  gram(
    symbol: 'g',
    dimension: Dimension.mass,
    scale: 100,
    baseUnitsPerIncrement: 10000,
  ),

  /// Milligrams. Tracked to 0.1 mg.
  milligram(
    symbol: 'mg',
    dimension: Dimension.mass,
    scale: 10,
    baseUnitsPerIncrement: 100,
  ),

  /// Micrograms. Tracked to 1 µg — the base unit of mass.
  microgram(
    symbol: 'µg',
    dimension: Dimension.mass,
    scale: 1,
    baseUnitsPerIncrement: 1,
  ),

  /// Millilitres. Tracked to 0.1 ml.
  millilitre(
    symbol: 'ml',
    dimension: Dimension.volume,
    scale: 10,
    baseUnitsPerIncrement: 100,
  ),

  /// Kilocalories. Tracked to 0.1 kcal.
  ///
  /// One increment is 0.1 kcal = 418 400 millijoules, using the thermochemical
  /// calorie (1 kcal = 4.184 kJ exactly). The integer relationship is what
  /// makes kcal/kJ comparison exact in base units.
  kilocalorie(
    symbol: 'kcal',
    dimension: Dimension.energy,
    scale: 10,
    baseUnitsPerIncrement: 418400,
  ),

  /// Kilojoules. Tracked to 0.1 kJ, i.e. 100 000 millijoules per increment.
  kilojoule(
    symbol: 'kJ',
    dimension: Dimension.energy,
    scale: 10,
    baseUnitsPerIncrement: 100000,
  ),

  /// Percentage of a reference value. Tracked to 0.1 %.
  percent(
    symbol: '%',
    dimension: Dimension.proportion,
    scale: 10,
    baseUnitsPerIncrement: 1,
  ),

  /// A dimensionless count, such as servings per pack. Tracked to 0.01.
  count(
    symbol: '',
    dimension: Dimension.count,
    scale: 100,
    baseUnitsPerIncrement: 1,
  );

  /// Defines a unit's symbol, dimension and tracked precision.
  const Unit({
    required this.symbol,
    required this.dimension,
    required this.scale,
    required this.baseUnitsPerIncrement,
  });

  /// The canonical printed symbol for this unit.
  final String symbol;

  /// The dimension this unit measures. Conversion is closed within it.
  final Dimension dimension;

  /// Increments per whole unit. A scale of 100 tracks hundredths.
  final int scale;

  /// This unit's smallest tracked increment, expressed in the dimension's base
  /// unit (micrograms for mass, microlitres for volume, millijoules for
  /// energy).
  ///
  /// Comparison and conversion operate in base units so that they are exact for
  /// every pair of units in a dimension, including kcal against kJ.
  final int baseUnitsPerIncrement;

  /// Whether [other] measures the same dimension, and so is convertible.
  bool isConvertibleTo(Unit other) => dimension == other.dimension;

  /// The finer of this unit and [other] — the one whose increment is smaller.
  ///
  /// Throws [ArgumentError] if the units measure different dimensions, which is
  /// a programming error rather than an expected condition.
  Unit finerOf(Unit other) {
    if (!isConvertibleTo(other)) {
      throw ArgumentError(
        'Cannot compare $name with ${other.name}: '
        'different dimensions ($dimension vs ${other.dimension}).',
      );
    }
    return baseUnitsPerIncrement <= other.baseUnitsPerIncrement ? this : other;
  }
}
