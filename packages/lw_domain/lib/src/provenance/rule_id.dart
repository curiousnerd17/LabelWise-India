/// The identity of a rule in the rule pack.
///
/// A rule reference is not an arbitrary string. The pattern is fixed by
/// `rulepack/schema/common.schema.json`, and a value failing it could never
/// resolve against the pack — so it is rejected at construction rather than
/// discovered later as a dangling reference (FR-EXP-04, ADR-0012).
///
/// Used by `Provenance` to record which parse rule produced a field
/// (FR-PAR-13) and by `Substitution` to record which rule applied a
/// transformation. Both are referenced as code spans rather than doc links:
/// they import this file, so a doc import here would be a cycle.
final class RuleId {
  /// Creates a rule identifier, validating it against the rule pack pattern.
  ///
  /// Throws [FormatException] when [value] does not match
  /// `^rule\.[a-z0-9_.-]+$`.
  RuleId(this.value) {
    if (!pattern.hasMatch(value)) {
      // A rule reference that cannot exist in the pack is a defect here, not a
      // dangling reference found later.
      throw FormatException('Not a rule pack identifier', value);
    }
  }

  /// The identifier as it appears in the rule pack, e.g. `rule.synonym.energy`.
  final String value;

  /// The pattern every rule identifier must match, mirroring
  /// `rulepack/schema/common.schema.json` `$defs.ruleId`.
  static final RegExp pattern = RegExp(r'^rule\.[a-z0-9_.-]+$');

  /// Whether [candidate] is a well-formed rule identifier.
  static bool isValid(String candidate) => pattern.hasMatch(candidate);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RuleId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RuleId($value)';
}
