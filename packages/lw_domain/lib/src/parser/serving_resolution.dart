import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/label/serving_facts.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';

/// One reading of a serving figure, before conflict resolution.
///
/// A *reading*, not a conclusion: two candidates for the same field are a
/// normal intermediate state, and choosing between them is the resolver's job.
/// Carries `ParseStrength` (signal S2) and never a `Confidence` — confidence is
/// assigned at S8 and nowhere else.
final class ServingCandidate {
  /// Records a reading.
  ServingCandidate({
    required this.field,
    required this.quantity,
    required this.parseStrength,
    required this.region,
    required List<int> sourceIndices,
    required this.matchedBy,
  }) : sourceIndices = List<int>.unmodifiable(sourceIndices);

  /// Which figure this reads.
  final ServingField field;

  /// The value as read, qualifier included.
  final Quantity quantity;

  /// How firmly the wording matched — signal S2.
  final ParseStrength parseStrength;

  /// Where on the label it was read.
  final RegionRef region;

  /// The recognition elements it came from (ADR-0009).
  final List<int> sourceIndices;

  /// The marker rule that matched.
  final RuleId matchedBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServingCandidate &&
          field == other.field &&
          quantity == other.quantity &&
          parseStrength == other.parseStrength &&
          region == other.region &&
          matchedBy == other.matchedBy &&
          _sameIndices(other.sourceIndices);

  bool _sameIndices(List<int> other) {
    if (sourceIndices.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (sourceIndices[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        field,
        quantity,
        parseStrength,
        region,
        matchedBy,
        Object.hashAll(sourceIndices),
      );

  @override
  String toString() => 'ServingCandidate(${field.name} = $quantity)';
}

/// What S5b concluded about one serving figure.
///
/// **Three outcomes, never two.** `ServingFacts` holds three nullable
/// quantities, and null cannot distinguish *the label does not declare this*
/// from *we found something and could not use it*. MI-08 forbids conflating
/// those, and FR-ERR-03 turns on keeping them apart — so the distinction lives
/// here and is carried into `ParsedLabel` as `NotDeclaredField` versus
/// `UnresolvedField`.
sealed class ServingOutcome {
  /// Base constructor.
  const ServingOutcome();
}

/// The figure was read, unambiguously.
final class ServingResolved extends ServingOutcome {
  /// Records a resolved figure.
  const ServingResolved(this.candidate);

  /// The winning reading. When several agreed, the strongest, with their
  /// source indices merged.
  final ServingCandidate candidate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServingResolved && candidate == other.candidate;

  @override
  int get hashCode => candidate.hashCode;

  @override
  String toString() => 'ServingResolved(${candidate.quantity})';
}

/// The label declares no such figure.
///
/// **Not a failure.** Most Indian packs declare a net quantity and many declare
/// no servings-per-pack at all. Reporting this as unresolved would blame the
/// parser for the manufacturer's choice (FR-ERR-03).
final class ServingNotDeclared extends ServingOutcome {
  /// Records an absent figure.
  const ServingNotDeclared();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ServingNotDeclared;

  @override
  int get hashCode => (ServingNotDeclared).hashCode;

  @override
  String toString() => 'ServingNotDeclared()';
}

/// Something was found and could not be used.
///
/// Every candidate is retained, so a correction UI can show the user what was
/// read and let them choose — which is the whole point of not choosing here.
final class ServingUnresolved extends ServingOutcome {
  /// Records an unusable figure.
  ServingUnresolved({
    required this.reason,
    required List<ServingCandidate> candidates,
  }) : candidates = List<ServingCandidate>.unmodifiable(candidates);

  /// Why it could not be used.
  final UnresolvedReason reason;

  /// Every reading that was found. Never empty.
  final List<ServingCandidate> candidates;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServingUnresolved &&
          reason == other.reason &&
          _same(other.candidates);

  bool _same(List<ServingCandidate> other) {
    if (candidates.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (candidates[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(reason, Object.hashAll(candidates));

  @override
  String toString() =>
      'ServingUnresolved(${reason.name}, ${candidates.length} candidates)';
}

/// What S5b produces.
///
/// [facts] is what S7 consumes; [outcomes] is what assembly consumes. The two
/// are not redundant: `facts` answers "what can the invariants use", `outcomes`
/// answers "what should we tell the user", and only the second can distinguish
/// absent from unresolved.
final class ServingResolution {
  /// Records the resolution.
  ServingResolution({
    required this.facts,
    required Map<ServingField, ServingOutcome> outcomes,
  }) : outcomes = Map<ServingField, ServingOutcome>.unmodifiable(outcomes);

  /// Nothing found, for a label with no serving text at all.
  static final ServingResolution none = ServingResolution(
    facts: ServingFacts.none,
    outcomes: <ServingField, ServingOutcome>{
      for (final ServingField f in ServingField.values)
        f: const ServingNotDeclared(),
    },
  );

  /// The figures the invariants may use. Only resolved figures appear.
  final ServingFacts facts;

  /// The outcome for every field. Always covers all three.
  final Map<ServingField, ServingOutcome> outcomes;

  /// The outcome for [field]. Never null — every field has an outcome.
  ServingOutcome outcomeFor(ServingField field) =>
      outcomes[field] ?? const ServingNotDeclared();

  /// Value equality across the facts and every outcome.
  ///
  /// **Required, not decorative.** FR-PAR-02 and PT-06 make determinism a
  /// property that must be *checkable*: the same label read twice must produce
  /// results that compare equal. Identity comparison would make that assertion
  /// pass only by accident and fail for two genuinely identical resolutions,
  /// which is the wrong answer in both directions.
  ///
  /// Compared over `ServingField.values` rather than by map iteration, so the
  /// result cannot depend on insertion order.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ServingResolution) {
      return false;
    }
    if (facts != other.facts) {
      return false;
    }
    for (final ServingField f in ServingField.values) {
      if (outcomeFor(f) != other.outcomeFor(f)) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        facts,
        Object.hashAll(
          <ServingOutcome>[
            for (final ServingField f in ServingField.values) outcomeFor(f),
          ],
        ),
      );

  @override
  String toString() {
    final int resolved = outcomes.values.whereType<ServingResolved>().length;
    return 'ServingResolution($resolved of ${outcomes.length} resolved)';
  }
}
