/// The physical dimension measured by a unit.
///
/// Conversion is closed within a dimension: a mass may become another mass, but
/// never a volume. `DATA_MODEL.md` §2.3.
///
/// [proportion] and [count] are deliberately distinct rather than a shared
/// "dimensionless" dimension. A percentage is not a serving count, and giving
/// them one dimension would make that conversion legal.
enum Dimension {
  /// Mass — grams, milligrams, micrograms.
  mass,

  /// Volume — millilitres.
  volume,

  /// Energy — kilocalories, kilojoules.
  energy,

  /// A proportion of a reference value, as a percentage.
  proportion,

  /// A dimensionless count, such as servings per pack.
  count,
}
