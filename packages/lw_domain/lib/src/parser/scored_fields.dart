import 'package:lw_domain/src/confidence/confidence.dart';
import 'package:lw_domain/src/confidence/confidence_signals.dart';
import 'package:lw_domain/src/confidence/scan_confidence.dart';
import 'package:lw_domain/src/invariants/invariant_result.dart';
import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/serving_facts.dart';
import 'package:lw_domain/src/parser/candidates.dart';
import 'package:lw_domain/src/parser/resolved_fields.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';

/// One field, its assigned confidence, and the signals that decided it.
///
/// The `FieldState` is the value; [signals] is the working. FR-EXP-09 needs
/// both — a classification that states a level but not what produced it is a
/// verdict without evidence, and ADR-0009 makes confidence and explainability
/// two views of one recorded fact rather than two features.
final class ScoredField {
  /// Records a scored field.
  ///
  /// Throws [ArgumentError] when [sourceIndices] is empty: a value with no
  /// origin cannot be explained (`ARCHITECTURE.md` §8.3).
  ScoredField({
    required this.nutrient,
    required this.basis,
    required this.state,
    required this.signals,
    required this.region,
    required List<int> sourceIndices,
  }) : sourceIndices = List<int>.unmodifiable(sourceIndices) {
    if (sourceIndices.isEmpty) {
      throw ArgumentError.value(
        sourceIndices,
        'sourceIndices',
        'A scored field must trace to at least one recognised element.',
      );
    }
  }

  /// The nutrient this value belongs to.
  final NutrientId nutrient;

  /// The reference quantity it is expressed against.
  final Basis basis;

  /// The value, now carrying its confidence (`DATA_MODEL.md` §5.1).
  final FieldState state;

  /// What S8 decided from.
  final ConfidenceSignals signals;

  /// Where the value sits on the label.
  final RegionRef region;

  /// Source indices of every element that contributed, ascending.
  final List<int> sourceIndices;

  /// The assigned level, or null where none exists.
  ///
  /// Null for a user-supplied field, which has no *inferred* confidence at all
  /// (FR-CNF-12, MI-02) — it still propagates as maximally trustworthy, but
  /// that is a propagation rule rather than a stored level. Exposed directly
  /// because callers ask this constantly, and making each one destructure a
  /// `FieldState` union would guarantee that some call site skips the question.
  Confidence? get confidence => state.confidenceOrNull;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoredField &&
          nutrient == other.nutrient &&
          basis == other.basis &&
          state == other.state &&
          signals == other.signals &&
          region == other.region &&
          _sameInts(sourceIndices, other.sourceIndices);

  @override
  int get hashCode => Object.hash(
        nutrient,
        basis,
        state,
        signals,
        region,
        Object.hashAll(sourceIndices),
      );

  /// A **debugging representation only**, carrying a level name and never a
  /// number: FR-CNF-10 forbids a numeric confidence reaching the user.
  @override
  String toString() => 'ScoredField(${nutrient.name}, ${basis.name}, '
      '${confidence?.name ?? '-'})';
}

/// The output of S8 — every field classified, and the scan summarised.
///
/// **Not `ParsedLabel`.** Per `ARCHITECTURE.md` §6.1 as amended in v1.3, that
/// assembly waits on ingredient identification and serving resolution, neither
/// of which exists yet. S8's responsibility has always been the narrower one:
/// combine the signals into a classification per field.
final class ScoredFields {
  /// Records the scored result.
  ScoredFields({
    required this.scanConfidence,
    List<ScoredField> fields = const <ScoredField>[],
    List<UnresolvedCandidate> unresolved = const <UnresolvedCandidate>[],
    List<InvariantResult> invariantResults = const <InvariantResult>[],
    List<IngredientToken> ingredientTokens = const <IngredientToken>[],
    this.serving = ServingFacts.none,
    this.nutritionPanelPresent = false,
    this.ingredientListPresent = false,
  })  : fields = List<ScoredField>.unmodifiable(fields),
        unresolved = List<UnresolvedCandidate>.unmodifiable(unresolved),
        invariantResults = List<InvariantResult>.unmodifiable(invariantResults),
        ingredientTokens = List<IngredientToken>.unmodifiable(ingredientTokens);

  /// Every field that typed, now classified.
  final List<ScoredField> fields;

  /// Everything that could not be read, carried from S5 and S6 (FR-ERR-03).
  final List<UnresolvedCandidate> unresolved;

  /// Every invariant evaluated, carried from S7 (FR-CNF-04).
  final List<InvariantResult> invariantResults;

  /// Ingredient tokens, carried through untouched.
  final List<IngredientToken> ingredientTokens;

  /// The pack figures the serving invariants were evaluated against.
  final ServingFacts serving;

  /// How much of this scan the user should check (`DATA_MODEL.md` §4.5).
  ///
  /// For orientation only. §4.5 forbids it gating anything: a scan can be LOW
  /// because the protein reading is poor while the sodium reading is
  /// impeccable, and suppressing the sodium finding would discard a good
  /// result on the strength of an unrelated bad one.
  final ScanConfidence scanConfidence;

  /// Whether S3 identified a nutrition panel at all.
  final bool nutritionPanelPresent;

  /// Whether S3 identified an ingredient list at all.
  final bool ingredientListPresent;

  /// The stage that produced this, recorded for diagnostics.
  PipelineStage get producedByStage => PipelineStage.confidenceAssignment;

  /// The level assigned to one field, or null when no such field was scored.
  ///
  /// Null rather than a default: an absent field has no level, and inventing
  /// one would be indistinguishable from a real classification.
  Confidence? confidenceFor(NutrientId nutrient, Basis basis) {
    for (final ScoredField f in fields) {
      if (f.nutrient == nutrient && f.basis == basis) {
        return f.confidence;
      }
    }
    return null;
  }

  /// Every source index reached, ascending.
  List<int> get sourceIndices {
    final List<int> all = <int>[
      for (final ScoredField f in fields) ...f.sourceIndices,
      for (final UnresolvedCandidate u in unresolved) ...u.sourceIndices,
      for (final IngredientToken t in ingredientTokens) ...t.allSourceIndices,
    ]..sort();
    return List<int>.unmodifiable(all);
  }

  @override
  String toString() =>
      'ScoredFields(${fields.length} scored, scan ${scanConfidence.name})';
}

bool _sameInts(List<int> a, List<int> b) {
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
