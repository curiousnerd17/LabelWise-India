/// The arithmetic checks S7 evaluates — confidence signal **S3**.
///
/// Exactly the ten named in `REQUIREMENTS.md` §5.3. Per ADR-0010 these are the
/// **primary** confidence signal, ahead of parse strength and OCR confidence:
/// an engine that is confidently wrong about a `3` it read as an `8` reports
/// high character confidence, and only the arithmetic catches it.
///
/// A closed set. A stringly-typed identifier would let a rule reference an
/// invariant that does not exist and surface as a runtime failure instead of a
/// build failure (ADR-0014's reasoning, applied here).
enum InvariantId {
  /// All declared values ≥ 0.
  inv01(code: 'INV-01', basisScoped: true),

  /// `saturatedFat` ≤ `totalFat`.
  inv02(code: 'INV-02', basisScoped: true),

  /// `transFat` ≤ `totalFat`.
  inv03(code: 'INV-03', basisScoped: true),

  /// `addedSugars` ≤ `totalSugars`.
  inv04(code: 'INV-04', basisScoped: true),

  /// `totalSugars` ≤ `carbohydrate`.
  inv05(code: 'INV-05', basisScoped: true),

  /// `protein + carbohydrate + totalFat` ≤ 100 g per 100 g.
  inv06(code: 'INV-06', basisScoped: true),

  /// Declared energy reconciles with the Atwater estimate.
  inv07(code: 'INV-07', basisScoped: true),

  /// `perServe` ≈ `per100g` × (`servingSize` ÷ 100).
  inv08(code: 'INV-08', basisScoped: true),

  /// `servingSize` ≤ `netQuantity`.
  inv09(code: 'INV-09', basisScoped: false),

  /// `servingsPerPack` ≈ `netQuantity` ÷ `servingSize`.
  inv10(code: 'INV-10', basisScoped: false);

  /// Defines an invariant's code and scope.
  const InvariantId({required this.code, required this.basisScoped});

  /// The identifier as `REQUIREMENTS.md` §5.3 and the rule pack write it.
  final String code;

  /// Whether this check is evaluated once per declared basis.
  ///
  /// False for INV-09 and INV-10: a serving count reconciling against net
  /// quantity is one fact about the pack, not a fact about a column. Every
  /// other check compares figures within a single column, and a panel
  /// declaring both per-100 g and per-serve produces one result per basis
  /// (`DATA_MODEL.md` §4.3, v1.5).
  final bool basisScoped;
}
