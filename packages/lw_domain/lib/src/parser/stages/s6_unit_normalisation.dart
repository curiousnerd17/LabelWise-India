import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/label/rounding.dart';
import 'package:lw_domain/src/label/unit.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/resolved_fields.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/parser/typed_fields.dart';
import 'package:lw_domain/src/parser/unit_lexicon.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';
import 'package:lw_domain/src/provenance/substitution.dart';
import 'package:lw_domain/src/rules/synonym_table.dart';

/// Rule identifiers S6 attributes its transformations to.
final class _S6Rules {
  const _S6Rules._();

  /// A printed unit mapped to its canonical form.
  static final RuleId unit = RuleId('rule.normalise.unit');

  /// Kilojoules converted to kilocalories.
  static final RuleId energy = RuleId('rule.normalise.energy');
}

/// **S6 — Unit normalisation.** Text becomes a typed `Quantity`.
///
/// Maps every printed unit variant to a canonical `Unit` and records that it
/// did (FR-PAR-06), builds a scaled-integer `Quantity` at that unit's tracked
/// precision, and converts kilojoules to kilocalories while retaining the
/// original declaration (FR-PAR-07).
///
/// **Variant normalisation is not magnitude conversion.** `gm` becomes `g`
/// because they are the same unit spelled differently. `mg` does **not** become
/// `g`: grams track hundredths, so 250 mg would round to 0.25 g and a
/// declaration the label made precisely would come back coarser than it was
/// printed. Only energy is converted, because FR-PAR-07 requires it.
///
/// **No confidence is assigned.** S6 records the signals — unit strength and
/// whether the unit was one the rule pack expects — and stops. Assignment is
/// S8's, from a function held in the rule pack (ADR-0010).
///
/// Pure and total: no I/O, no clock, no randomness (FR-PAR-01), and every
/// input yields a `StageResult` rather than an exception (FR-PAR-17).
///
/// [units] defaults to `UnitLexicon.defaults` when omitted. It is a nullable
/// parameter rather than a defaulted one only because Dart requires default
/// values to be compile-time constants, and a variant is validated at
/// construction.
StageResult<TypedFields> normaliseUnits(
  ResolvedFields resolved, {
  required SynonymTable synonyms,
  UnitLexicon? units,
}) {
  if (!resolved.nutritionPanelPresent && !resolved.ingredientListPresent) {
    return const StageFailure<TypedFields>(
      ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        stage: PipelineStage.unitNormalisation,
      ),
    );
  }

  final UnitLexicon lexicon = units ?? UnitLexicon.defaults;
  final List<TypedField> typed = <TypedField>[];
  final List<UnresolvedCandidate> unresolved = <UnresolvedCandidate>[
    // S5's failures are carried, not re-derived. FR-ERR-03 needs every
    // failure to survive to the end of the pipeline.
    ...resolved.unresolved,
  ];

  for (final ResolvedField f in resolved.fields) {
    final String? printed = f.unitText;
    if (printed == null) {
      unresolved.add(_declined(f, UnresolvedReason.unitNotDetermined));
      continue;
    }
    final UnitVariant? variant = lexicon.resolve(printed);
    if (variant == null) {
      unresolved.add(_declined(f, UnresolvedReason.unitNotDetermined));
      continue;
    }
    final int? scaled = _parseScaled(f.valueText, variant.unit);
    if (scaled == null) {
      unresolved.add(_declined(f, UnresolvedReason.valueNotParseable));
      continue;
    }

    final List<Substitution> substitutions = <Substitution>[];
    final String canonical = variant.unit.symbol;
    if (printed.trim() != canonical) {
      substitutions.add(
        Substitution(
          kind: SubstitutionKind.unitNormalisation,
          before: printed.trim(),
          after: canonical,
          appliedByRuleId: _S6Rules.unit,
        ),
      );
    }

    final Quantity declared =
        Quantity.qualified(scaled, variant.unit, f.qualifier);
    final Quantity value = _canonicalise(declared, substitutions);

    typed.add(
      TypedField(
        nutrient: f.nutrient,
        quantity: value,
        basis: f.basis,
        declaredAs: value == declared ? null : declared,
        substitutions: substitutions,
        labelStrength: f.labelStrength,
        basisStrength: f.basisStrength,
        unitStrength: variant.strength,
        unitWasExpected: _wasExpected(synonyms, f, variant.unit),
        region: f.region,
        sourceIndices: f.sourceIndices,
        matchedBy: f.matchedBy,
      ),
    );
  }

  return StageSuccess<TypedFields>(
    TypedFields(
      fields: typed,
      unresolved: unresolved,
      ingredientTokens: resolved.ingredientTokens,
      nutritionPanelPresent: resolved.nutritionPanelPresent,
      ingredientListPresent: resolved.ingredientListPresent,
    ),
  );
}

