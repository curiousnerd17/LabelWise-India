import 'package:lw_domain/src/analysis/derivation.dart';
import 'package:lw_domain/src/analysis/factual_value.dart';
import 'package:lw_domain/src/analysis/finding_subject.dart';
import 'package:lw_domain/src/confidence/confidence.dart';
import 'package:lw_domain/src/rulepack/pack_ids.dart';

/// What kind of factual statement a finding makes.
///
/// Exactly the three Layer 1 can produce in this milestone.
/// `DATA_MODEL.md` §6.2 also lists `DECLARATION_GAP` and
/// `ADDITIVE_IDENTIFICATION`; both are deferred — FR-L1-06 has no
/// authoritative mandatory-declaration list in the pack, and FR-L1-07 needs
/// additive identification the parser deliberately does not attempt. Naming a
/// kind nothing can emit would put an unreachable case into every switch that
/// reads a finding.
enum FactualFindingKind {
  /// A declared value restated on a common basis (FR-L1-02, FR-L1-03).
  normalisation,

  /// A value expressed as a share of a gazetted daily value (FR-L1-04).
  rdaContribution,

  /// The declared serve, servings per pack and net quantity, reconciled
  /// (FR-L1-05).
  servingReconciliation,
}

/// One factual statement about the label.
///
/// **Factual, never evaluative** (FR-L1-01, P5). A finding may restate a
/// declared number, state a computed one, state that a figure could not be
/// computed, or state that no daily value is gazetted. It cannot say a food is
/// high in anything, or good, or worth avoiding — there is no field in which
/// such a claim could be stored, which is what keeps the constraint structural
/// rather than a matter of wording discipline.
///
/// The [messageId] names a catalogue entry; the domain never holds display
/// text (FR-LOC-01, M5).
final class FactualFinding {
  /// Records a factual finding.
  const FactualFinding({
    required this.kind,
    required this.subject,
    required this.value,
    required this.confidence,
    required this.messageId,
    this.derivation,
  });

  /// What kind of statement this is.
  final FactualFindingKind kind;

  /// Which figure the statement is about.
  final FindingSubject subject;

  /// What was concluded — a computed value, or an explicit non-computation.
  final FactualValue value;

  /// How much the statement should be trusted.
  ///
  /// For a computed value this is the meet of its inputs' propagated
  /// confidences (ADR-0010, FR-L1-08); a derivation never produces a level
  /// beyond the weakest thing it consumed.
  final Confidence confidence;

  /// The catalogue entry naming this statement.
  final MessageId messageId;

  /// How the value was arrived at (FR-EXP-09), or null where nothing was
  /// computed.
  ///
  /// **Null is a statement, not an omission.** A finding that restates a
  /// declared value performed no arithmetic, and one whose arithmetic was
  /// refused has no result to describe. Fabricating a derivation to fill the
  /// field would record a calculation that never happened — the opposite of
  /// what FR-EXP-09 exists for.
  final Derivation? derivation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FactualFinding &&
          kind == other.kind &&
          subject == other.subject &&
          value == other.value &&
          confidence == other.confidence &&
          messageId == other.messageId &&
          derivation == other.derivation;

  @override
  int get hashCode =>
      Object.hash(kind, subject, value, confidence, messageId, derivation);

  /// A **debugging representation only**, carrying a level name and never a
  /// number: FR-CNF-10 forbids a numeric confidence reaching the user.
  @override
  String toString() => 'FactualFinding(${kind.name}, $subject, '
      '${confidence.name}, ${messageId.value})';
}
