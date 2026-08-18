import 'package:lw_domain/src/analysis/serving_reconciliation.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/parsed_label.dart';

/// Whether the declared serving figures reconcile.
///
/// **Factual, never evaluative** (FR-L1-01). Each state says what the
/// arithmetic did. That a small serve might be *misleading* is an
/// interpretation, and interpretations belong to Layer 2 with an explanation
/// attached (ADR-0011) — not to an enum in the factual engine.
enum ServingDiscrepancy {
  /// The declared serve, servings per pack and net quantity reconcile.
  none,

  /// Serve x servings per pack does not reconcile with the net quantity.
  ///
  /// States that the numbers do not multiply out, and nothing more. A pack may
  /// round its servings count for perfectly ordinary reasons.
  servesInconsistent,

  /// The declared serve is larger than the declared net quantity.
  serveExceedsPack,

  /// The required arithmetic could not be performed safely.
  ///
  /// Distinct from a figure being undeclared: absence lives in the
  /// [ServingReconciliationResult.declaredServe] and
  /// [ServingReconciliationResult.servesPerPack] field states, which already
  /// separate *not declared* from *not readable* (MI-08). This state means the
  /// inputs were understood and the calculation over them was declined — a
  /// magnitude a checked multiply refused, for instance. M11b established that
  /// a refused calculation never becomes a fabricated number.
  notComputable,
}

/// The declared serving figures, side by side, and whether they reconcile.
///
/// `DATA_MODEL.md` §6.2 calls this "the product's signature Layer 1 output".
/// Serving-size manipulation is the primary legal deception on Indian
/// packaging (`PROJECT_VISION.md` §2.1), which is why it earns a type rather
/// than being three loose findings.
///
/// **Stores outcomes; computes nothing.** The constructor does no arithmetic
/// and infers no discrepancy — a result reports whatever it was given. The
/// Layer 1 engine decides, and it does so with the checked arithmetic M11b
/// established.
///
/// Implements the domain's open [ServingReconciliation] interface, which was
/// declared `abstract interface` rather than `sealed` precisely so the analysis
/// layer could supply this implementation.
final class ServingReconciliationResult implements ServingReconciliation {
  /// Records a reconciliation.
  ///
  /// [wholePackValues] is copied and stored unmodifiable, so a caller that
  /// keeps its list cannot alter a result after the fact.
  ServingReconciliationResult({
    required this.declaredServe,
    required this.servesPerPack,
    required List<NutrientField> wholePackValues,
    required this.discrepancy,
  }) : wholePackValues = List<NutrientField>.unmodifiable(wholePackValues);

  /// The serve the label declares, as read.
  ///
  /// A [FieldState], so *not declared*, *not readable* and *read as 30 g* stay
  /// three distinguishable facts rather than collapsing into a nullable
  /// quantity (FR-ERR-03).
  final FieldState declaredServe;

  /// The servings per pack the label declares, as read.
  final FieldState servesPerPack;

  /// Whole-pack totals for the nutrients that could be scaled.
  ///
  /// Ordinary [NutrientField]s carrying a `perPack` value, not a parallel
  /// value type — a consumer that can render a nutrient can render these.
  /// Order is deterministic and part of the value (FR-PAR-02). Legitimately
  /// empty when no per-100 figure could be scaled.
  final List<NutrientField> wholePackValues;

  /// What the arithmetic showed.
  final ServingDiscrepancy discrepancy;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! ServingReconciliationResult) {
      return false;
    }
    if (declaredServe != other.declaredServe ||
        servesPerPack != other.servesPerPack ||
        discrepancy != other.discrepancy) {
      return false;
    }
    return _sameValues(other.wholePackValues);
  }

  bool _sameValues(List<NutrientField> other) {
    if (wholePackValues.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (wholePackValues[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        declaredServe,
        servesPerPack,
        discrepancy,
        Object.hashAll(wholePackValues),
      );

  @override
  String toString() => 'ServingReconciliationResult(${discrepancy.name}, '
      '${wholePackValues.length} whole-pack values)';
}
