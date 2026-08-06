/// The identity of a product category in the rule pack.
///
/// **Deliberately not an enum.** FR-CAT-03 requires that adding support for a
/// new category be a rule pack change and nothing else: *"Adding support for a
/// new category MUST require changes to rule pack data only — no Dart source
/// modification."* An enum would force a code change for every category the
/// pack gains, which is exactly the coupling ADR-0013 exists to prevent — and
/// which the fifth-category verification (FR-CAT-06) is designed to catch.
///
/// Built like `RuleId`: an immutable, validated value object. The pattern is
/// fixed by `rulepack/schema/categories.schema.json`, and a value failing it
/// could never resolve against the pack, so it is rejected at construction
/// rather than surfacing later as a dangling reference.
///
/// The parser never determines a category (FR-CAT-02); it carries whatever the
/// caller supplies, or nothing.
final class CategoryId {
  /// Creates a category identifier, validating it against the pack pattern.
  ///
  /// Throws [FormatException] when [value] does not match
  /// `^cat\.[a-z0-9-]+$`.
  CategoryId(this.value) {
    if (!pattern.hasMatch(value)) {
      throw FormatException('Not a rule pack category identifier', value);
    }
  }

  /// The identifier as it appears in the rule pack, e.g. `cat.biscuits`.
  final String value;

  /// The pattern every category identifier must match.
  static final RegExp pattern = RegExp(r'^cat\.[a-z0-9-]+$');

  /// Whether [candidate] is a well-formed category identifier.
  static bool isValid(String candidate) => pattern.hasMatch(candidate);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CategoryId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CategoryId($value)';
}
