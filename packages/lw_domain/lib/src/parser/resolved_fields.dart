import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/qualifier.dart';
import 'package:lw_domain/src/parser/candidates.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';

/// A candidate that resolved to a nutrient and a basis, but is still text.
///
/// **No `Quantity` yet.** S5 answers *which nutrient* and *against what
/// reference*; S6 answers *what number in what unit*. Splitting them is what
/// the stage names say (`ResolvedFields` then `TypedFields`) and what keeps
/// each independently testable (`ARCHITECTURE.md` §6.2).
///
/// Carries **two** parse strengths rather than one. The label may match
/// exactly while the basis is a heuristic read of a vague heading, and S8
/// needs both to combine signal S2 honestly — collapsing them to a single
/// value would lose which half was weak.
final class ResolvedField {
  /// Records a resolved field.
  ///
  /// Throws [ArgumentError] when [valueText] is blank or [sourceIndices] is
  /// empty — a value with no origin cannot be explained (`ARCHITECTURE.md`
  /// §8.3).
  ResolvedField({
    required this.nutrient,
    required this.valueText,
    required this.basis,
    required this.labelStrength,
    required this.basisStrength,
    required this.region,
    required List<int> sourceIndices,
    required this.matchedBy,
    this.unitText,
    this.qualifier = Qualifier.exact,
  }) : sourceIndices = List<int>.unmodifiable(sourceIndices) {
    if (valueText.trim().isEmpty) {
      throw ArgumentError.value(
        valueText,
        'valueText',
        'A resolved field without a value declares nothing.',
      );
    }
    if (sourceIndices.isEmpty) {
      throw ArgumentError.value(
        sourceIndices,
        'sourceIndices',
        'A resolved field must trace to at least one recognised element.',
      );
    }
  }

  /// The nutrient the label wording resolved to.
  final NutrientId nutrient;

  /// The number as printed, still text. S6 types it.
  final String valueText;

  /// The unit as printed, or null when the line carried none. S6 judges it.
  final String? unitText;

  /// The qualifier read at S4, carried through untouched (ADR-0027).
  final Qualifier qualifier;

  /// The reference quantity, read from the column heading.
  final Basis basis;

  /// How firmly the label matched the synonym table — signal S2.
  final ParseStrength labelStrength;

  /// How firmly the column heading declared the basis — signal S2.
  final ParseStrength basisStrength;

  /// Where the field sits on the label.
  final RegionRef region;

  /// Source indices of every element that contributed, ascending.
  final List<int> sourceIndices;

  /// The rule that resolved it (FR-PAR-13).
  final RuleId matchedBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedField &&
          nutrient == other.nutrient &&
          valueText == other.valueText &&
          unitText == other.unitText &&
          qualifier == other.qualifier &&
          basis == other.basis &&
          labelStrength == other.labelStrength &&
          basisStrength == other.basisStrength &&
          region == other.region &&
          matchedBy == other.matchedBy &&
          _sameInts(sourceIndices, other.sourceIndices);

  @override
  int get hashCode => Object.hash(
        nutrient,
        valueText,
        unitText,
        qualifier,
        basis,
        labelStrength,
        basisStrength,
        region,
        matchedBy,
        Object.hashAll(sourceIndices),
      );

  @override
  String toString() => 'ResolvedField(${nutrient.name}, ${basis.name}, '
      '${qualifier.name} "$valueText" ${unitText ?? "?"})';
}

/// A candidate that could not be resolved, and why.
///
/// A first-class outcome, not an omission. FR-ERR-03 requires "we could not
/// read this" to stay distinguishable from "the label does not declare this",
/// and that distinction only survives if the failure is carried forward with
/// the same provenance a success would have had.
final class UnresolvedCandidate {
  /// Records a failure to resolve.
  ///
  /// Throws [ArgumentError] when [sourceIndices] is empty.
  UnresolvedCandidate({
    required this.reason,
    required this.labelText,
    required this.region,
    required List<int> sourceIndices,
  }) : sourceIndices = List<int>.unmodifiable(sourceIndices) {
    if (sourceIndices.isEmpty) {
      throw ArgumentError.value(
        sourceIndices,
        'sourceIndices',
        'An unresolved candidate must still trace to the label.',
      );
    }
  }

  /// Why it could not be resolved.
  final UnresolvedReason reason;

  /// The wording that could not be resolved, as printed.
  final String labelText;

  /// Where it sits on the label, so the user can be shown what failed.
  final RegionRef region;

  /// Source indices of every element that contributed, ascending.
  final List<int> sourceIndices;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnresolvedCandidate &&
          reason == other.reason &&
          labelText == other.labelText &&
          region == other.region &&
          _sameInts(sourceIndices, other.sourceIndices);

  @override
  int get hashCode =>
      Object.hash(reason, labelText, region, Object.hashAll(sourceIndices));

  @override
  String toString() => 'UnresolvedCandidate(${reason.name}, "$labelText")';
}

/// The output of S5 — nutrients and bases identified, values still text.
final class ResolvedFields {
  /// Records the resolution.
  ResolvedFields({
    List<ResolvedField> fields = const <ResolvedField>[],
    List<UnresolvedCandidate> unresolved = const <UnresolvedCandidate>[],
    List<IngredientToken> ingredientTokens = const <IngredientToken>[],
    this.nutritionPanelPresent = false,
    this.ingredientListPresent = false,
  })  : fields = List<ResolvedField>.unmodifiable(fields),
        unresolved = List<UnresolvedCandidate>.unmodifiable(unresolved),
        ingredientTokens = List<IngredientToken>.unmodifiable(ingredientTokens);

  /// Fields that resolved, in the order S4 produced their candidates.
  final List<ResolvedField> fields;

  /// Candidates that did not resolve, with the reason (FR-ERR-03).
  final List<UnresolvedCandidate> unresolved;

  /// Ingredient tokens, carried through untouched.
  ///
  /// S5 has nothing to say about them — additive identification is Layer 1's
  /// job (FR-PAR-11) — but dropping them here would lose the declaration
  /// before it reaches `ParsedLabel`.
  final List<IngredientToken> ingredientTokens;

  /// Whether S3 identified a nutrition panel at all. See
  /// `Candidates.nutritionPanelPresent`.
  final bool nutritionPanelPresent;

  /// Whether S3 identified an ingredient list at all.
  final bool ingredientListPresent;

  /// The stage that produced this, recorded for diagnostics.
  PipelineStage get producedByStage => PipelineStage.fieldResolution;

  /// Every source index reached, ascending.
  List<int> get sourceIndices {
    final List<int> all = <int>[
      for (final ResolvedField f in fields) ...f.sourceIndices,
      for (final UnresolvedCandidate u in unresolved) ...u.sourceIndices,
      for (final IngredientToken t in ingredientTokens) ...t.allSourceIndices,
    ]..sort();
    return List<int>.unmodifiable(all);
  }

  @override
  String toString() => 'ResolvedFields(${fields.length} resolved, '
      '${unresolved.length} unresolved)';
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
