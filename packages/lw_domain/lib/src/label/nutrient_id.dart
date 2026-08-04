/// The nutrients the system understands.
///
/// A **closed, typed set**. Adding a member is a deliberate code change, not a
/// rule pack edit (ADR-0014). The set FSSAI mandates is small, stable and
/// legally defined; it changes on a regulatory timescale of years, not a
/// contribution timescale of days. A stringly-typed domain would pay a cost on
/// every line, forever, to buy flexibility on an axis that barely moves.
///
/// Only sodium is modelled, never salt. Some labels print salt and
/// `salt ≈ sodium × 2.5` is approximate, so a label declaring salt is converted
/// at parse time and marked derived. Two first-class nutrients for one quantity
/// would create two sources of truth and invite a rule that fires twice.
enum NutrientId {
  /// Energy content.
  energy(isCritical: true),

  /// Protein.
  protein(isCritical: true),

  /// Total carbohydrate.
  carbohydrate(isCritical: true),

  /// Total sugars, including those naturally present.
  totalSugars(isCritical: true),

  /// Sugars added during manufacture.
  addedSugars(isCritical: true),

  /// Dietary fibre.
  dietaryFibre(isCritical: false),

  /// Total fat.
  totalFat(isCritical: true),

  /// Saturated fat.
  saturatedFat(isCritical: true),

  /// Trans fat. Commonly declared as a bound, such as `< 0.5 g`.
  transFat(isCritical: true),

  /// Monounsaturated fat.
  monounsaturatedFat(isCritical: false),

  /// Polyunsaturated fat.
  polyunsaturatedFat(isCritical: false),

  /// Cholesterol.
  cholesterol(isCritical: false),

  /// Sodium.
  sodium(isCritical: true);

  /// Defines whether this nutrient is a critical field.
  const NutrientId({required this.isCritical});

  /// Whether an incorrect extraction of this nutrient materially misleads the
  /// user.
  ///
  /// Critical fields form the denominator of the accuracy metrics in
  /// `TEST_STRATEGY.md` §4.4. The serving descriptors — serving size, servings
  /// per pack and net quantity — are also critical but are not nutrients, so
  /// they are modelled separately.
  final bool isCritical;

  /// The critical nutrients, in declaration order.
  static List<NutrientId> get critical =>
      values.where((NutrientId n) => n.isCritical).toList(growable: false);
}
