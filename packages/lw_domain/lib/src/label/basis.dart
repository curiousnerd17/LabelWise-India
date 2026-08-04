/// The reference quantity a nutrient value is expressed against.
///
/// A value without a basis is not interpretable, so basis is required
/// wherever a nutrient value appears — never optional, never defaulted
/// (FR-PAR-04,
/// FR-PAR-05, MI-03).
///
/// A right value on the wrong basis is wrong, usually by a factor of three or
/// more, which is why the accuracy comparator treats basis as an exact match
/// (`TEST_STRATEGY.md` §4.2).
enum Basis {
  /// Per 100 grams.
  per100g,

  /// Per 100 millilitres.
  per100ml,

  /// Per the manufacturer-declared serving. Manufacturer-chosen, not
  /// standardised — which is why serving-size reconciliation exists.
  perServe,

  /// Per the whole declared net quantity.
  perPack,
}
