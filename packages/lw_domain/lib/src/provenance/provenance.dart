import 'package:lw_domain/src/provenance/field_origin.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';
import 'package:lw_domain/src/provenance/substitution.dart';
import 'package:lw_domain/src/version.dart';

/// Where a value came from, and how it got here.
///
/// **The single abstraction beneath confidence and explainability** (ADR-0009).
/// They are not two features but two views of one recorded fact: what produced
/// this value, from which inputs, under which rule, at what strength. Built
/// once, both fall out; built separately, they drift.
///
/// Construction goes through named constructors rather than one constructor
/// with optional arguments. `DATA_MODEL.md` §3.1 justifies each optional field
/// by origin — `parseRuleId` and `parseStrength` are absent only for
/// user-supplied values, `sourceRegion` for anything never on the label — and
/// named constructors make those rules structural instead of documentary (M2).
final class Provenance {
  const Provenance._({
    required this.origin,
    required this.rulePackVersion,
    required List<Substitution> substitutions,
    this.producedByStage,
    this.parseRuleId,
    this.parseStrength,
    this.sourceRegion,
  }) : _substitutions = substitutions;

  /// Provenance for a value read from the label by the parser.
  ///
  /// Requires the rule that matched, the strength at which it matched, and the
  /// position on the label. All three exist for every extracted value, so none
  /// of them is optional here (FR-PAR-13).
  factory Provenance.extracted({
    required PipelineStage producedByStage,
    required RuleId parseRuleId,
    required ParseStrength parseStrength,
    required RegionRef sourceRegion,
    required Version rulePackVersion,
    List<Substitution> substitutions = const <Substitution>[],
  }) =>
      Provenance._(
        origin: FieldOrigin.extracted,
        producedByStage: producedByStage,
        parseRuleId: parseRuleId,
        parseStrength: parseStrength,
        sourceRegion: sourceRegion,
        rulePackVersion: rulePackVersion,
        substitutions: List<Substitution>.unmodifiable(substitutions),
      );

  /// Provenance for a value computed from other fields.
  ///
  /// Carries no [sourceRegion]: a derived value was never on the label, so it
  /// cannot point at a position on it.
  factory Provenance.derived({
    required PipelineStage producedByStage,
    required RuleId parseRuleId,
    required Version rulePackVersion,
    ParseStrength? parseStrength,
    List<Substitution> substitutions = const <Substitution>[],
  }) =>
      Provenance._(
        origin: FieldOrigin.derived,
        producedByStage: producedByStage,
        parseRuleId: parseRuleId,
        parseStrength: parseStrength,
        rulePackVersion: rulePackVersion,
        substitutions: List<Substitution>.unmodifiable(substitutions),
      );

  /// Provenance for a value computed by **Layer 1 factual analysis**.
  ///
  /// Carries no [producedByStage], and that is the point rather than an
  /// omission. Layer 1 consumes the finished `ParsedLabel`; it is analysis, not
  /// a parser stage, and no stage produced its output. [producedByStage] is
  /// already documented as null "for a value that no stage produced" — this is
  /// the first caller for which that is literally true.
  ///
  /// > **Why [PipelineStage] did not grow a tenth member instead.** Its nine
  /// > values are the parser stages, and `precedes` is meaningful only while
  /// > every member sits in one pipeline. A `factualAnalysis` member would make
  /// > that comparison span two layers of the architecture, weakening a type
  /// > whose whole purpose is to make pipeline ordering mechanically
  /// > verifiable.
  ///
  /// Carries no [parseStrength] either: signal S2 is a property of a rule
  /// *matching text*, and Layer 1 matched nothing — it did arithmetic.
  /// Supplying a placeholder would feed a confidence signal from an event that
  /// never happened (ADR-0010, P1). No [sourceRegion], because a computed value
  /// was never on the label.
  ///
  /// [origin] is [FieldOrigin.derived] rather than a fourth kind: a Layer 1
  /// value *is* computed from other fields, so ADR-0010's rule that a derived
  /// confidence never exceeds the meet of its inputs applies unchanged.
  factory Provenance.factual({
    required RuleId parseRuleId,
    required Version rulePackVersion,
    List<Substitution> substitutions = const <Substitution>[],
  }) =>
      Provenance._(
        origin: FieldOrigin.derived,
        parseRuleId: parseRuleId,
        rulePackVersion: rulePackVersion,
        substitutions: List<Substitution>.unmodifiable(substitutions),
      );

  /// Provenance for a value entered or corrected by the user.
  ///
  /// Carries no rule, no strength, no stage and no region. Nothing in the
  /// parser produced it, so there is no rule to name and no strength at which a
  /// rule matched (`DATA_MODEL.md` §3.1). Supplying a placeholder strength
  /// would feed signal S2 from a match that never happened (ADR-0010) and would
  /// breach honesty over completeness (P1).
  factory Provenance.userSupplied({
    required Version rulePackVersion,
    List<Substitution> substitutions = const <Substitution>[],
  }) =>
      Provenance._(
        origin: FieldOrigin.userSupplied,
        rulePackVersion: rulePackVersion,
        substitutions: List<Substitution>.unmodifiable(substitutions),
      );

  /// How this value came to exist.
  final FieldOrigin origin;

  /// The pipeline stage that produced it, or null for a user-supplied value
  /// that no stage produced.
  final PipelineStage? producedByStage;

  /// The rule that produced it, or null for a user-supplied value.
  final RuleId? parseRuleId;

  /// The strength at which the rule matched — signal S2 — or null for a
  /// user-supplied value, which matched nothing.
  final ParseStrength? parseStrength;

  /// Its position on the label, or null when it was never on the label.
  final RegionRef? sourceRegion;

  /// The rule pack version in force when this value was produced (FR-KB-02).
  final Version rulePackVersion;

  final List<Substitution> _substitutions;

  /// Every transformation applied on the way to the typed value, in the order
  /// applied. Possibly empty; never null.
  ///
  /// Unmodifiable: an audit trail that callers can append to after the fact is
  /// not an audit trail.
  List<Substitution> get substitutions => _substitutions;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Provenance) {
      return false;
    }
    if (_substitutions.length != other._substitutions.length) {
      return false;
    }
    for (int i = 0; i < _substitutions.length; i++) {
      if (_substitutions[i] != other._substitutions[i]) {
        return false;
      }
    }
    return origin == other.origin &&
        producedByStage == other.producedByStage &&
        parseRuleId == other.parseRuleId &&
        parseStrength == other.parseStrength &&
        sourceRegion == other.sourceRegion &&
        rulePackVersion == other.rulePackVersion;
  }

  @override
  int get hashCode => Object.hash(
        origin,
        producedByStage,
        parseRuleId,
        parseStrength,
        sourceRegion,
        rulePackVersion,
        Object.hashAll(_substitutions),
      );

  @override
  String toString() => 'Provenance(${origin.name}, stage: '
      '${producedByStage?.name}, rule: $parseRuleId, '
      'strength: ${parseStrength?.name}, pack: $rulePackVersion)';
}
