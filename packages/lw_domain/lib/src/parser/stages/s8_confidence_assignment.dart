import 'package:lw_domain/src/confidence/confidence.dart';
import 'package:lw_domain/src/confidence/confidence_policy.dart';
import 'package:lw_domain/src/confidence/confidence_signals.dart';
import 'package:lw_domain/src/confidence/scan_confidence.dart';
import 'package:lw_domain/src/invariants/invariant_result.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/scored_fields.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/parser/typed_fields.dart';
import 'package:lw_domain/src/parser/validated_fields.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/provenance.dart';
import 'package:lw_domain/src/version.dart';

/// **S8 — Confidence assignment.** How much of this should the user check?
///
/// Gathers the three signals for each typed field and asks the
/// [ConfidencePolicy] what they earn. **The stage orchestrates; the policy
/// decides.** No confidence level is chosen anywhere in this file: every level
/// comes back from `ConfidencePolicy.classify`, whose rules are rule pack data
/// (ADR-0010, ADR-0012, `ARCHITECTURE.md` §7.2). That separation is what lets
/// the assignment be tuned from corpus calibration without a code change, and
/// what stops a second source of truth appearing for the number this product's
/// honesty rests on.
///
/// **FR-CNF-05 remains absolute** and is enforced by construction rather than
/// by a rule in this file: a field's `ConfidenceSignals` carry exactly the
/// invariants that field took part in, on its own basis, so the policy's
/// first rule — failed invariant means LOW — cannot be outvoted by an EXACT
/// parse. Capping by field rather than by invariant is what keeps a clean
/// sodium reading out of a fat reconciliation it took no part in.
///
/// **Values are never modified.** S7 judged the arithmetic and S8 judges the
/// reading; neither corrects. Adjusting a value here would replace the
/// manufacturer's claim with our guess (P1).
///
/// Pure and total: no I/O, no clock, no randomness, no cached state
/// (FR-PAR-01), and every input yields a `StageResult` rather than an
/// exception (FR-PAR-17).
///
/// [rulePackVersion] is required because every extracted value must record the
/// pack in force (FR-KB-02). [policy] defaults to `ConfidencePolicy.defaults`,
/// which mirrors `rulepack/rules/confidence.json`.
StageResult<ScoredFields> assignConfidence(
  ValidatedFields validated, {
  required Version rulePackVersion,
  ConfidencePolicy? policy,
}) {
  if (!validated.nutritionPanelPresent && !validated.ingredientListPresent) {
    return const StageFailure<ScoredFields>(
      ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        stage: PipelineStage.confidenceAssignment,
      ),
    );
  }

  final ConfidencePolicy rules = policy ?? ConfidencePolicy.defaults;
  final List<ScoredField> scored = <ScoredField>[];

  for (final TypedField field in validated.fields) {
    final ConfidenceSignals signals = _signalsFor(field, validated);
    final Confidence level = rules.classify(signals);

    scored.add(
      ScoredField(
        nutrient: field.nutrient,
        basis: field.basis,
        state: ExtractedField(
          quantity: field.quantity,
          basis: field.basis,
          provenance: Provenance.extracted(
            producedByStage: PipelineStage.confidenceAssignment,
            parseRuleId: field.matchedBy,
            parseStrength: signals.s2ParseStrength,
            sourceRegion: field.region,
            rulePackVersion: rulePackVersion,
            substitutions: field.substitutions,
          ),
          confidence: level,
        ),
        signals: signals,
        region: field.region,
        sourceIndices: field.sourceIndices,
      ),
    );
  }

  return StageSuccess<ScoredFields>(
    ScoredFields(
      fields: scored,
      unresolved: validated.unresolved,
      invariantResults: validated.results,
      ingredientTokens: validated.ingredientTokens,
      serving: validated.serving,
      scanConfidence: _scanLevel(scored, validated),
      nutritionPanelPresent: validated.nutritionPanelPresent,
      ingredientListPresent: validated.ingredientListPresent,
    ),
  );
}

