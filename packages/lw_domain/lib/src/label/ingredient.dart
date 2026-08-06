import 'package:lw_domain/src/provenance/provenance.dart';

/// An International Numbering System identifier for a food additive.
///
/// **The primary key for additive resolution** (ADR-0005, FR-PAR-11). A number
/// is language-independent and unambiguous where a name is neither, which is
/// why name matching is capped at `MEDIUM` and this is not.
final class InsNumber {
  /// Creates an INS number.
  ///
  /// Throws [ArgumentError] outside 1…99999. The published series runs to four
  /// digits; the bound is deliberately generous rather than a guess at the
  /// exact ceiling, and it still rejects a misread that produced zero or a
  /// negative.
  InsNumber(this.value) {
    if (value < 1 || value > 99999) {
      throw ArgumentError.value(
        value,
        'value',
        'An INS number lies between 1 and 99999.',
      );
    }
  }

  /// The number as printed, e.g. 322 for lecithin.
  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InsNumber && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'InsNumber($value)';
}

/// Why an ingredient could not be identified.
enum UnidentifiedReason {
  /// Identification has not been attempted.
  ///
  /// Distinct from a failed attempt, and distinct again from a null
  /// `Ingredient.identification` — this variant records a deliberate decision
  /// not to try, where null records that the engine does not yet exist.
  notAttempted,

  /// Identification was attempted and nothing matched.
  noMatchFound,

  /// The recognised text was too damaged to identify from.
  textUnreadable,
}

/// What an ingredient was identified as.
///
/// `DATA_MODEL.md` §5.4. Sealed, so a switch that forgets a variant fails to
/// compile rather than silently mishandling one.
///
/// > **Nothing in the parser constructs any of these.** Additive
/// > identification is Layer 1 work, scheduled by `ROADMAP.md` §4.3 item 4.4.
/// > The type exists so that `ParsedLabel` matches its published contract; the
/// > engine that fills it arrives later.
///
/// The confidence ceilings §5.4 states — `AdditiveByName` capped at `MEDIUM`,
/// `Unidentified` at `LOW` — belong to whatever assigns confidence to an
/// identification, not to these types. Name matching is fuzzy and
/// language-dependent, and the model must make it impossible to present a
/// fuzzy match with the authority of an INS-number match.
sealed class IngredientIdentification {
  /// Base constructor for the four variants.
  const IngredientIdentification();
}

/// Identified by its INS number — the strongest form (ADR-0005).
final class AdditiveByIns extends IngredientIdentification {
  /// Records an INS-number identification.
  const AdditiveByIns(this.insNumber, {this.classTitle});

  /// The number that identified it.
  final InsNumber insNumber;

  /// The class title as printed, such as `Emulsifier`. Null when absent.
  final String? classTitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdditiveByIns &&
          insNumber == other.insNumber &&
          classTitle == other.classTitle;

  @override
  int get hashCode => Object.hash(insNumber, classTitle);

  @override
  String toString() => 'AdditiveByIns(${insNumber.value})';
}

/// Identified by name, which is fuzzy and language-dependent (ADR-0005).
final class AdditiveByName extends IngredientIdentification {
  /// Records a name identification.
  ///
  /// Throws [ArgumentError] when [matchedName] is blank.
  AdditiveByName(this.matchedName, {this.insNumber}) {
    if (matchedName.trim().isEmpty) {
      throw ArgumentError.value(
        matchedName,
        'matchedName',
        'A name identification must carry the name it matched.',
      );
    }
  }

  /// The name that matched, as the rule pack spells it.
  final String matchedName;

  /// The INS number the name suggests, when the pack records one.
  final InsNumber? insNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdditiveByName &&
          matchedName == other.matchedName &&
          insNumber == other.insNumber;

  @override
  int get hashCode => Object.hash(matchedName, insNumber);

  @override
  String toString() => 'AdditiveByName($matchedName)';
}

/// An ordinary ingredient, not an additive.
final class PlainIngredient extends IngredientIdentification {
  /// Records a plain ingredient.
  ///
  /// Throws [ArgumentError] when [normalisedName] is blank.
  PlainIngredient(this.normalisedName) {
    if (normalisedName.trim().isEmpty) {
      throw ArgumentError.value(
        normalisedName,
        'normalisedName',
        'A plain ingredient must carry a name.',
      );
    }
  }

  /// The name after normalisation.
  final String normalisedName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlainIngredient && normalisedName == other.normalisedName;

  @override
  int get hashCode => normalisedName.hashCode;

  @override
  String toString() => 'PlainIngredient($normalisedName)';
}

/// Identification was attempted and did not settle (FR-ERR-03).
final class Unidentified extends IngredientIdentification {
  /// Records a failure to identify.
  const Unidentified(this.reason);

  /// Why it could not be identified.
  final UnidentifiedReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Unidentified && reason == other.reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'Unidentified(${reason.name})';
}

/// One entry in the declared ingredient list.
///
/// `DATA_MODEL.md` §5.4. [position] is 1-based because declaration order is
/// legally meaningful — Indian labelling requires descending order by weight,
/// so the first ingredient is the largest component and losing the order
/// destroys the only quantitative information the list carries.
final class Ingredient {
  /// Records an ingredient.
  ///
  /// Throws [ArgumentError] when [position] is below 1 or [rawText] is blank.
  Ingredient({
    required this.position,
    required this.rawText,
    required this.provenance,
    this.identification,
    List<Ingredient> subIngredients = const <Ingredient>[],
  }) : subIngredients = List<Ingredient>.unmodifiable(subIngredients) {
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
  }

  /// 1-based position among its siblings (FR-PAR-10).
  final int position;

  /// The text as recognised, before any interpretation.
  final String rawText;

  /// What it was identified as, or **null when identification has not been
  /// attempted at all**.
  ///
  /// Optional since `DATA_MODEL.md` v1.6. Null is **not** `Unidentified`: that
  /// variant records an attempt that failed, and conflating the two would let
  /// an unbuilt feature masquerade as a resolved absence — the FR-ERR-03
  /// failure mode, one level up. The parser leaves this null throughout.
  final IngredientIdentification? identification;

  /// Parenthetical sub-ingredients, in declaration order (FR-PAR-12).
  final List<Ingredient> subIngredients;

  /// Where it came from and how (ADR-0009).
  final Provenance provenance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ingredient &&
          position == other.position &&
          rawText == other.rawText &&
          identification == other.identification &&
          provenance == other.provenance &&
          _sameIngredients(subIngredients, other.subIngredients);

  @override
  int get hashCode => Object.hash(
        position,
        rawText,
        identification,
        provenance,
        Object.hashAll(subIngredients),
      );

  @override
  String toString() =>
      'Ingredient($position, "$rawText", ${subIngredients.length} nested)';
}

bool _sameIngredients(List<Ingredient> a, List<Ingredient> b) {
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
