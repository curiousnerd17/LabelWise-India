import 'package:lw_domain/src/provenance/rule_id.dart';

/// The kind of transformation a [Substitution] records.
///
/// Exactly the six named in `DATA_MODEL.md` §3.4.
enum SubstitutionKind {
  /// An OCR character confusion corrected at S1 — `O`↔`0`, `l`↔`1`, `S`↔`5`,
  /// `B`↔`8`.
  characterConfusion,

  /// A declared unit mapped to its canonical form — `gm` to `g`.
  unitNormalisation,

  /// Kilojoules converted to kilocalories. The declared value is retained in
  /// [Substitution.before], which is what makes FR-PAR-07 satisfiable.
  energyConversion,

  /// A declared salt figure converted to sodium. Approximate, and marked
  /// derived by the caller.
  saltToSodium,

  /// A value rounded under the single rounding policy (`DATA_MODEL.md` §2.4).
  rounding,

  /// Whitespace collapsed or trimmed.
  whitespace,
}

/// One transformation applied to raw text on the way to a typed value.
///
/// Recorded so the chain from pixel to value is reconstructible (FR-EXP-07,
/// `ARCHITECTURE.md` §8.3). Without these, an explanation could state a
/// conclusion but not how the number reached it.
final class Substitution {
  /// Records a transformation.
  ///
  /// Throws [ArgumentError] when [before] equals [after]: a no-op pads the
  /// audit trail without adding information, which makes a real substitution
  /// harder to find.
  Substitution({
    required this.kind,
    required this.before,
    required this.after,
    required this.appliedByRuleId,
  }) {
    if (before == after) {
      throw ArgumentError(
        'Substitution changed nothing ("$before"). Recording a no-op '
        'transformation obscures the substitutions that matter.',
      );
    }
  }

  /// What kind of transformation this was.
  final SubstitutionKind kind;

  /// The text as it stood before the transformation.
  final String before;

  /// The text as it stood after.
  final String after;

  /// The rule that applied it.
  final RuleId appliedByRuleId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Substitution &&
          kind == other.kind &&
          before == other.before &&
          after == other.after &&
          appliedByRuleId == other.appliedByRuleId;

  @override
  int get hashCode => Object.hash(kind, before, after, appliedByRuleId);

  @override
  String toString() =>
      'Substitution(${kind.name}: "$before" -> "$after" by $appliedByRuleId)';
}
