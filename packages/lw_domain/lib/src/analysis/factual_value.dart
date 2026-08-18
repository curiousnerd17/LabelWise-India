import 'package:lw_domain/src/label/field_state.dart';

/// What a Layer 1 finding concluded about one figure.
///
/// > **A deliberate, localised narrowing of `DATA_MODEL.md` §6.2.** That
/// > section types `FactualFinding.value` as `FieldState`. `FieldState` cannot
/// > express two outcomes that only factual analysis produces:
/// >
/// > - the arithmetic was refused because it could not be performed safely;
/// > - the rule pack gazettes no denominator for a nutrient.
/// >
/// > Both are states in which the label was read **perfectly**. The only
/// > `FieldState` variant carrying "no value" is `UnresolvedField`, and every
/// > `UnresolvedReason` describes a *parsing* failure — `valueNotParseable`,
/// > `ambiguousMatch`, and so on. Reusing one would say the label was
/// > unreadable when it was not, which is the MI-08 conflation this project
/// > has refused at every prior milestone. Extending `UnresolvedReason`
/// > instead would push Layer 1's vocabulary into an enum that S5, S6 and S5b
/// > switch over exhaustively.
/// >
/// > So Layer 1 wraps `FieldState` rather than replacing or extending it. The
/// > narrowing stays inside this layer; nothing in M1–M12 changes.
///
/// `sealed`, so a switch that omits a case does not compile.
sealed class FactualValue {
  /// Base constructor for the three outcomes.
  const FactualValue();
}

/// A figure Layer 1 successfully computed or restated.
///
/// Wraps the existing [FieldState] **unchanged** rather than re-representing
/// it: the wrapped value keeps its own quantity, basis, provenance and
/// confidence, and a consumer that already understands `FieldState` needs no
/// second vocabulary to read it. For M13's derived figures this is normally a
/// `DerivedField` carrying `Provenance.factual`.
final class ComputedFactualValue extends FactualValue {
  /// Records a computed figure.
  const ComputedFactualValue(this.field);

  /// The value, in the domain's existing field vocabulary.
  final FieldState field;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComputedFactualValue && field == other.field;

  @override
  int get hashCode => field.hashCode;

  @override
  String toString() => 'ComputedFactualValue($field)';
}

/// The inputs were read, and the arithmetic could not be performed safely.
///
/// **Not a parse failure and not an absence.** The declared values were
/// understood; the calculation over them was declined — a magnitude that would
/// wrap a 64-bit multiply, or a divisor that cannot be bounded. M11b
/// established that a refused calculation must never become a fabricated
/// number, and this is where that refusal surfaces to the user.
///
/// Carries no reason code. The finding's `messageId` says which figure could
/// not be computed, and inventing a taxonomy of arithmetic refusals would be
/// vocabulary no corpus has justified.
final class NotComputableFactualValue extends FactualValue {
  /// Records an arithmetic refusal.
  const NotComputableFactualValue();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NotComputableFactualValue;

  @override
  int get hashCode => (NotComputableFactualValue).hashCode;

  @override
  String toString() => 'NotComputableFactualValue()';
}

/// The nutrient was declared, and the rule pack gazettes no daily value.
///
/// **A fact about the regulation, not about the label.** FSSAI sets daily
/// values for six nutrients; a label declaring dietary fibre is complete and
/// correct, and there is simply no denominator to divide by. `RdaTable`
/// already documents its null return as exactly this statement — "no daily
/// value is gazetted for this nutrient", which is a different sentence from
/// "this nutrient is absent" (FR-ERR-03, one level up).
final class NoDenominatorFactualValue extends FactualValue {
  /// Records the absence of a gazetted denominator.
  const NoDenominatorFactualValue();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NoDenominatorFactualValue;

  @override
  int get hashCode => (NoDenominatorFactualValue).hashCode;

  @override
  String toString() => 'NoDenominatorFactualValue()';
}