/// The three signals for one field.
///
/// **S3** is every invariant this field took part in, on its own basis or on
/// none. **S2** is the weakest of the parse strengths that produced it. **S1**
/// is absent.
ConfidenceSignals _signalsFor(TypedField field, ValidatedFields validated) {
  final InvariantSubject subject = NutrientSubject(field.nutrient);
  final List<InvariantResult> joined = <InvariantResult>[
    for (final InvariantResult r in validated.results)
      if ((r.basis == null || r.basis == field.basis) && r.involves(subject)) r,
  ];

  return ConfidenceSignals(
    s2ParseStrength: _weakestStrength(field),
    // S1 is deliberately absent, not defaulted. `NutritionCandidate` does not
    // carry the engine's per-element confidence forward from S1, and the Q2
    // spike that would settle whether the engine exposes a usable one has not
    // run. `ARCHITECTURE.md` §7.2 requires the model to work without it and
    // FR-CNF-03 requires the absence to be recorded rather than filled in.
    s3InvariantResults: joined,
  );
}

/// The weakest parse strength that contributed to this field.
///
/// **Signal aggregation, not a confidence decision.** `ARCHITECTURE.md` §7.1
/// makes propagation the meet: *"a derived value can never be more confident
/// than its least confident input."* An exact label read from a heuristically
/// identified column heading is a heuristic reading of that value, and taking
/// the strongest of the three would launder the weak part away.
///
/// An unexpected unit enters as `HEURISTIC` rather than failing the field.
/// `DATA_MODEL.md` §7.4 is explicit that a unit outside the pack's expected set
/// **lowers confidence rather than failing the parse** — an unusual label is
/// not the same thing as a misread one — and the meet is the mechanism §7.1
/// already provides for lowering it.
ParseStrength _weakestStrength(TypedField field) => <ParseStrength>[
      field.labelStrength,
      field.basisStrength,
      field.unitStrength,
      if (!field.unitWasExpected) ParseStrength.heuristic,
    ].reduce(_weaker);

ParseStrength _weaker(ParseStrength a, ParseStrength b) =>
    _rank(a) >= _rank(b) ? a : b;

/// Strongest first. An exhaustive switch, so a fourth parse strength cannot be
/// added without deciding where it sits.
int _rank(ParseStrength strength) => switch (strength) {
      ParseStrength.exact => 0,
      ParseStrength.normalised => 1,
      ParseStrength.heuristic => 2,
    };

/// The scan-level classification (`DATA_MODEL.md` §4.5).
///
/// A critical field counts as resolved when it was scored on **any** basis, or
/// — for the three pack figures — when it was declared. A nutrient declared on
/// two bases contributes the **weaker** of its levels, for the same reason S2
/// takes the meet: the column that read badly is the one worth telling the
/// user about.
ScanConfidence _scanLevel(
  List<ScoredField> scored,
  ValidatedFields validated,
) {
  final Map<NutrientId, Confidence> levels = <NutrientId, Confidence>{};
  for (final ScoredField f in scored) {
    if (!f.nutrient.isCritical) {
      continue;
    }
    final Confidence? level = f.confidence;
    if (level == null) {
      continue;
    }
    final Confidence? seen = levels[f.nutrient];
    levels[f.nutrient] = seen == null ? level : seen.meet(level);
  }

  final List<Quantity?> packFigures = <Quantity?>[
    validated.serving.servingSize,
    validated.serving.servingsPerPack,
    validated.serving.netQuantity,
  ];
  final int declaredPackFigures =
      packFigures.where((Quantity? q) => q != null).length;

  final bool everyCriticalResolved =
      levels.length == NutrientId.critical.length &&
          declaredPackFigures == packFigures.length;

  // The pack figures count toward presence but **not** toward the ratio. They
  // carry no confidence — no stage assigns one — so counting them in the
  // denominator would make HIGH unreachable for every label (9 classified
  // fields out of 12 is 75%, below the 80% bar, however clean the reading).
  // Counting them as HIGH would be worse: it would manufacture trust in a
  // reading no stage performed. §4.5's own "resolved" list has the same shape
  // for `UserSupplied`, which likewise carries no inferred level.
  return ScanConfidence.from(
    everyCriticalFieldResolved: everyCriticalResolved,
    resolvedCriticalCount: levels.length,
    highCriticalCount:
        levels.values.where((Confidence c) => c == Confidence.high).length,
    lowCriticalCount:
        levels.values.where((Confidence c) => c == Confidence.low).length,
    failedInvariantCount: validated.failures.length,
  );
}
