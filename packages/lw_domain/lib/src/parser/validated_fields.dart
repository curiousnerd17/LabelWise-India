import 'package:lw_domain/src/invariants/invariant_id.dart';
import 'package:lw_domain/src/invariants/invariant_result.dart';
import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/serving_facts.dart';
import 'package:lw_domain/src/parser/candidates.dart';
import 'package:lw_domain/src/parser/resolved_fields.dart';
import 'package:lw_domain/src/parser/typed_fields.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';

/// The output of S7 — typed values, each now with its arithmetic checked.
///
/// The values themselves are **unchanged**. S7 judges, it does not correct: a
/// value that fails an invariant is still the value the label declared, and
/// silently adjusting it would replace the manufacturer's claim with our guess
/// (P1). What S7 adds is the evidence S8 needs to assign confidence and Layer 1
/// needs to explain itself.
final class ValidatedFields {
  /// Records the validated result.
  ValidatedFields({
    List<TypedField> fields = const <TypedField>[],
    List<InvariantResult> results = const <InvariantResult>[],
    List<UnresolvedCandidate> unresolved = const <UnresolvedCandidate>[],
    List<IngredientToken> ingredientTokens = const <IngredientToken>[],
    this.serving = ServingFacts.none,
    this.nutritionPanelPresent = false,
    this.ingredientListPresent = false,
  })  : fields = List<TypedField>.unmodifiable(fields),
        results = List<InvariantResult>.unmodifiable(results),
        unresolved = List<UnresolvedCandidate>.unmodifiable(unresolved),
        ingredientTokens = List<IngredientToken>.unmodifiable(ingredientTokens);

  /// The typed values, exactly as S6 produced them.
  final List<TypedField> fields;

  /// Every invariant evaluated, in a deterministic order (FR-CNF-04).
  ///
  /// Includes the `INAPPLICABLE` ones. "We could not check this" is different
  /// from "this checked out", and omitting the former would collapse them.
  final List<InvariantResult> results;

  /// Everything that could not be typed, carried from S5 and S6 (FR-ERR-03).
  final List<UnresolvedCandidate> unresolved;

  /// Ingredient tokens, carried through untouched.
  final List<IngredientToken> ingredientTokens;

  /// The pack figures the serving invariants were evaluated against.
  final ServingFacts serving;

  /// Whether S3 identified a nutrition panel at all.
  final bool nutritionPanelPresent;

  /// Whether S3 identified an ingredient list at all.
  final bool ingredientListPresent;

  /// The stage that produced this, recorded for diagnostics.
  PipelineStage get producedByStage => PipelineStage.invariantEvaluation;

  /// Every check that failed.
  List<InvariantResult> get failures => List<InvariantResult>.unmodifiable(
        results.where((InvariantResult r) => r.outcome.capsConfidence),
      );

  /// Whether FR-CNF-05 forbids `HIGH` for this field.
  ///
  /// True when the field took part in a failed check on its own basis, or in a
  /// failed check that is not basis-scoped. Capping by *field* rather than by
  /// invariant is deliberate: a clean sodium reading must not be penalised for
  /// a fat reconciliation it took no part in.
  bool capsConfidenceFor(NutrientId nutrient, Basis basis) {
    final InvariantSubject subject = NutrientSubject(nutrient);
    for (final InvariantResult r in results) {
      if (!r.outcome.capsConfidence) {
        continue;
      }
      if (r.basis != null && r.basis != basis) {
        continue;
      }
      if (r.involves(subject)) {
        return true;
      }
    }
    return false;
  }

  /// Every result recorded for [id], in evaluation order.
  List<InvariantResult> resultsFor(InvariantId id) =>
      List<InvariantResult>.unmodifiable(
        results.where((InvariantResult r) => r.invariantId == id),
      );

  /// Every source index reached, ascending.
  List<int> get sourceIndices {
    final List<int> all = <int>[
      for (final TypedField f in fields) ...f.sourceIndices,
      for (final UnresolvedCandidate u in unresolved) ...u.sourceIndices,
      for (final IngredientToken t in ingredientTokens) ...t.allSourceIndices,
    ]..sort();
    return List<int>.unmodifiable(all);
  }

  @override
  String toString() => 'ValidatedFields(${fields.length} typed, '
      '${results.length} checks, ${failures.length} failed)';
}
