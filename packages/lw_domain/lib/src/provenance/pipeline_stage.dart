/// A stage of the parser pipeline, S1 through S8 including S5b.
///
/// Mirrors `ARCHITECTURE.md` §6.1. S0 is deliberately absent: it is the P-OCR
/// port boundary and, per that section, "not part of the domain".
///
/// [ordinal] exists so that §6.2's forward-only rule — "no stage may consult a
/// later stage" — is checkable rather than merely stated. An ordering that
/// lives in a comment cannot be verified.
///
/// > **Ordinals were renumbered when S5b was introduced (M11).** Serving
/// > resolution runs between field resolution and unit normalisation, so the
/// > three stages after it moved up by one. Nothing persists or serialises an
/// > ordinal — it is a comparison key, and a key that misorders the pipeline
/// > defeats the only purpose it has. Preserving stale numbers would have kept
/// > `precedes()` compiling while making it wrong.
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

  /// S5b — Serving resolution: declared serve, servings per pack, net
  /// quantity (FR-PAR-08).
  ///
  /// Runs after field resolution because it reuses the same qualifier and unit
  /// lexicons, and before unit normalisation because S7 needs the figures.
  servingResolution(ordinal: 6),

  /// S6 — Unit normalisation and energy conversion.
  unitNormalisation(ordinal: 7),

  /// S7 — Invariant evaluation, INV-01…10.
  invariantEvaluation(ordinal: 8),

  /// S8 — Confidence assignment from the S1/S2/S3 signals.
  confidenceAssignment(ordinal: 9);

  /// Defines a stage and its position in the pipeline.
  const PipelineStage({required this.ordinal});

  /// Position in the pipeline, 1–9. Ascends with execution order.
  final int ordinal;

  /// Whether this stage runs strictly before [other].
  bool precedes(PipelineStage other) => ordinal < other.ordinal;
}
