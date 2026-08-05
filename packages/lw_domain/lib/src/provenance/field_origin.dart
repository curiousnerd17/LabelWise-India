/// How a field's value came to exist.
///
/// Origin determines **how confidence is obtained**, not what it is
/// (`DATA_MODEL.md` §3.2).
enum FieldOrigin {
  /// Read from the label by the parser. Confidence is computed from the
  /// S1/S2/S3 signals.
  extracted,

  /// Computed from other fields. Confidence is the meet of its inputs,
  /// possibly downgraded when the derivation is itself approximate.
  derived,

  /// Entered or corrected by the user.
  ///
  /// Carries **no inferred confidence** (FR-CNF-12). It is not a level on the
  /// lattice but a different kind of thing: the user has looked at the packet,
  /// which the parser cannot do.
  userSupplied,
}
