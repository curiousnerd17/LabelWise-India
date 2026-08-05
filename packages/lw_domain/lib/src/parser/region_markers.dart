import 'package:lw_domain/src/parser/classified_regions.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';

/// One structural cue that identifies a kind of region.
///
/// A marker is a **heading**, not a nutrient. `Nutritional Information` names
/// a block; `Energy` names a value inside one. Keeping the distinction is what
/// lets S3 stay out of the synonym table (Q13, `DATA_MODEL.md` §7.9).
final class RegionMarker {
  /// Records a marker.
  ///
  /// [text] is folded to lower case and trimmed once, here, so that matching
  /// cannot depend on how a marker was typed.
  ///
  /// Throws [ArgumentError] when [text] is blank, or when [kind] is
  /// `RegionKind.other` — `other` is the absence of a match, and a marker for
  /// it would make the fallback reachable two ways.
  RegionMarker({
    required String text,
    required this.kind,
    required this.strength,
  }) : text = text.trim().toLowerCase() {
    if (this.text.isEmpty) {
      throw ArgumentError.value(text, 'text', 'A marker must carry text.');
    }
    if (!kind.isClassified) {
      throw ArgumentError.value(
        kind,
        'kind',
        'A marker cannot classify a region as ${kind.name}.',
      );
    }
  }

  /// The cue, lower-cased and trimmed.
  final String text;

  /// What a line containing this cue identifies.
  final RegionKind kind;

  /// How firmly a hit on this cue counts — signal S2, carried into confidence.
  final ParseStrength strength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegionMarker &&
          text == other.text &&
          kind == other.kind &&
          strength == other.strength;

  @override
  int get hashCode => Object.hash(text, kind, strength);

  @override
  String toString() =>
      'RegionMarker("$text" -> ${kind.name}, ${strength.name})';
}

/// The structural cues S3 recognises.
///
/// **Injected, not hard-coded** (owner decision D1). The default set below is
/// Indian food-label vocabulary; a cosmetics or medicine module supplies its
/// own and reuses S1–S4 unchanged (`ARCHITECTURE.md` §11). Passing the table in
/// is what keeps Q13's reuse rationale true rather than merely stated.
///
/// It is **not** rule pack data. Q13 resolved that S3 must not consult the
/// pack, so the default lives in code and the caller may override it.
final class RegionMarkerTable {
  /// Creates a marker table.
  RegionMarkerTable(List<RegionMarker> markers)
      : markers = List<RegionMarker>.unmodifiable(markers);

  /// Indian food-label headings, per FSSAI labelling practice.
  ///
  /// Deliberately small. A set that grows by one entry per failing label
  /// becomes the synonym table Q13 excluded — in code, where no contributor
  /// can reach it (FR-KB-12). If this needs to grow much beyond its current
  /// size, that is evidence to reopen Q13, not evidence to add a line.
  static final RegionMarkerTable foodLabelDefaults =
      RegionMarkerTable(<RegionMarker>[
    RegionMarker(
      text: 'nutritional information',
      kind: RegionKind.nutritionPanel,
      strength: ParseStrength.exact,
    ),
    RegionMarker(
      text: 'nutrition information',
      kind: RegionKind.nutritionPanel,
      strength: ParseStrength.exact,
    ),
    RegionMarker(
      text: 'nutrition facts',
      kind: RegionKind.nutritionPanel,
      strength: ParseStrength.exact,
    ),
    RegionMarker(
      text: 'nutritional facts',
      kind: RegionKind.nutritionPanel,
      strength: ParseStrength.normalised,
    ),
    RegionMarker(
      text: 'per 100 g',
      kind: RegionKind.nutritionPanel,
      strength: ParseStrength.normalised,
    ),
    RegionMarker(
      text: 'per 100 ml',
      kind: RegionKind.nutritionPanel,
      strength: ParseStrength.normalised,
    ),
    RegionMarker(
      text: 'per serve',
      kind: RegionKind.nutritionPanel,
      strength: ParseStrength.heuristic,
    ),
    RegionMarker(
      text: 'per serving',
      kind: RegionKind.nutritionPanel,
      strength: ParseStrength.heuristic,
    ),
    RegionMarker(
      text: 'ingredients',
      kind: RegionKind.ingredientList,
      strength: ParseStrength.exact,
    ),
    RegionMarker(
      text: 'ingredient list',
      kind: RegionKind.ingredientList,
      strength: ParseStrength.exact,
    ),
  ]);

  /// The cues, in declaration order.
  final List<RegionMarker> markers;

  /// The strongest marker contained in [lineText], or null when none is.
  ///
  /// Matching is a case-insensitive substring test: real headings arrive with
  /// trailing colons, surrounding punctuation and neighbouring words, and an
  /// equality test would miss every one of them.
  ///
  /// When several markers hit, the strongest wins; ties resolve to the first
  /// in declaration order. Both rules exist so the recorded strength cannot
  /// depend on table ordering or iteration order (FR-PAR-02).
  RegionMarker? strongestMatch(String lineText) {
    if (lineText.isEmpty || markers.isEmpty) {
      return null;
    }
    final String folded = lineText.toLowerCase();
    RegionMarker? best;
    for (final RegionMarker m in markers) {
      if (!folded.contains(m.text)) {
        continue;
      }
      if (best == null || _rank(m.strength) < _rank(best.strength)) {
        best = m;
      }
    }
    return best;
  }

  @override
  String toString() => 'RegionMarkerTable(${markers.length} markers)';
}

/// Strongest first.
///
/// Written as an exhaustive switch rather than read from `index`, so that
/// adding a fourth parse strength is a compile error here instead of a silent
/// reordering of which marker wins.
int _rank(ParseStrength strength) => switch (strength) {
      ParseStrength.exact => 0,
      ParseStrength.normalised => 1,
      ParseStrength.heuristic => 2,
    };
