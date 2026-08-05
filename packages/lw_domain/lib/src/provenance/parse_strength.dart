/// How firmly a parse rule matched — confidence signal **S2**.
///
/// These are exactly the three grades `rulepack/schema/synonyms.schema.json`
/// assigns to every label-text pattern, and exactly the values
/// `rulepack/rules/confidence.json` keys its assignment table on. A fourth
/// value here would be unrepresentable in the pack.
///
/// Per ADR-0010 the signal priority is S3 (arithmetic invariants) first, then
/// S2, then S1. Parse strength is therefore secondary: it says how the text
/// matched, not whether the number reconciles.
enum ParseStrength {
  /// Canonical label text matched verbatim.
  exact,

  /// Matched after documented normalisation — case, spacing, or a known
  /// synonym.
  normalised,

  /// Matched by positional or fuzzy inference.
  heuristic,
}
