import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';

/// Why a pipeline stage could not produce its output.
///
/// An enum, not a string: the domain holds identity, never display text
/// (M5, FR-LOC-01). Each kind is specific enough that the presentation layer
/// can offer an actionable message (FR-ERR-01) — a single generic failure
/// would make that impossible.
enum ParseFailureKind {
  /// The label is in a script v0.1 cannot read (FR-OCR-05, ADR-0015).
  ///
  /// An honest refusal. A bad parse destroys trust; declining preserves it.
  unsupportedScript,

  /// The recognition engine returned nothing to parse (FR-OCR-07).
  noTextRecognised,

  /// Geometry carries too little information to reconstruct lines.
  layoutIndeterminate,

  /// An expected region of the label could not be located.
  regionNotFound,

  /// The pipeline reached a state its own invariants forbid.
  ///
  /// Distinct from the others: this indicates a defect in the parser, not a
  /// problem with the label.
  internalInconsistency,
}

/// A structured account of why a stage failed.
///
/// **Never an empty success** (FR-PAR-17). A stage that could not do its work
/// says so, names the stage, and where possible points at the region — so the
/// failure is as traceable as a success.
final class ParseFailure {
  /// Records a stage failure.
  const ParseFailure({
    required this.kind,
    required this.stage,
    this.region,
    this.detailMessageId,
  });

  /// What went wrong.
  final ParseFailureKind kind;

  /// Which stage could not proceed.
  final PipelineStage stage;

  /// Where on the label, when the failure is localised.
  ///
  /// Null for failures that concern the whole image, such as an unsupported
  /// script.
  final RegionRef? region;

  /// A message identifier for presentation, never display text (M5).
  final String? detailMessageId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParseFailure &&
          kind == other.kind &&
          stage == other.stage &&
          region == other.region &&
          detailMessageId == other.detailMessageId;

  @override
  int get hashCode => Object.hash(kind, stage, region, detailMessageId);

  @override
  String toString() => 'ParseFailure(${kind.name} at ${stage.name})';
}
