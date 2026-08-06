import 'package:lw_domain/src/analysis/serving_reconciliation.dart';
import 'package:lw_domain/src/confidence/scan_confidence.dart';
import 'package:lw_domain/src/invariants/invariant_result.dart';
import 'package:lw_domain/src/label/category_id.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/ingredient.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/version.dart';

/// One nutrient across the three declaration slots.
///
/// `DATA_MODEL.md` §5.2. Modelled as a fixed triple rather than a list so that
/// FR-PRS-02 — display all three together — is a lookup and not a search, and
/// so that "we could not compute per-pack because net quantity was unreadable"
/// is expressible rather than merely absent.
///
/// > **[perHundred] is a storage slot, not a semantic basis.** It holds either
/// > a per-100 g or a per-100 ml declaration; a beverage panel uses the latter.
/// > **Consumers must read the basis from the contained field**
/// > (`FieldState.basisOrNull`) and must never infer it from the slot name. A
/// > right value on the wrong basis is wrong by a factor of three or more.
final class NutrientField {
  /// Records one nutrient's three slots.
  const NutrientField({
    required this.nutrient,
    required this.perHundred,
    required this.perServe,
    required this.perPack,
  });

  /// The nutrient these slots describe.
  final NutrientId nutrient;

  /// The per-hundred declaration — grams or millilitres. See the note above.
  final FieldState perHundred;

  /// The per-serve declaration.
  final FieldState perServe;

  /// The whole-pack declaration.
  final FieldState perPack;

  /// Whether any slot carries a value.
  ///
  /// False when every slot is `NotDeclaredField` — a nutrient the label is
  /// silent about, which Layer 1 reports as a declaration gap rather than a
  /// parser failure.
  bool get anyDeclared =>
      perHundred.quantityOrNull != null ||
      perServe.quantityOrNull != null ||
      perPack.quantityOrNull != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutrientField &&
          nutrient == other.nutrient &&
          perHundred == other.perHundred &&
          perServe == other.perServe &&
          perPack == other.perPack;

  @override
  int get hashCode => Object.hash(nutrient, perHundred, perServe, perPack);

  @override
  String toString() => 'NutrientField(${nutrient.name})';
}

/// The declared pack figures.
///
/// `DATA_MODEL.md` §5.3. All three are **critical fields**: serving-size
/// manipulation is the primary legal deception on Indian packaging
/// (`PROJECT_VISION.md` §2.1), so their extraction matters as much as any
/// nutrient's.
final class ServingInfo {
  /// Records the pack figures.
  const ServingInfo({
    required this.declaredServingSize,
    required this.servingsPerPack,
    required this.netQuantity,
    this.reconciliation,
  });

  /// The manufacturer's chosen serve.
  final FieldState declaredServingSize;

  /// How many serves the pack contains. Often declared approximately.
  final FieldState servingsPerPack;

  /// Total declared pack contents.
  final FieldState netQuantity;

  /// The Layer 1 reconciliation, or null from the parser.
  ///
  /// Optional since `DATA_MODEL.md` v1.6. It is a Layer 1 output (§6.2) and
  /// Layer 1 consumes the `ParsedLabel` this sits inside; requiring a **value**
  /// would make `ParsedLabel` unconstructible by its own producer.
  ///
  /// Naming the **type** costs nothing and buys compile-time safety: a type
  /// reference is not a dependency on a value. The parser always leaves this
  /// null, and no implementation of `ServingReconciliation` exists yet.
  final ServingReconciliation? reconciliation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServingInfo &&
          declaredServingSize == other.declaredServingSize &&
          servingsPerPack == other.servingsPerPack &&
          netQuantity == other.netQuantity &&
          reconciliation == other.reconciliation;

  @override
  int get hashCode => Object.hash(
        declaredServingSize,
        servingsPerPack,
        netQuantity,
        reconciliation,
      );

  @override
  String toString() => 'ServingInfo(${_describe(declaredServingSize)}, '
      '${_describe(servingsPerPack)}, ${_describe(netQuantity)})';
}

