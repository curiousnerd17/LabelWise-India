import 'package:lw_domain/src/invariants/invariant_result.dart';
import 'package:lw_domain/src/parser/recognition_result.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';

/// The three inputs from which a field's confidence is assigned.
///
/// Mirrors `DATA_MODEL.md` §4.2. Per ADR-0010 the priority is **S3 primary,
/// S2 secondary, S1 an optional refinement** — the reverse of the intuitive
/// ordering, and defensible on its merits: an OCR engine that is confidently
/// wrong about a `3` it read as an `8` reports high character confidence, and
/// only the arithmetic catches it.
///
/// Held as a value object rather than three loose parameters so that what S8
/// decided from can be recorded alongside what it decided — FR-EXP-09 needs
/// the inputs, not just the verdict.
final class ConfidenceSignals {
  /// Records the signals observed for one field.
  ConfidenceSignals({
    required this.s2ParseStrength,
    this.s1OcrConfidence,
    List<InvariantResult> s3InvariantResults = const <InvariantResult>[],
  }) : s3InvariantResults =
            List<InvariantResult>.unmodifiable(s3InvariantResults);

  /// **S1** — the engine's per-element character confidence, or null.
  ///
  /// Null is a first-class answer, not a missing value. FR-OCR-04 requires the
  /// adapter to report absence rather than substitute a default, and FR-CNF-03
  /// requires classification to degrade gracefully without it.
  /// `ARCHITECTURE.md` §7.2 is explicit that the architecture must not assume
  /// S1 exists: its availability is unverified until the Q2 spike.
  final OcrConfidence? s1OcrConfidence;

  /// **S2** — how firmly the parse rule matched. Always present.
  final ParseStrength s2ParseStrength;

  /// **S3** — every invariant this field took part in.
  ///
  /// Possibly empty: an invariant only fires when its participating fields are
  /// present, so a sparse label carries less of this signal (ADR-0010's stated
  /// negative consequence).
  final List<InvariantResult> s3InvariantResults;

  /// Whether the engine supplied S1 at all (FR-CNF-03).
  bool get s1WasAvailable => s1OcrConfidence != null;

  /// Whether any invariant this field took part in failed.
  ///
  /// The condition `rulepack/rules/confidence.json` keys its first rule on, and
  /// the mechanism by which FR-CNF-05 becomes absolute.
  bool get anyInvariantFailed =>
      s3InvariantResults.any((InvariantResult r) => r.outcome.capsConfidence);

  /// Whether any invariant this field took part in passed.
  ///
  /// `INDETERMINATE` and `INAPPLICABLE` count as neither pass nor fail
  /// (FR-CNF-14, `DATA_MODEL.md` §4.3a).
  bool get anyInvariantPassed =>
      s3InvariantResults.any((InvariantResult r) => r.outcome.supportsHigh);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfidenceSignals &&
          s1OcrConfidence == other.s1OcrConfidence &&
          s2ParseStrength == other.s2ParseStrength &&
          _sameResults(s3InvariantResults, other.s3InvariantResults);

  @override
  int get hashCode => Object.hash(
        s1OcrConfidence,
        s2ParseStrength,
        Object.hashAll(s3InvariantResults),
      );

  /// A **debugging representation only.** Deliberately carries no number for
  /// S1: FR-CNF-10 forbids a numeric confidence reaching the user, and the
  /// cheapest way to keep that true is never to format one.
  @override
  String toString() => 'ConfidenceSignals('
      'S1 ${s1WasAvailable ? 'present' : 'absent'}, '
      '${s2ParseStrength.name}, '
      '${s3InvariantResults.length} checks)';
}

bool _sameResults(List<InvariantResult> a, List<InvariantResult> b) {
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
