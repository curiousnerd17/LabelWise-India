import 'package:lw_domain/src/label/qualifier.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';

/// What one column band of the nutrition panel is headed by.
///
/// S4 carries this because S5 is required to "assign basis from column
/// headers" (`ARCHITECTURE.md` §6.1) and its only input is `Candidates`. A
/// column *index* says which band a value sits in; only the header says what
/// that band means, and `Per 100 g` against `Per Serve` is a factor of three
/// or more — the highest-harm error this parser can make.
///
/// S4 does not interpret the wording. Reading `Per 100 g` as a basis is S5's
/// job, because basis vocabulary is nutrition-specific and S1–S4 stay domain
/// independent (`ARCHITECTURE.md` §11).
final class ColumnHeader {
  /// Records a band's heading.
  ///
  /// Throws [ArgumentError] when [columnIndex] is negative, when [text] is
  /// blank, or when [sourceIndices] is empty — a heading that traces to no
  /// recognised element could not have been read off the label.
  ColumnHeader({
    required this.columnIndex,
    required this.text,
    required this.region,
    required List<int> sourceIndices,
  }) : sourceIndices = List<int>.unmodifiable(sourceIndices) {
    if (columnIndex < 0) {
      throw ArgumentError.value(
        columnIndex,
        'columnIndex',
        'Column bands are indexed from zero.',
      );
    }
    if (text.trim().isEmpty) {
      throw ArgumentError.value(
        text,
        'text',
        'A heading without text names nothing.',
      );
    }
    if (sourceIndices.isEmpty) {
      throw ArgumentError.value(
        sourceIndices,
        'sourceIndices',
        'A heading must trace to at least one recognised element.',
      );
    }
  }

  /// The S2 band this heading sits above.
  final int columnIndex;

  /// The heading as printed, before any interpretation.
  final String text;

  /// Where the heading sits on the label.
  final RegionRef region;

  /// Source indices of the elements that formed it, ascending.
  final List<int> sourceIndices;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColumnHeader &&
          columnIndex == other.columnIndex &&
          text == other.text &&
          region == other.region &&
          _sameInts(sourceIndices, other.sourceIndices);

  @override
  int get hashCode => Object.hash(
        columnIndex,
        text,
        region,
        Object.hashAll(sourceIndices),
      );

  @override
  String toString() => 'ColumnHeader($columnIndex, "$text")';
}

/// One `(label, value, unit?, qualifier)` quadruple read off the panel.
///
/// **Text, not `Quantity`.** A quantity requires a unit (MI-03), and unit
/// normalisation is S6's job — `g`, `gm`, `gms`, `kcal` are nutrition-domain
/// knowledge that S1–S4 must not acquire if they are to stay reusable
/// (`ARCHITECTURE.md` §11). S4 reads the shapes; S5 and S6 give them meaning.
///
/// The qualifier is the one exception, and only because it is lexical rather
/// than semantic: `<` means the same on any label (ADR-0027, FR-PAR-18).
final class NutritionCandidate {
  /// Records a candidate.
  ///
  /// Throws [ArgumentError] when [labelText] or [valueText] is blank, or when
  /// [sourceIndices] is empty — a candidate that traces to no recognised
  /// element is a value with no origin, which §8.3 of `ARCHITECTURE.md`
  /// forbids outright.
  NutritionCandidate({
    required this.labelText,
    required this.valueText,
    required this.region,
    required List<int> sourceIndices,
    required this.parseStrength,
    this.unitText,
    this.qualifier = Qualifier.exact,
    this.columnIndex,
  }) : sourceIndices = List<int>.unmodifiable(sourceIndices) {
    if (labelText.trim().isEmpty) {
      throw ArgumentError.value(
        labelText,
        'labelText',
        'A candidate without a label cannot be resolved to a nutrient.',
      );
    }
    if (valueText.trim().isEmpty) {
      throw ArgumentError.value(
        valueText,
        'valueText',
        'A candidate without a value declares nothing.',
      );
    }
    if (sourceIndices.isEmpty) {
      throw ArgumentError.value(
        sourceIndices,
        'sourceIndices',
        'A candidate must trace to at least one recognised element.',
      );
    }
  }