String _describe(FieldState state) => switch (state) {
      ExtractedField() => 'declared',
      DerivedField() => 'derived',
      UserSuppliedField() => 'corrected',
      UnresolvedField() => 'unresolved',
      NotDeclaredField() => 'absent',
    };

/// **The boundary object between the parser and analysis.**
///
/// Per `ARCHITECTURE.md` AR5 this is the **only** parser type that is a
/// published contract; S1–S8 intermediates are internal and refactorable. That
/// asymmetry is deliberate: it lets the parser be reshaped as the corpus
/// teaches us things, without the analysis layer moving.
///
/// Assembled after S8 rather than by it (`ARCHITECTURE.md` v1.3). The parser
/// stops here: what follows — findings, reconciliation, additive
/// identification, advice — is Layer 1 and Layer 2 work.
final class ParsedLabel {
  /// Records a parsed label.
  ///
  /// Throws [ArgumentError] when two entries describe the same nutrient. Two
  /// would make [nutrientFor] mean "whichever came first" — a silent choice no
  /// consumer could see or question.
  ParsedLabel({
    required this.servingInfo,
    required this.scanConfidence,
    required this.rulePackVersion,
    List<NutrientField> nutrients = const <NutrientField>[],
    List<Ingredient> ingredients = const <Ingredient>[],
    List<InvariantResult> invariantResults = const <InvariantResult>[],
    this.declaredCategory,
    this.unsupportedScript = false,
  })  : nutrients = List<NutrientField>.unmodifiable(nutrients),
        ingredients = List<Ingredient>.unmodifiable(ingredients),
        invariantResults =
            List<InvariantResult>.unmodifiable(invariantResults) {
    final Set<NutrientId> seen = <NutrientId>{};
    for (final NutrientField f in nutrients) {
      if (!seen.add(f.nutrient)) {
        throw ArgumentError.value(
          f.nutrient,
          'nutrients',
          'Duplicate entry for ${f.nutrient.name}.',
        );
      }
    }
  }

  /// Every nutrient the label was read for, in a deterministic order.
  final List<NutrientField> nutrients;

  /// The declared pack figures.
  final ServingInfo servingInfo;

  /// The ingredient list, in declaration order (FR-PAR-10, MI-12).
  final List<Ingredient> ingredients;

  /// The product category, when the caller supplied one.
  ///
  /// Always null from the parser: FR-CAT-02 makes category optional and no
  /// stage determines it. Category scoping is declarative rule pack data
  /// (FR-CAT-04), never code branching (FR-PAR-16).
  final CategoryId? declaredCategory;

  /// Every invariant evaluated, including the inapplicable ones (FR-CNF-04).
  final List<InvariantResult> invariantResults;

  /// How much of this scan the user should check (`DATA_MODEL.md` §4.5).
  ///
  /// For orientation only. §4.5 forbids it gating anything — a scan can be LOW
  /// because one reading is poor while another is impeccable.
  final ScanConfidence scanConfidence;

  /// The rule pack in force when this was produced (FR-KB-02).
  final Version rulePackVersion;

  /// Whether the image was predominantly a script we cannot read (FR-OCR-05).
  ///
  /// **Orchestration state, never inferred here.** S1 declines a non-Latin
  /// result through `StageResult`, which remains the pipeline's only failure
  /// channel; whoever runs S1–S8 and catches that failure sets this. A false
  /// value is therefore not evidence that the script was checked.
  final bool unsupportedScript;

  /// The entry for [nutrient], or null when the label was not read for it.
  ///
  /// Null rather than an empty triple: "we have no entry" and "we have an
  /// entry declaring nothing" are different facts, and FR-ERR-03 turns on
  /// keeping such pairs apart.
  NutrientField? nutrientFor(NutrientId nutrient) {
    for (final NutrientField f in nutrients) {
      if (f.nutrient == nutrient) {
        return f;
      }
    }
    return null;
  }

  @override
  String toString() => 'ParsedLabel(${nutrients.length} nutrients, '
      '${ingredients.length} ingredients, scan ${scanConfidence.name})';
}
