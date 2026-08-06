import 'package:lw_domain/src/invariants/invariant_id.dart';
import 'package:lw_domain/src/invariants/tolerance.dart';
import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/label/serving_facts.dart';

/// What came of evaluating an invariant.
///
/// Four outcomes, not two. `DATA_MODEL.md` §4.3a:
///
/// - `INAPPLICABLE` is a first-class outcome, not a silent skip — "we could
///   not check this" is different from "this checked out" (FR-CNF-04).
/// - `INDETERMINATE` records that the declarations themselves do not settle
///   the comparison, because one of them was a bound (ADR-0027, FR-CNF-14).
///
/// The two behave identically for confidence and are still recorded
/// separately, because they answer different questions. Only `INDETERMINATE`
/// is worth telling the user about.
enum InvariantOutcome {
  /// The comparison is definitely true.
  passed,

  /// The comparison is definitely false.
  failed,

  /// The intervals overlap; the declarations do not settle it.
  indeterminate,

  /// The participating fields were absent, or excluded for this category.
  inapplicable;

  /// Whether this outcome caps a participating field below `HIGH`.
  ///
  /// **True only for [failed]** — FR-CNF-05 is absolute, and FR-CNF-14 is
  /// equally absolute that [indeterminate] must never be treated as a failure.
  /// A label that declared `< 0.5 g` has not been caught out; it has declined
  /// to settle the question.
  bool get capsConfidence => this == InvariantOutcome.failed;

  /// Whether this outcome is positive evidence for `HIGH`.
  ///
  /// True only for [passed]. [indeterminate] and [inapplicable] carry no
  /// signal in either direction.
  bool get supportsHigh => this == InvariantOutcome.passed;
}

/// A field an invariant compared.
///
/// `DATA_MODEL.md` §4.3 gives `participatingFields` the type
/// `[NutrientId | ServingField]`. A sealed union rather than two nullable
/// members, so a switch that forgets one kind fails to compile rather than
/// silently ignoring half the subjects FR-CNF-05 must cap.
sealed class InvariantSubject {
  /// Base constructor for the two kinds.
  const InvariantSubject();
}

/// A nutrient that participated in an invariant.
final class NutrientSubject extends InvariantSubject {
  /// Records a nutrient subject.
  const NutrientSubject(this.nutrient);

  /// The nutrient compared.
  final NutrientId nutrient;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutrientSubject && nutrient == other.nutrient;

  @override
  int get hashCode => nutrient.hashCode;

  @override
  String toString() => 'NutrientSubject(${nutrient.name})';
}

/// A declared pack figure that participated in an invariant.
final class ServingSubject extends InvariantSubject {
  /// Records a serving subject.
  const ServingSubject(this.field);

  /// The pack figure compared.
  final ServingField field;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ServingSubject && field == other.field;

  @override
  int get hashCode => field.hashCode;

  @override
  String toString() => 'ServingSubject(${field.name})';
}

/// The record of one invariant evaluation — confidence signal **S3**.
///
/// Mirrors `DATA_MODEL.md` §4.3 as amended in v1.5. Consumed by S8 to
/// discharge FR-CNF-05 and by Layer 1 to satisfy FR-EXP-09, which is why the
/// participating fields and the tolerance are recorded rather than only the
/// verdict: a finding that states a conclusion but not how it was reached is
/// not an explanation.
final class InvariantResult {
  /// Records an evaluation.
  ///
  /// Throws [ArgumentError] when [participatingFields] is empty — FR-CNF-05
  /// has to know which fields to cap, and a result naming none could never
  /// discharge it.
  ///
  /// Throws [ArgumentError] when an `INAPPLICABLE` outcome carries an
  /// [observedDeviation] or a [toleranceApplied]. §4.3 calls both meaningless
  /// in that case; making it structural is cheaper than a comment nobody
  /// reads.
  InvariantResult({
    required this.invariantId,
    required this.outcome,
    required List<InvariantSubject> participatingFields,
    this.basis,
    this.observedDeviation,
    this.toleranceApplied,
  }) : participatingFields =
            List<InvariantSubject>.unmodifiable(participatingFields) {
    if (participatingFields.isEmpty) {
      throw ArgumentError.value(
        participatingFields,
        'participatingFields',
        'An invariant result must name the fields it compared.',
      );
    }
    if (outcome == InvariantOutcome.inapplicable &&
        (observedDeviation != null || toleranceApplied != null)) {
      throw ArgumentError.value(
        outcome,
        'outcome',
        'An inapplicable check has nothing to be out by and no band to '
            'have applied.',
      );
    }
  }

  /// Which check this was.
  final InvariantId invariantId;

  /// What came of it.
  final InvariantOutcome outcome;

  /// The fields compared, in the order the check names them.
  final List<InvariantSubject> participatingFields;

  /// The column this check applied to, or null when it is not basis-scoped.
  ///
  /// Added in `DATA_MODEL.md` v1.5. A panel declaring both per-100 g and
  /// per-serve produces one result per basis, and without this a per-serve
  /// failure would cap a correctly-read per-100 g field under FR-CNF-05.
  final Basis? basis;

  /// How far the declaration was out, when it was.
  ///
  /// Recorded for [InvariantOutcome.failed], where it is what a user needs in
  /// order to check the packet. Null otherwise: a pass is not out by anything
  /// worth stating, and an indeterminate comparison has no single deviation.
  final Quantity? observedDeviation;

  /// The band that was granted, or null when none applied.
  final Tolerance? toleranceApplied;

  /// Whether [subject] took part in this check.
  ///
  /// The hook S8 uses to cap **only** the fields that were actually involved
  /// (FR-CNF-05). Capping by invariant rather than by field would penalise a
  /// clean sodium reading for a fat reconciliation it took no part in.
  bool involves(InvariantSubject subject) =>
      participatingFields.contains(subject);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvariantResult &&
          invariantId == other.invariantId &&
          outcome == other.outcome &&
          basis == other.basis &&
          observedDeviation == other.observedDeviation &&
          toleranceApplied == other.toleranceApplied &&
          _sameSubjects(participatingFields, other.participatingFields);

  @override
  int get hashCode => Object.hash(
        invariantId,
        outcome,
        basis,
        observedDeviation,
        toleranceApplied,
        Object.hashAll(participatingFields),
      );

  @override
  String toString() => 'InvariantResult(${invariantId.code}, '
      '${basis?.name ?? '-'}, ${outcome.name})';
}

bool _sameSubjects(List<InvariantSubject> a, List<InvariantSubject> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
