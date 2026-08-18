import 'package:lw_domain/src/label/category_id.dart';
import 'package:lw_domain/src/label/parsed_label.dart';
import 'package:lw_domain/src/parser/assemble_parsed_label.dart';
import 'package:lw_domain/src/parser/candidates.dart';
import 'package:lw_domain/src/parser/classified_regions.dart';
import 'package:lw_domain/src/parser/label_layout.dart';
import 'package:lw_domain/src/parser/normalised_text.dart';
import 'package:lw_domain/src/parser/recognition_result.dart';
import 'package:lw_domain/src/parser/resolved_fields.dart';
import 'package:lw_domain/src/parser/scored_fields.dart';
import 'package:lw_domain/src/parser/serving_resolution.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/parser/stages/s1_normalisation.dart';
import 'package:lw_domain/src/parser/stages/s2_layout.dart';
import 'package:lw_domain/src/parser/stages/s3_region_classification.dart';
import 'package:lw_domain/src/parser/stages/s4_tokenisation.dart';
import 'package:lw_domain/src/parser/stages/s5_field_resolution.dart';
import 'package:lw_domain/src/parser/stages/s5b_serving_resolution.dart';
import 'package:lw_domain/src/parser/stages/s6_unit_normalisation.dart';
import 'package:lw_domain/src/parser/stages/s7_invariant_evaluation.dart';
import 'package:lw_domain/src/parser/stages/s8_confidence_assignment.dart';
import 'package:lw_domain/src/parser/typed_fields.dart';
import 'package:lw_domain/src/parser/validated_fields.dart';
import 'package:lw_domain/src/rulepack/rule_pack.dart';

