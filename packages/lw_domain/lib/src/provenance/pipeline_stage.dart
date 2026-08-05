/// A stage of the parser pipeline, S1 through S8.
///
/// Mirrors `ARCHITECTURE.md` §6.1. S0 is deliberately absent: it is the P-OCR
/// port boundary and, per that section, "not part of the domain".
///
/// [ordinal] exists so that §6.2's forward-only rule — "no stage may consult a
/// later stage" — is checkable rather than merely stated. An ordering that
/// lives in a comment cannot be verified.
enum PipelineStage {
  /// S1 — Unicode normalisation, whitespace collapse, character-confusion
  /// handling. Every substitution recorded.
  normalisation(ordinal: 1),

  /// S2 — Layout reconstruction from geometry alone. No semantics.
  layoutReconstruction(ordinal: 2),

  /// S3 — Region classification: nutrition panel, ingredient list, other.
  regionClassification(ordinal: 3),

  /// S4 — Tokenisation into candidate label/value/unit triples.
  tokenisation(ordinal: 4),

  /// S5 — Field resolution against the rule pack synonym table.
  fieldResolution(ordinal: 5),

  /// S6 — Unit normalisation and energy conversion.
  unitNormalisation(ordinal: 6),

  /// S7 — Invariant evaluation, INV-01…10.
  invariantEvaluation(ordinal: 7),

  /// S8 — Confidence assignment from the S1/S2/S3 signals.
  confidenceAssignment(ordinal: 8);

  /// Defines a stage and its position in the pipeline.
  const PipelineStage({required this.ordinal});

  /// Position in the pipeline, 1–8. Ascends with execution order.
  final int ordinal;

  /// Whether this stage runs strictly before [other].
  bool precedes(PipelineStage other) => ordinal < other.ordinal;
}
