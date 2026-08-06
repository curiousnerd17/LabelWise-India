import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/parser/basis_markers.dart';
import 'package:lw_domain/src/parser/candidates.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/resolved_fields.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';
import 'package:lw_domain/src/rules/synonym_table.dart';

/// Rule identifiers S5 attributes its resolutions to.
final class _S5Rules {
  const _S5Rules._();

  /// A label matched the rule pack synonym table.
  static final RuleId synonym = RuleId('rule.resolve.synonym');
}

/// **S5 — Field resolution.** Which nutrient, against which reference.
///
/// Maps candidate label text to a canonical `NutrientId` through the synonym
/// table **held in the rule pack** (`ARCHITECTURE.md` §6.3, ADR-0012), and
/// assigns a `Basis` from the column heading S4 carried across.
///
/// This is the first stage that holds nutrition knowledge. S1–S4 are
/// deliberately domain independent so a cosmetics module can reuse them
/// (`ARCHITECTURE.md` §11); S5 is where that reuse boundary ends.
///
/// **No `Quantity` is built here and no confidence is assigned.** Typing is
/// S6's job, and confidence assignment is S8's — per ADR-0010 the assignment
/// function is rule pack data combining signals S1, S2 and S3. S5 records the
/// S2 signals it observed (label strength, basis strength) and stops.
///
/// Pure and total: no I/O, no clock, no randomness (FR-PAR-01), and every
/// input yields a `StageResult` rather than an exception (FR-PAR-17).
///
/// [bases] defaults to `BasisMarkerTable.defaults` when omitted. It is a
/// nullable parameter rather than a defaulted one only because Dart requires
/// default values to be compile-time constants, and a marker is validated at
/// construction.
StageResult<ResolvedFields> resolveFields(
  Candidates candidates, {
  required SynonymTable synonyms,
  BasisMarkerTable? bases,
}) {
  // FR-PAR-17: nothing to resolve is a structured failure, not an empty
  // success. S4 declines a label with no region, so reaching this means S5 was
  // called with an empty result.
  if (!candidates.nutritionPanelPresent && !candidates.ingredientListPresent) {
    return const StageFailure<ResolvedFields>(
      ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        stage: PipelineStage.fieldResolution,
      ),
    );
  }

  final BasisMarkerTable basisTable = bases ?? BasisMarkerTable.defaults;
  final List<ResolvedField> resolved = <ResolvedField>[];
  final List<UnresolvedCandidate> unresolved = <UnresolvedCandidate>[];

  for (final NutritionCandidate c in candidates.nutritionCandidates) {
    final SynonymMatch? match = synonyms.match(c.labelText);
    if (match == null) {
      unresolved.add(_declined(c, UnresolvedReason.noMatchingRule));
      continue;
    }

    final BasisMarker? basis = _basisFor(c, candidates, basisTable);
    if (basis == null) {
      // A right value on the wrong basis is wrong by a factor of three or
      // more. FR-PAR-05 requires silence over a default.
      unresolved.add(_declined(c, UnresolvedReason.basisNotDetermined));
      continue;
    }

    resolved.add(
      ResolvedField(
        nutrient: match.nutrient,
        valueText: c.valueText,
        unitText: c.unitText,
        qualifier: c.qualifier,
        basis: basis.basis,
        labelStrength: match.strength,
        basisStrength: basis.strength,
        region: c.region,
        sourceIndices: c.sourceIndices,
        matchedBy: _S5Rules.synonym,
      ),
    );
  }

  final _Deduplicated deduplicated = _rejectDuplicates(resolved, candidates);
  unresolved.addAll(deduplicated.ambiguous);

  return StageSuccess<ResolvedFields>(
    ResolvedFields(
      fields: deduplicated.kept,
      unresolved: unresolved,
      ingredientTokens: candidates.ingredientTokens,
      nutritionPanelPresent: candidates.nutritionPanelPresent,
      ingredientListPresent: candidates.ingredientListPresent,
    ),
  );
}

/// The basis declared by the heading above this candidate's column band.
///
/// Null at three distinct points — no band, no heading above the band, or a
/// heading that declares no basis — and all three are the same outcome for the
/// caller: the field is unresolved rather than defaulted.
BasisMarker? _basisFor(
  NutritionCandidate candidate,
  Candidates candidates,
  BasisMarkerTable table,
) {
  final int? band = candidate.columnIndex;
  if (band == null) {
    return null;
  }
  final ColumnHeader? header = candidates.headerFor(band);
  if (header == null) {
    return null;
  }
  return table.strongestMatch(header.text);
}

UnresolvedCandidate _declined(
  NutritionCandidate candidate,
  UnresolvedReason reason,
) =>
    UnresolvedCandidate(
      reason: reason,
      labelText: candidate.labelText,
      region: candidate.region,
      sourceIndices: candidate.sourceIndices,
    );

final class _Deduplicated {
  const _Deduplicated(this.kept, this.ambiguous);

  final List<ResolvedField> kept;
  final List<UnresolvedCandidate> ambiguous;
}

/// Rejects every field whose `(nutrient, basis)` pair appears more than once.
///
/// OCR duplicates lines. Two protein figures for the same basis is a genuine
/// conflict, and keeping either one would let a later stage present an
/// arbitrary choice as a fact. Rejecting **both** is the honest outcome, and
/// `UnresolvedReason.ambiguousMatch` exists for exactly this.
///
/// The same nutrient on two *different* bases is not a conflict — per-100 g
/// and per-serve protein are two legitimate declarations, and treating them as
/// one would discard half the panel.
_Deduplicated _rejectDuplicates(
  List<ResolvedField> fields,
  Candidates candidates,
) {
  final Map<String, int> counts = <String, int>{};
  for (final ResolvedField f in fields) {
    final String key = _key(f.nutrient, f.basis);
    counts[key] = (counts[key] ?? 0) + 1;
  }

  final List<ResolvedField> kept = <ResolvedField>[];
  final List<UnresolvedCandidate> ambiguous = <UnresolvedCandidate>[];
  for (final ResolvedField f in fields) {
    if ((counts[_key(f.nutrient, f.basis)] ?? 0) > 1) {
      ambiguous.add(
        UnresolvedCandidate(
          reason: UnresolvedReason.ambiguousMatch,
          labelText: _labelOf(f, candidates),
          region: f.region,
          sourceIndices: f.sourceIndices,
        ),
      );
      continue;
    }
    kept.add(f);
  }
  return _Deduplicated(kept, ambiguous);
}

String _key(NutrientId nutrient, Basis basis) =>
    '${nutrient.name}|${basis.name}';

/// The candidate wording behind a resolved field, so the rejection stays
/// traceable to what was printed rather than to the nutrient it resolved to.
String _labelOf(ResolvedField field, Candidates candidates) {
  for (final NutritionCandidate c in candidates.nutritionCandidates) {
    if (c.region == field.region && c.valueText == field.valueText) {
      return c.labelText;
    }
  }
  return field.nutrient.name;
}