/// Converts kilojoules to kilocalories, recording the change.
///
/// Nothing else is converted. The audit entry carries scaled values and unit
/// names rather than formatted magnitudes: it is a machine-checkable record,
/// and keeping display formatting out of it removes any chance of it being
/// mistaken for user-facing text (FR-LOC-01).
Quantity _canonicalise(Quantity declared, List<Substitution> substitutions) {
  if (declared.unit != Unit.kilojoule) {
    return declared;
  }
  final Quantity converted = declared.convertTo(Unit.kilocalorie);
  substitutions.add(
    Substitution(
      kind: SubstitutionKind.energyConversion,
      before: '${declared.scaledValue} ${declared.unit.name}',
      after: '${converted.scaledValue} ${converted.unit.name}',
      appliedByRuleId: _S6Rules.energy,
    ),
  );
  return converted;
}

/// Whether the rule pack expects [unit] for this nutrient.
///
/// True when the pack states no expectation: absence of a rule is not evidence
/// against a value, and treating it as such would penalise every nutrient the
/// pack has not yet been extended to cover.
bool _wasExpected(SynonymTable synonyms, ResolvedField f, Unit unit) {
  final List<Unit> expected = synonyms.expectedUnitsFor(f.nutrient);
  return expected.isEmpty || expected.contains(unit);
}

UnresolvedCandidate _declined(ResolvedField f, UnresolvedReason reason) =>
    UnresolvedCandidate(
      reason: reason,
      labelText: f.nutrient.name,
      region: f.region,
      sourceIndices: f.sourceIndices,
    );

/// Parses [text] into [unit]'s increments, or null when it is not a number.
///
/// Accepts an optional thousands separator, because Indian labels print
/// `1,000 kcal`. Rejects a sign, a bare decimal point, more than one point,
/// and any non-digit — FR-PAR-05 requires the field to be reported unresolved
/// rather than coerced.
///
/// Excess precision rounds once, half away from zero, under the project's
/// single rounding policy (`DATA_MODEL.md` §2.4): `0.005 g` becomes `0.01 g`
/// rather than being truncated to nothing.
int? _parseScaled(String text, Unit unit) {
  final String cleaned = text.replaceAll(',', '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) {
    return null;
  }
  final int point = cleaned.indexOf('.');
  final String whole = point < 0 ? cleaned : cleaned.substring(0, point);
  final String fraction = point < 0 ? '' : cleaned.substring(point + 1);

  // A second point, a sign, or a trailing point is not a declared number.
  if (fraction.contains('.') || whole.isEmpty || !_allDigits(whole)) {
    return null;
  }
  if (point >= 0 && (fraction.isEmpty || !_allDigits(fraction))) {
    return null;
  }
  // Guards against overflow on absurd input; no real label prints this.
  if (whole.length > 12 || fraction.length > 9) {
    return null;
  }

  final int wholePart = int.parse(whole) * unit.scale;
  if (fraction.isEmpty) {
    return wholePart;
  }
  int power = 1;
  for (int i = 0; i < fraction.length; i++) {
    power *= 10;
  }
  return wholePart + divideRounded(int.parse(fraction) * unit.scale, power);
}

bool _allDigits(String text) {
  for (int i = 0; i < text.length; i++) {
    final int c = text.codeUnitAt(i);
    if (c < 48 || c > 57) {
      return false;
    }
  }
  return true;
}
