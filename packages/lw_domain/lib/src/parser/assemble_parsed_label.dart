import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/category_id.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/ingredient.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/parsed_label.dart';
import 'package:lw_domain/src/parser/candidates.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/scored_fields.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/provenance.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';
import 'package:lw_domain/src/version.dart';

/// Rule identifiers the assembler attributes its output to.
final class _AssemblyRules {
  const _AssemblyRules._();

  /// An ingredient carried from S4's tokenisation.
  static final RuleId ingredient = RuleId('rule.tokenise.ingredient');

  /// A serving figure no stage attempted to read.
  static final RuleId servingUnresolved =
      RuleId('rule.assemble.serving-unresolved');
}

/// Assembles the parser's published boundary object.
///
/// **Not a pipeline stage.** S1–S8 transform; this shapes their result into the
/// one type the analysis layer is allowed to depend on (AR5). It is separated
/// from S8 because `ParsedLabel` needs things no stage produces — see the
/// limitations below — and folding those into S8 would have required inventing
/// them.
///
/// **The parser stops here.** Findings, serving reconciliation, additive
/// identification, %RDA and advice are Layer 1 and Layer 2 work
/// (`ROADMAP.md` §4.3, §4.6).
///
/// Pure, total and deterministic: nutrients are emitted in `NutrientId`
/// declaration order rather than the order they happened to be read, so the
/// output cannot depend on how the panel was laid out (FR-PAR-02).
///
/// Fails with `regionNotFound` when neither region was present — the same
/// guard every stage from S3 onward applies, so an empty result is never
/// mistaken for a parsed label (FR-PAR-17).
StageResult<ParsedLabel> assembleParsedLabel(
  ScoredFields scored, {
  required Version rulePackVersion,
  CategoryId? declaredCategory,
  bool unsupportedScript = false,
}) {
  if (!scored.nutritionPanelPresent && !scored.ingredientListPresent) {
    return const StageFailure<ParsedLabel>(
      ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        // No `PipelineStage` names assembly: S8 is the last stage, and adding
        // a ninth would misrepresent this as a transform.
        stage: PipelineStage.confidenceAssignment,
      ),
    );
  }

  return StageSuccess<ParsedLabel>(
    ParsedLabel(
      nutrients: _nutrients(scored),
      servingInfo: _servingInfo(rulePackVersion),
      ingredients: <Ingredient>[
        for (final IngredientToken t in scored.ingredientTokens)
          _ingredient(t, rulePackVersion),
      ],
      invariantResults: scored.invariantResults,
      scanConfidence: scored.scanConfidence,
      rulePackVersion: rulePackVersion,
      declaredCategory: declaredCategory,
      unsupportedScript: unsupportedScript,
    ),
  );
}

/// One `NutrientField` per nutrient that was read, in declaration order.
///
/// A nutrient with no scored field gets **no entry at all**, which is not the
/// same as an entry declaring nothing: "we have no record of this" and "we
/// have a record saying nothing was declared" are different facts, and
/// FR-ERR-03 turns on keeping such pairs apart.
List<NutrientField> _nutrients(ScoredFields scored) {
  final List<NutrientField> out = <NutrientField>[];
  for (final NutrientId nutrient in NutrientId.values) {
    final List<ScoredField> mine = <ScoredField>[
      for (final ScoredField f in scored.fields)
        if (f.nutrient == nutrient) f,
    ];
    if (mine.isEmpty) {
      continue;
    }
    out.add(
      NutrientField(
        nutrient: nutrient,
        perHundred: _slot(mine, const <Basis>[Basis.per100g, Basis.per100ml]),
        perServe: _slot(mine, const <Basis>[Basis.perServe]),
        perPack: _slot(mine, const <Basis>[Basis.perPack]),
      ),
    );
  }
  return out;
}

/// The field for whichever of [accepted] the label declared.
///
/// `perHundred` accepts two bases because it is a **storage slot, not a
/// semantic basis** (owner decision D1): a beverage declares per 100 ml where a
/// biscuit declares per 100 g, and both belong in the same slot. The semantic
/// basis is read from the returned field, never inferred from the slot. Where
/// a label improbably declares both, the first in [accepted] wins, so the
/// choice is fixed rather than dependent on read order (FR-PAR-02).
///
/// Absent means `NotDeclaredField` — never `UnresolvedField`, which would blame
/// us for a manufacturer's choice, and never `DerivedField`, because deriving
/// per-serve from per-100 g is Layer 1's arithmetic and not the parser's.
FieldState _slot(List<ScoredField> fields, List<Basis> accepted) {
  for (final Basis basis in accepted) {
    for (final ScoredField f in fields) {
      if (f.basis == basis) {
        return f.state;
      }
    }
  }
  return const NotDeclaredField();
}

/// The pack figures, all unresolved (owner decision D2).
///
/// No stage reads serving size, servings per pack or net quantity: the rule
/// pack carries no wordings for them, so a candidate bearing one fails S5 with
/// `noMatchingRule` and lands in the unresolved list. S8 correspondingly
/// assigns them no confidence, so an `ExtractedField` here would require
/// inventing one.
///
/// **This is the honest output, and it has a known cost:** the parser cannot
/// distinguish "the label declares no serving size" from "we could not read
/// it", and always reports the latter. That is the safer of the two errors —
/// we never accuse a manufacturer of an omission we invented — but it is a
/// real FR-ERR-03 limitation, and the milestone that adds serving resolution
/// must route those figures through S8 rather than around it.
///
/// The provenance is `derived` rather than `extracted` for a structural
/// reason: a figure we never located has no position on the label, and
/// `Provenance.derived` is the only factory that carries a stage, a rule and a
/// pack version without demanding a `sourceRegion`.
ServingInfo _servingInfo(Version rulePackVersion) {
  FieldState unread() => UnresolvedField(
        reason: UnresolvedReason.noMatchingRule,
        provenance: Provenance.derived(
          producedByStage: PipelineStage.fieldResolution,
          parseRuleId: _AssemblyRules.servingUnresolved,
          rulePackVersion: rulePackVersion,
        ),
      );

  return ServingInfo(
    declaredServingSize: unread(),
    servingsPerPack: unread(),
    netQuantity: unread(),
  );
}

/// One `Ingredient` per token, nesting preserved (FR-PAR-12).
///
/// `identification` is left null throughout: additive identification is Layer 1
/// work (`ROADMAP.md` §4.3 item 4.4). Null is **not** `Unidentified` — that
/// variant records an attempt that failed, and the parser makes no attempt.
Ingredient _ingredient(IngredientToken token, Version rulePackVersion) =>
    Ingredient(
      position: token.position,
      rawText: token.rawText,
      provenance: Provenance.extracted(
        producedByStage: PipelineStage.tokenisation,
        parseRuleId: _AssemblyRules.ingredient,
        parseStrength: token.parseStrength,
        sourceRegion: token.region,
        rulePackVersion: rulePackVersion,
      ),
      subIngredients: <Ingredient>[
        for (final IngredientToken child in token.children)
          _ingredient(child, rulePackVersion),
      ],
    );
