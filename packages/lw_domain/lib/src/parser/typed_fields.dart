import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/parser/candidates.dart';
import 'package:lw_domain/src/parser/resolved_fields.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';
import 'package:lw_domain/src/provenance/substitution.dart';

/// A nutrient value with a unit, a basis, and everything S8 needs to judge it.
///
/// The end of the parser's typing work. What remains before `ParsedLabel` is
/// arithmetic validation (S7) and confidence assignment (S8).
///
/// **Deliberately not an `ExtractedField`.** That type requires a `Confidence`,
/// and confidence is assigned at S8 from a function held in the rule pack
/// (ADR-0010, `ARCHITECTURE.md` §7.2). Constructing one here would either
/// invent a confidence or duplicate S8's rule — two sources of truth for the
/// number the whole product's honesty rests on.
final class TypedField {
  /// Records a typed field.
  ///
  /// Throws [ArgumentError] when [sourceIndices] is empty.
  TypedField({
    required this.nutrient,
    required this.quantity,
    required this.basis,
    required this.labelStrength,
    required this.basisStrength,
    required this.unitStrength,
    required this.unitWasExpected,
    required this.region,
    required List<int> sourceIndices,
    required this.matchedBy,
    this.declaredAs,
    List<Substitution> substitutions = const <Substitution>[],
  })  : sourceIndices = List<int>.unmodifiable(sourceIndices),
        substitutions = List<Substitution>.unmodifiable(substitutions) {
    if (sourceIndices.isEmpty) {
      throw ArgumentError.value(
        sourceIndices,
        'sourceIndices',
        'A typed field must trace to at least one recognised element.',
      );
    }
  }

  /// The nutrient this value belongs to.
  final NutrientId nutrient;

  /// The value, in its canonical unit.
  final Quantity quantity;

  /// The reference quantity it is expressed against.
  final Basis basis;

  /// The value exactly as declared, when a conversion changed it.
  ///
  /// Null when none occurred. Non-null only after a kilojoule-to-kilocalorie
  /// conversion, which FR-PAR-07 requires to retain the original declaration.
  final Quantity? declaredAs;

  /// Every transformation applied on the way to [quantity], in order applied.
  ///
  /// Empty when the printed form was already canonical. `Substitution` rejects
  /// a no-op, so an entry here always records a real change (FR-OCR-06).
  final List<Substitution> substitutions;

  /// How firmly the label matched the synonym table — signal S2.
  final ParseStrength labelStrength;

  /// How firmly the column heading declared the basis — signal S2.
  final ParseStrength basisStrength;

  /// How firmly the printed unit matched the lexicon — signal S2.
  final ParseStrength unitStrength;

  /// Whether the declared unit was one the rule pack expects for [nutrient].
  ///
  /// A signal for S8, not a verdict. `DATA_MODEL.md` §7.4: a unit outside the
  /// expected set **lowers confidence rather than failing the parse**, because
  /// an unusual label is not the same thing as a misread one. True when the
  /// pack states no expectation, since absence of a rule is not evidence
  /// against the value.
  final bool unitWasExpected;

  /// Where the value sits on the label.
  final RegionRef region;

  /// Source indices of every element that contributed, ascending.
  final List<int> sourceIndices;

  /// The rule that resolved it (FR-PAR-13).
  final RuleId matchedBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TypedField &&
          nutrient == other.nutrient &&
          quantity == other.quantity &&
          basis == other.basis &&
          declaredAs == other.declaredAs &&
          labelStrength == other.labelStrength &&
          basisStrength == other.basisStrength &&
          unitStrength == other.unitStrength &&
          unitWasExpected == other.unitWasExpected &&
          region == other.region &&
          matchedBy == other.matchedBy &&
          _sameInts(sourceIndices, other.sourceIndices) &&
          _sameSubstitutions(substitutions, other.substitutions);

  @override
  int get hashCode => Object.hash(
        nutrient,
        quantity,
        basis,
        declaredAs,
        labelStrength,
        basisStrength,
        unitStrength,
        unitWasExpected,
        region,
        matchedBy,
        Object.hashAll(sourceIndices),
        Object.hashAll(substitutions),
      );

  @override
  String toString() => 'TypedField(${nutrient.name}, $quantity, ${basis.name})';
}

/// The output of S6 — typed values, ready for S7's invariants.
final class TypedFields {
  /// Records the typed result.
  TypedFields({
    List<TypedField> fields = const <TypedField>[],
    List<UnresolvedCandidate> unresolved = const <UnresolvedCandidate>[],
    List<IngredientToken> ingredientTokens = const <IngredientToken>[],
    this.nutritionPanelPresent = false,
    this.ingredientListPresent = false,
  })  : fields = List<TypedField>.unmodifiable(fields),
        unresolved = List<UnresolvedCandidate>.unmodifiable(unresolved),
        ingredientTokens = List<IngredientToken>.unmodifiable(ingredientTokens);

  /// Fields that typed successfully, in the order S5 resolved them.
  final List<TypedField> fields;

  /// Everything that could not be typed, from S5 and S6 alike (FR-ERR-03).
  final List<UnresolvedCandidate> unresolved;

  /// Ingredient tokens, carried through untouched.
  final List<IngredientToken> ingredientTokens;

  /// Whether S3 identified a nutrition panel at all.
  final bool nutritionPanelPresent;

  /// Whether S3 identified an ingredient list at all.
  final bool ingredientListPresent;

  /// The stage that produced this, recorded for diagnostics.
  PipelineStage get producedByStage => PipelineStage.unitNormalisation;

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
  String toString() => 'TypedFields(${fields.length} typed, '
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

bool _sameSubstitutions(List<Substitution> a, List<Substitution> b) {
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
