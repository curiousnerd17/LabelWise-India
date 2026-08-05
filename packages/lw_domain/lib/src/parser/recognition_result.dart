import 'package:lw_domain/src/provenance/region_ref.dart';

/// The script the OCR adapter observed to dominate the image.
///
/// The adapter **observes**; the domain **decides policy** (S1 declines
/// anything it cannot read). Splitting it this way keeps FR-OCR-05's decision
/// in the domain while leaving detection where the pixels are.
enum DominantScript {
  /// Latin script — the only script v0.1 parses (ADR-0015).
  latin,

  /// Devanagari. Legally valid on Indian labels and not readable by v0.1, so
  /// S1 declines it explicitly rather than mis-parsing it.
  devanagari,

  /// A script that is neither Latin nor Devanagari.
  other,

  /// The adapter could not classify the script.
  ///
  /// Not evidence of a foreign script. Declining on this would refuse labels
  /// the adapter merely failed to classify, so S1 proceeds.
  undetermined,
}

/// The recognition engine's own confidence in one element — signal **S1**.
///
/// Deliberately a **different type from `Confidence`**. The engine's
/// self-report is not our classification, and giving them one type would let
/// S1 leak into S8's verdict (ADR-0010). Availability is unresolved until the
/// Q2 spike, which is why every use of it is optional.
///
/// A normalised scaled integer in `0 … `[scale], matching `RegionRef`'s
/// discipline rather than introducing floating point (ADR-0021).
final class OcrConfidence {
  /// Creates an engine confidence reading.
  ///
  /// Throws [ArgumentError] outside `0 … `[scale].
  OcrConfidence(this.scaledValue) {
    if (scaledValue < 0 || scaledValue > scale) {
      throw ArgumentError(
        'OCR confidence $scaledValue is outside 0..$scale.',
      );
    }
  }

  /// The upper bound of the normalised range.
  static const int scale = 10000;

  /// The reading, in `0 … `[scale].
  final int scaledValue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrConfidence && scaledValue == other.scaledValue;

  @override
  int get hashCode => scaledValue.hashCode;

  @override
  String toString() => 'OcrConfidence($scaledValue/$scale)';
}

/// One piece of text the recognition engine returned, with its position.
///
/// The **neutral model** that crosses boundary B2. No engine type appears in
/// the domain, which is what lets the golden corpus store recorded OCR output
/// and run parser tests without OCR at all.
final class RecognitionElement {
  /// Records a recognised element exactly as the engine returned it.
  const RecognitionElement({
    required this.text,
    required this.region,
    this.ocrConfidence,
  });

  /// The text **exactly as recognised** — not trimmed, corrected or case
  /// folded (FR-OCR-06). S1 is the first place text may change, and every
  /// change there is recorded as a `Substitution`.
  final String text;

  /// Where it sits on the label (FR-OCR-03).
  final RegionRef region;

  /// The engine's confidence, or null when the engine does not report one.
  ///
  /// Null means **absent**, never "zero" and never a default. Substituting a
  /// value would make a missing signal indistinguishable from a real reading
  /// (FR-OCR-04).
  final OcrConfidence? ocrConfidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecognitionElement &&
          text == other.text &&
          region == other.region &&
          ocrConfidence == other.ocrConfidence;

  @override
  int get hashCode => Object.hash(text, region, ocrConfidence);

  @override
  String toString() => 'RecognitionElement("$text", $region)';
}

/// Everything the recognition engine returned for one image — the S0 output.
///
/// Produced by the P-OCR adapter and consumed by S1. This is the parser's
/// input type and the type the golden corpus records alongside each label.
final class RecognitionResult {
  /// Records a recognition pass.
  RecognitionResult({
    required List<RecognitionElement> elements,
    required this.dominantScript,
  }) : elements = List<RecognitionElement>.unmodifiable(elements);

  /// The recognised elements, in the engine's reading order.
  ///
  /// Unmodifiable: the recognition result is evidence, and evidence callers
  /// can append to is not evidence.
  final List<RecognitionElement> elements;

  /// The script the adapter observed. An observation, not a decision.
  final DominantScript dominantScript;

  @override
  String toString() =>
      'RecognitionResult(${elements.length} elements, ${dominantScript.name})';
}