/// **The parse.** Recognised text and a rule pack in; a `ParsedLabel` out.
///
/// Every stage from M4 to M11 proved a contract in isolation. This composes
/// them, and composing is all it does: it holds no vocabulary, evaluates no
/// rule, and reaches no conclusion of its own. Anything it appeared to decide
/// would be a second implementation of a decision a stage already owns.
///
/// **Pure and total** (FR-PAR-01, FR-PAR-17). No I/O, no clock, no locale, no
/// randomness — the only inputs are [input] and [pack], so identical arguments
/// produce identical output on every run and platform (FR-PAR-02).
///
/// > **Why this is one function rather than a pipeline object.** A builder
/// > holding state between stages would make `ARCHITECTURE.md` §6.4's
/// > correction re-entry impossible: FR-COR-02 requires re-running from S7 with
/// > a field set mixing extracted and user-supplied values, which only works
/// > while every stage stays a free function callable on its own. This adds a
/// > way to run them in order; it does not become the only way to run them.
///
/// **First failure wins.** A stage that declines ends the parse, and its
/// `ParseFailure` travels to the caller **unchanged** — same kind, same stage,
/// same region, same message id. Rewrapping it would make `failure.stage` name
/// this function instead of the stage that actually stopped, and that field is
/// what a correction UI uses to tell the user which part of the photo to
/// retake.
///
/// **Partial input needs no branch here.** S3 declines only when *neither*
/// region is found; S4 records which regions were present and every later stage
/// carries those flags forward. A panel without an ingredient list, or an
/// ingredient list without a panel, therefore produces a complete result for
/// the portion supplied (FR-PAR-14) through the ordinary path. Adding an
/// `if` for it here would duplicate a decision S3 and S4 already make, and two
/// implementations of one rule eventually disagree.
///
/// [declaredCategory] and [unsupportedScript] are recorded, never inferred. No
/// stage determines a category (FR-CAT-02), and S1 refuses an unreadable script
/// through `StageResult` rather than by setting a flag — so a caller that knows
/// the script was unsupported says so, and this function does not guess.
StageResult<ParsedLabel> parseLabel(
  RecognitionResult input, {
  required RulePack pack,
  CategoryId? declaredCategory,
  bool unsupportedScript = false,
}) {
  // S1 — normalisation.
  final StageResult<NormalisedText> s1 = normaliseText(input);
  final NormalisedText? normalised = s1.valueOrNull;
  if (normalised == null) {
    return StageFailure<ParsedLabel>(s1.failureOrNull!);
  }

  // S2 — layout reconstruction.
  final StageResult<LabelLayout> s2 = reconstructLayout(normalised);
  final LabelLayout? layout = s2.valueOrNull;
  if (layout == null) {
    return StageFailure<ParsedLabel>(s2.failureOrNull!);
  }

  // S3 — region classification.
  final StageResult<ClassifiedRegions> s3 = classifyRegions(layout);
  final ClassifiedRegions? regions = s3.valueOrNull;
  if (regions == null) {
    return StageFailure<ParsedLabel>(s3.failureOrNull!);
  }

  // S4 — tokenisation.
  final StageResult<Candidates> s4 = tokenise(regions);
  final Candidates? candidates = s4.valueOrNull;
  if (candidates == null) {
    return StageFailure<ParsedLabel>(s4.failureOrNull!);
  }

  // S5 — field resolution.
  final StageResult<ResolvedFields> s5 =
      resolveFields(candidates, synonyms: pack.synonyms);
  final ResolvedFields? resolved = s5.valueOrNull;
  if (resolved == null) {
    return StageFailure<ParsedLabel>(s5.failureOrNull!);
  }

  // S5b — serving resolution.
  //
  // Reads the **same** `ClassifiedRegions` S3 produced, not a re-derived view
  // of the label. The serving figures and the nutrient figures must be read
  // from one classification or they can disagree about which text is the
  // panel — and a serving size read from the wrong region scales every
  // per-serve figure derived from it.
  final StageResult<ServingResolution> s5b = resolveServing(regions);
  final ServingResolution? servingResolution = s5b.valueOrNull;
  if (servingResolution == null) {
    return StageFailure<ParsedLabel>(s5b.failureOrNull!);
  }

  // S6 — unit normalisation.
  final StageResult<TypedFields> s6 =
      normaliseUnits(resolved, synonyms: pack.synonyms);
  final TypedFields? typed = s6.valueOrNull;
  if (typed == null) {
    return StageFailure<ParsedLabel>(s6.failureOrNull!);
  }

  // S7 — invariant evaluation.
  //
  // Takes `servingResolution.facts`: the figures the invariants may use, which
  // hold only what S5b actually resolved. An unresolved or undeclared figure
  // is absent from `facts` and the serving invariants report themselves
  // inapplicable rather than being evaluated against a guess (MI-08).
  final StageResult<ValidatedFields> s7 = evaluateInvariants(
    typed,
    serving: servingResolution.facts,
    tolerances: pack.tolerances,
    deltas: pack.approximationDeltas,
    category: declaredCategory,
    categories: pack.categories,
  );
  final ValidatedFields? validated = s7.valueOrNull;
  if (validated == null) {
    return StageFailure<ParsedLabel>(s7.failureOrNull!);
  }

  // S8 — confidence assignment.
  //
  // Takes the whole `ServingResolution`, not just its facts. S8 scores serving
  // fields through the same `ConfidencePolicy` as nutrient fields (M11a), and
  // that needs the outcomes — a figure that was found and refused is scored
  // differently from one the label never declared, which `facts` alone cannot
  // express.
  final StageResult<ScoredFields> s8 = assignConfidence(
    validated,
    rulePackVersion: pack.version,
    policy: pack.confidencePolicy,
    servingResolution: servingResolution,
  );
  final ScoredFields? scored = s8.valueOrNull;
  if (scored == null) {
    return StageFailure<ParsedLabel>(s8.failureOrNull!);
  }

  // Assembly — shape, not judgement.
  return assembleParsedLabel(
    scored,
    rulePackVersion: pack.version,
    declaredCategory: declaredCategory,
    unsupportedScript: unsupportedScript,
  );
}
