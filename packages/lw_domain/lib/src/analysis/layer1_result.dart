import 'package:lw_domain/src/analysis/factual_finding.dart';
import 'package:lw_domain/src/analysis/serving_reconciliation_result.dart';

/// What Layer 1 factual analysis produced.
///
/// Two members, because the reconciliation is **not** a finding.
/// `DATA_MODEL.md` §6.2 gives it its own shape — a declared serve, a servings
/// count, the whole-pack totals and a discrepancy — and flattening those into
/// the findings list would lose the relationship between the four parts that
/// makes the comparison meaningful.
///
/// **An aggregate, not an engine.** It holds what it is given: no arithmetic,
/// no inference, no finding manufactured from the reconciliation it carries.
/// The engine computes; this reports.
final class Layer1Result {
  /// Records the outcome of one factual analysis.
  ///
  /// [findings] is copied and stored unmodifiable, so a caller keeping its
  /// list cannot alter a result after the fact.
  Layer1Result({
    required List<FactualFinding> findings,
    required this.servingReconciliation,
  }) : findings = List<FactualFinding>.unmodifiable(findings);

  /// Every factual statement, in a deterministic order (FR-PAR-02).
  ///
  /// Order is part of the value: the same label analysed twice must present
  /// its findings identically, and a consumer rendering them in receipt order
  /// must get the same screen each time.
  ///
  /// Legitimately empty — an ingredients-only label declares no nutrient to
  /// restate, and an empty list is that fact rather than a failure.
  final List<FactualFinding> findings;

  /// How the declared serving figures reconcile.
  ///
  /// **Never null.** A label declaring no serving information still produces a
  /// reconciliation, whose field states record the absence (`NotDeclaredField`)
  /// and whose discrepancy records that nothing could be computed. Making this
  /// nullable would collapse "the pack declares no serve" into "we did not
  /// look", which is the MI-08 distinction one level up.
  final ServingReconciliationResult servingReconciliation;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Layer1Result) {
      return false;
    }
    if (servingReconciliation != other.servingReconciliation) {
      return false;
    }
    return _sameFindings(other.findings);
  }

  bool _sameFindings(List<FactualFinding> other) {
    if (findings.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (findings[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(servingReconciliation, Object.hashAll(findings));

  @override
  String toString() => 'Layer1Result(${findings.length} findings, '
      '${servingReconciliation.discrepancy.name})';
}
