import 'package:lw_domain/src/parser/recognition_result.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';
import 'package:lw_domain/src/provenance/substitution.dart';

/// One element after S1 normalisation.
///
/// Carries **both** the text as recognised and the text after normalisation.
/// Retaining the original is what makes FR-PAR-06's "record that a
/// normalisation occurred" verifiable and keeps the audit chain from pixel to
/// value unbroken (`ARCHITECTURE.md` §8.3).
final class NormalisedElement {
  /// Records one normalised element.
  NormalisedElement({
    required this.sourceIndex,
    required this.originalText,
    required this.text,
    required this.region,
    List<Substitution> substitutions = const <Substitution>[],
    this.ocrConfidence,
  }) : substitutions = List<Substitution>.unmodifiable(substitutions);

  /// Position of the source element in the recognition result.
  ///
  /// Every later stage can trace a value back to the element it came from
  /// without holding a reference to it — which keeps stage outputs
  /// independently snapshot-testable.
  final int sourceIndex;

  /// The text exactly as the engine returned it (FR-OCR-06).
  final String originalText;

  /// The text after normalisation. Equal to [originalText] when nothing
  /// changed.
  final String text;

  /// Where the source element sits on the label.
  final RegionRef region;

  /// Every transformation applied, in the order applied.
  ///
  /// Empty when [text] equals [originalText]. A no-op substitution is never
  /// recorded — it would pad the audit trail and make real changes harder to
  /// find.
  final List<Substitution> substitutions;

  /// The engine's confidence, passed through unchanged. Null means absent
  /// (FR-OCR-04).
  final OcrConfidence? ocrConfidence;

  /// Whether normalisation altered this element's text.
  bool get wasChanged => originalText != text;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! NormalisedElement) {
      return false;
    }
    if (substitutions.length != other.substitutions.length) {
      return false;
    }
    for (int i = 0; i < substitutions.length; i++) {
      if (substitutions[i] != other.substitutions[i]) {
        return false;
      }
    }
    return sourceIndex == other.sourceIndex &&
        originalText == other.originalText &&
        text == other.text &&
        region == other.region &&
        ocrConfidence == other.ocrConfidence;
  }

  @override
  int get hashCode => Object.hash(sourceIndex, originalText, text, region,
      ocrConfidence, Object.hashAll(substitutions));

  @override
  String toString() => 'NormalisedElement[$sourceIndex]("$text")';
}

/// The output of S1.
///
/// Element count and order match the recognition result exactly. Normalisation
/// may change text; it never adds, removes or reorders elements, because
/// [NormalisedElement.sourceIndex] is the mapping every later stage relies on.
final class NormalisedText {
  /// Records the S1 output.
  NormalisedText({required List<NormalisedElement> elements})
      : elements = List<NormalisedElement>.unmodifiable(elements);

  /// The normalised elements, in recognition order.
  final List<NormalisedElement> elements;

  /// The stage that produced this, recorded for diagnostics.
  PipelineStage get producedByStage => PipelineStage.normalisation;

  /// Every substitution applied across every element, in element order.
  ///
  /// The whole normalisation audit trail for one label, without walking the
  /// elements.
  List<Substitution> get allSubstitutions => List<Substitution>.unmodifiable(
        <Substitution>[
          for (final NormalisedElement e in elements) ...e.substitutions,
        ],
      );

  @override
  String toString() => 'NormalisedText(${elements.length} elements)';
}