  /// The wording to the left of the value, as printed. S5 resolves it.
  final String labelText;

  /// The number as printed, with any qualifier marker removed.
  final String valueText;

  /// The unit as printed, or null when the line carried none.
  ///
  /// Null is the honest reading, not a defect. FR-PAR-05 forbids emitting a
  /// value whose unit could not be determined, so S5 turns this into an
  /// unresolved field rather than S4 inventing a unit.
  final String? unitText;

  /// The qualifier read off the value (FR-PAR-18). `Qualifier.exact` when the
  /// value carried no marker.
  final Qualifier qualifier;

  /// The S2 column band this candidate's value sits in, or null when no band
  /// claimed it. S5 turns a column into a `Basis`.
  final int? columnIndex;

  /// Where the candidate sits on the label.
  final RegionRef region;

  /// Source indices of every element that contributed, ascending.
  final List<int> sourceIndices;

  /// How firmly the line parsed — signal S2, carried into confidence.
  final ParseStrength parseStrength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutritionCandidate &&
          labelText == other.labelText &&
          valueText == other.valueText &&
          unitText == other.unitText &&
          qualifier == other.qualifier &&
          columnIndex == other.columnIndex &&
          region == other.region &&
          parseStrength == other.parseStrength &&
          _sameInts(sourceIndices, other.sourceIndices);

  @override
  int get hashCode => Object.hash(
        labelText,
        valueText,
        unitText,
        qualifier,
        columnIndex,
        region,
        parseStrength,
        Object.hashAll(sourceIndices),
      );

  @override
  String toString() => 'NutritionCandidate("$labelText" = '
      '${qualifier.name} "$valueText" ${unitText ?? "?"})';
}

/// One entry in the declared ingredient list, with its nesting intact.
///
/// Mirrors `DATA_MODEL.md` §5.4: [position] is 1-based because declaration
/// order is legally meaningful — Indian labelling requires descending order by
/// weight, so the first ingredient is the largest component and losing the
/// order destroys the only quantitative information the list carries.
final class IngredientToken {
  /// Records a token.
  ///
  /// Throws [ArgumentError] when [position] is below 1, when [rawText] is
  /// blank, or when [sourceIndices] is empty.
  IngredientToken({
    required this.position,
    required this.rawText,
    required this.region,
    required List<int> sourceIndices,
    required this.parseStrength,
    List<IngredientToken> children = const <IngredientToken>[],
  })  : sourceIndices = List<int>.unmodifiable(sourceIndices),
        children = List<IngredientToken>.unmodifiable(children) {
    if (position < 1) {
      throw ArgumentError.value(
        position,
        'position',
        'Declaration position is 1-based.',
      );
    }
    if (rawText.trim().isEmpty) {
      throw ArgumentError.value(
        rawText,
        'rawText',
        'An ingredient without text declares nothing.',
      );
    }
    if (sourceIndices.isEmpty) {
      throw ArgumentError.value(
        sourceIndices,
        'sourceIndices',
        'An ingredient must trace to at least one recognised element.',
      );
    }
  }

  /// 1-based position among its siblings. Legally meaningful (FR-PAR-10).
  final int position;

  /// The text as recognised, before any interpretation.
  final String rawText;

  /// Parenthetical sub-ingredients, in declaration order (FR-PAR-12).
  ///
  /// Empty for a plain ingredient. Nesting is preserved rather than flattened
  /// because `Emulsifier (INS 322)` says something a flat list cannot: which
  /// additive belongs to which class title.
  final List<IngredientToken> children;

  /// Where the entry sits on the label.
  final RegionRef region;

  /// Source indices of the elements that contributed, ascending.
  final List<int> sourceIndices;

  /// How cleanly it parsed. `ParseStrength.heuristic` when the structure had
  /// to be repaired — an unclosed bracket, for instance.
  final ParseStrength parseStrength;

