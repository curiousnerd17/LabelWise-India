/// How much of a whole scan the user should check.
///
/// **A separate type from `Confidence`, deliberately** (`DATA_MODEL.md` §4.5,
/// MI-10). The naive approach — the meet across all fields — is wrong: one LOW
/// field among twelve would render the whole scan LOW, which is both
/// uninformative and demoralising.
///
/// > **It never participates in rule evaluation.** §4.5 is emphatic: a scan can
/// > be LOW overall because the protein reading is poor while the sodium
/// > reading is impeccable, and the sodium finding should be presented with
/// > full confidence. Suppressing it would discard a good finding on the
/// > strength of an unrelated bad one. FR-CNF-13 already handles that
/// > precisely, at the level of the individual determining input.
///
/// Keeping it a distinct type is how MI-10 becomes structural rather than a
/// convention someone must remember: it cannot be passed where a field
/// `Confidence` is expected.
enum ScanConfidence {
  /// Every critical field resolved, at least 80% of them HIGH, no failure.
  high,

  /// Every critical field resolved, none LOW, at most one failed invariant.
  medium,

  /// A resolved critical field is LOW, or two or more invariants failed.
  low,

  /// One or more critical fields could not be read.
  ///
  /// Reserved for **our** failure, not the label's. A product that legitimately
  /// declares no added sugars has a declaration gap for Layer 1 to report, and
  /// is not a partial scan — which is FR-ERR-03 applied at the scan level.
  partial;

  /// The level implied by the field counts, per `DATA_MODEL.md` §4.5.
  ///
  /// "Resolved" there means `Extracted`, `UserSupplied`, `Derived` **or**
  /// `NotDeclared` — the caller decides which fields count and supplies the
  /// totals; this holds only the rule.
  ///
  /// Throws [ArgumentError] on a negative count, or when the HIGH and LOW
  /// counts exceed the resolved count. An impossible tally means the caller
  /// miscounted, and absorbing it would let a miscount present itself as a
  /// trustworthy scan.
  static ScanConfidence from({
    required bool everyCriticalFieldResolved,
    required int resolvedCriticalCount,
    required int highCriticalCount,
    required int lowCriticalCount,
    required int failedInvariantCount,
  }) {
    _requireNonNegative(resolvedCriticalCount, 'resolvedCriticalCount');
    _requireNonNegative(highCriticalCount, 'highCriticalCount');
    _requireNonNegative(lowCriticalCount, 'lowCriticalCount');
    _requireNonNegative(failedInvariantCount, 'failedInvariantCount');
    if (highCriticalCount + lowCriticalCount > resolvedCriticalCount) {
      throw ArgumentError.value(
        highCriticalCount + lowCriticalCount,
        'highCriticalCount + lowCriticalCount',
        'More classified critical fields than resolved ones '
            '($resolvedCriticalCount).',
      );
    }

    // Checked first: it records that we could not read something, which is a
    // different kind of statement from a judgement about what we did read.
    if (!everyCriticalFieldResolved) {
      return ScanConfidence.partial;
    }
    if (lowCriticalCount > 0 || failedInvariantCount >= 2) {
      return ScanConfidence.low;
    }
    // Integer comparison rather than a ratio, so the 80% boundary is exact.
    // The zero guard matters: 0 of 0 is not 100% of anything, and a scan that
    // read nothing must not be presented as trustworthy.
    final bool mostlyHigh = resolvedCriticalCount > 0 &&
        highCriticalCount * 100 >= resolvedCriticalCount * 80;
    if (mostlyHigh && failedInvariantCount == 0) {
      return ScanConfidence.high;
    }
    return ScanConfidence.medium;
  }
}

void _requireNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'A count cannot be negative.');
  }
}
