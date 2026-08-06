import 'package:lw_domain/src/label/unit.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';

/// One printed form of a unit, and the unit it denotes.
final class UnitVariant {
  /// Records a variant.
  ///
  /// [text] is folded to lower case and trimmed once, here, so that matching
  /// cannot depend on how the label printed it.
  ///
  /// Throws [ArgumentError] when [text] is blank.
  UnitVariant({
    required String text,
    required this.unit,
    required this.strength,
  }) : text = text.trim().toLowerCase() {
    if (this.text.isEmpty) {
      throw ArgumentError.value(text, 'text', 'A variant must carry text.');
    }
  }

  /// The printed form, lower-cased and trimmed.
  final String text;

  /// The unit it denotes.
  final Unit unit;

  /// How firmly this form counts — signal S2. Canonical symbols are exact;
  /// spelled-out and abbreviated forms are normalised.
  final ParseStrength strength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnitVariant &&
          text == other.text &&
          unit == other.unit &&
          strength == other.strength;

  @override
  int get hashCode => Object.hash(text, unit, strength);

  @override
  String toString() => 'UnitVariant("$text" -> ${unit.name})';
}

/// The unit spellings S6 recognises (FR-PAR-06).
///
/// FR-PAR-06 names `g`, `gm`, `gms`, `mg`, `kcal`, `kJ` and `ml` explicitly.
/// The default set below covers those and the spelled-out forms that appear
/// alongside them.
///
/// **Injected, not hard-coded**, matching the pattern approved at S3 and S5.
/// Kept in code rather than the rule pack for the same reason as the basis
/// markers: this is a small, fixed, structural vocabulary shared by every
/// category, so a schema extension would buy nothing.
final class UnitLexicon {
  /// Creates a lexicon.
  UnitLexicon(List<UnitVariant> variants)
      : variants = List<UnitVariant>.unmodifiable(variants);

  /// The forms found on Indian food labels.
  static final UnitLexicon defaults = UnitLexicon(<UnitVariant>[
    UnitVariant(text: 'g', unit: Unit.gram, strength: ParseStrength.exact),
    UnitVariant(
      text: 'gm',
      unit: Unit.gram,
      strength: ParseStrength.normalised,
    ),
    UnitVariant(
      text: 'gms',
      unit: Unit.gram,
      strength: ParseStrength.normalised,
    ),
    UnitVariant(
      text: 'gram',
      unit: Unit.gram,
      strength: ParseStrength.normalised,
    ),
    UnitVariant(
      text: 'grams',
      unit: Unit.gram,
      strength: ParseStrength.normalised,
    ),
    UnitVariant(
      text: 'mg',
      unit: Unit.milligram,
      strength: ParseStrength.exact,
    ),
    UnitVariant(
      text: 'mgs',
      unit: Unit.milligram,
      strength: ParseStrength.normalised,
    ),
    UnitVariant(
      text: 'mcg',
      unit: Unit.microgram,
      strength: ParseStrength.normalised,
    ),
    UnitVariant(
      text: 'µg',
      unit: Unit.microgram,
      strength: ParseStrength.exact,
    ),
    UnitVariant(
      text: 'ml',
      unit: Unit.millilitre,
      strength: ParseStrength.exact,
    ),
    UnitVariant(
      text: 'mls',
      unit: Unit.millilitre,
      strength: ParseStrength.normalised,
    ),
    UnitVariant(
      text: 'kcal',
      unit: Unit.kilocalorie,
      strength: ParseStrength.exact,
    ),
    UnitVariant(
      text: 'kcals',
      unit: Unit.kilocalorie,
      strength: ParseStrength.normalised,
    ),
    // "Cal" on an Indian food label means kilocalories in practice, but the
    // word is genuinely ambiguous, so the match is weak rather than absent.
    UnitVariant(
      text: 'cal',
      unit: Unit.kilocalorie,
      strength: ParseStrength.heuristic,
    ),
    UnitVariant(
      text: 'kj',
      unit: Unit.kilojoule,
      strength: ParseStrength.exact,
    ),
    UnitVariant(
      text: '%',
      unit: Unit.percent,
      strength: ParseStrength.exact,
    ),
  ]);

  /// The variants, in declaration order.
  final List<UnitVariant> variants;

  /// The unit [printed] denotes, or null when nothing in the lexicon does.
  ///
  /// An **exact token match** after folding case and trimming, deliberately
  /// not a substring test: `mg` is a substring of nothing useful, but a
  /// substring rule would let `g` match inside `kg` and silently mis-scale a
  /// declaration by a thousand. Null is the honest answer, and FR-PAR-05
  /// requires the field to be reported unresolved rather than assigned a
  /// guessed unit.
  UnitVariant? resolve(String printed) {
    final String folded = printed.trim().toLowerCase();
    if (folded.isEmpty || variants.isEmpty) {
      return null;
    }
    for (final UnitVariant v in variants) {
      if (v.text == folded) {
        return v;
      }
    }
    return null;
  }

  @override
  String toString() => 'UnitLexicon(${variants.length} variants)';
}