  /// This token's own indices plus every descendant's, ascending.
  List<int> get allSourceIndices {
    final List<int> all = <int>[
      ...sourceIndices,
      for (final IngredientToken c in children) ...c.allSourceIndices,
    ]..sort();
    return List<int>.unmodifiable(all);
  }

  /// Nesting depth, counting this token as 1.
  int get depth {
    int deepest = 0;
    for (final IngredientToken c in children) {
      if (c.depth > deepest) {
        deepest = c.depth;
      }
    }
    return 1 + deepest;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IngredientToken &&
          position == other.position &&
          rawText == other.rawText &&
          region == other.region &&
          parseStrength == other.parseStrength &&
          _sameInts(sourceIndices, other.sourceIndices) &&
          _sameTokens(children, other.children);

  @override
  int get hashCode => Object.hash(
        position,
        rawText,
        region,
        parseStrength,
        Object.hashAll(sourceIndices),
        Object.hashAll(children),
      );

  @override
  String toString() =>
      'IngredientToken($position, "$rawText", ${children.length} nested)';
}

/// The output of S4 — candidate shapes, with no meaning attached yet.
final class Candidates {
  /// Records the tokenisation.
  Candidates({
    List<NutritionCandidate> nutritionCandidates = const <NutritionCandidate>[],
    List<IngredientToken> ingredientTokens = const <IngredientToken>[],
    List<ColumnHeader> columnHeaders = const <ColumnHeader>[],
    this.nutritionPanelPresent = false,
    this.ingredientListPresent = false,
  })  : nutritionCandidates =
            List<NutritionCandidate>.unmodifiable(nutritionCandidates),
        ingredientTokens = List<IngredientToken>.unmodifiable(ingredientTokens),
        columnHeaders = List<ColumnHeader>.unmodifiable(columnHeaders);

  /// Candidate quadruples from the nutrition panel, in reading order.
  final List<NutritionCandidate> nutritionCandidates;

  /// Ingredient entries, in declaration order (MI-12, PT-10).
  final List<IngredientToken> ingredientTokens;

  /// Whether S3 identified a nutrition panel at all.
  ///
  /// Carries the FR-ERR-03 distinction across the stage boundary. An empty
  /// [nutritionCandidates] with this true means "the panel was there and we
  /// could not read it"; with this false it means "the label declares none".
  /// Without the flag S5 would see one empty list and could not tell which.
  final bool nutritionPanelPresent;

  /// Whether S3 identified an ingredient list at all. See
  /// [nutritionPanelPresent].
  final bool ingredientListPresent;

  /// What each column band of the nutrition panel is headed by.
  ///
  /// Empty when the panel is single-column with no heading, or when S2 found
  /// no bands. S5 then has no evidence of a basis and must report the field
  /// unresolved rather than assume one (FR-PAR-05).
  final List<ColumnHeader> columnHeaders;

  /// The heading above band [columnIndex], or null when there is none.
  ///
  /// Null is the honest answer, not a defect: an absent heading means S5 must
  /// decline to assign a basis rather than guess one.
  ColumnHeader? headerFor(int columnIndex) {
    for (final ColumnHeader h in columnHeaders) {
      if (h.columnIndex == columnIndex) {
        return h;
      }
    }
    return null;
  }

  /// The stage that produced this, recorded for diagnostics.
  PipelineStage get producedByStage => PipelineStage.tokenisation;

  /// Whether any nutrition candidate was found.
  bool get hasNutrition => nutritionCandidates.isNotEmpty;

  /// Whether any ingredient entry was found.
  bool get hasIngredients => ingredientTokens.isNotEmpty;

  /// Every source index reached by either half, ascending.
  List<int> get sourceIndices {
    final List<int> all = <int>[
      for (final NutritionCandidate c in nutritionCandidates)
        ...c.sourceIndices,
      for (final IngredientToken t in ingredientTokens) ...t.allSourceIndices,
    ]..sort();
    return List<int>.unmodifiable(all);
  }

  @override
  String toString() => 'Candidates(${nutritionCandidates.length} nutrition, '
      '${ingredientTokens.length} ingredients)';
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

bool _sameTokens(List<IngredientToken> a, List<IngredientToken> b) {
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
