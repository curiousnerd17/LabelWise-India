import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/unit.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';

/// One label wording that identifies a nutrient, and how firmly it matches.
///
/// Mirrors an entry in `rulepack/nutrients/synonyms.json`. The strength is
/// confidence signal **S2** and is carried through to `Provenance`
/// (FR-PAR-13).
final class SynonymPattern {
  /// Records a label wording.
  const SynonymPattern({
    required this.text,
    required this.strength,
    this.caseSensitive = false,
  });

  /// The wording as it appears on labels, e.g. `Energy Value`.
  final String text;

  /// How firmly a match on this wording counts.
  final ParseStrength strength;

  /// Whether casing must match. Defaults to false, matching the rule pack
  /// schema, so `ENERGY` and `energy` resolve without separate patterns.
  final bool caseSensitive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SynonymPattern &&
          text == other.text &&
          strength == other.strength &&
          caseSensitive == other.caseSensitive;

  @override
  int get hashCode => Object.hash(text, strength, caseSensitive);

  @override
  String toString() => 'SynonymPattern("$text", ${strength.name})';
}

/// Every wording that identifies one nutrient, with the units it may carry.
final class SynonymEntry {
  /// Records the wordings for one nutrient.
  ///
  /// Throws [ArgumentError] when [patterns] is empty: the rule pack schema
  /// sets `minItems: 1`, and a domain type must not accept what the schema
  /// forbids.
  SynonymEntry({
    required this.nutrient,
    required List<SynonymPattern> patterns,
    required List<Unit> expectedUnits,
  })  : patterns = List<SynonymPattern>.unmodifiable(patterns),
        expectedUnits = List<Unit>.unmodifiable(expectedUnits) {
    if (patterns.isEmpty) {
      throw ArgumentError(
        'Synonym entry for ${nutrient.name} has no pattern. A nutrient no '
        'wording can reach is unreachable content.',
      );
    }
  }

  /// The nutrient these wordings identify.
  final NutrientId nutrient;

  /// The wordings, in rule pack order.
  final List<SynonymPattern> patterns;

  /// The units this nutrient plausibly carries.
  ///
  /// A declared unit outside this set lowers confidence rather than failing
  /// the parse — the label may be unusual rather than misread.
  final List<Unit> expectedUnits;
}

/// The result of resolving a label wording to a nutrient.
final class SynonymMatch {
  /// Records a resolved wording.
  const SynonymMatch({
    required this.nutrient,
    required this.pattern,
  });

  /// The nutrient the wording identifies.
  final NutrientId nutrient;

  /// The pattern that matched.
  final SynonymPattern pattern;

  /// How firmly it matched — signal S2, carried into `Provenance`.
  ParseStrength get strength => pattern.strength;

  @override
  String toString() => 'SynonymMatch(${nutrient.name}, ${strength.name})';
}

/// The nutrient synonym table, as a **domain type**.
///
/// `rulepack/nutrients/synonyms.json` is the authored source; `lw_rulepack`
/// deserialises it and builds this. The domain never sees JSON
/// (`ARCHITECTURE.md` §2.2) — the moment it did, the rule pack format would
/// have leaked into the business logic.
///
/// Holding the wordings as data rather than code is what keeps the project's
/// highest-frequency contribution path open: a contributor who spots an
/// unhandled label variant adds a line of JSON, not a line of Dart
/// (FR-KB-12, `ARCHITECTURE.md` §6.3).
final class SynonymTable {
  /// Builds a lookup table.
  ///
  /// Throws [ArgumentError] when the same wording maps to two nutrients.
  /// An ambiguous table would make resolution depend on entry order, which
  /// breaks byte-identical determinism (FR-PAR-02).
  SynonymTable(List<SynonymEntry> entries)
      : entries = List<SynonymEntry>.unmodifiable(entries),
        _index = _buildIndex(entries);

  /// The entries, in rule pack order.
  final List<SynonymEntry> entries;

  final Map<String, SynonymMatch> _index;

  static Map<String, SynonymMatch> _buildIndex(List<SynonymEntry> entries) {
    final Map<String, SynonymMatch> index = <String, SynonymMatch>{};
    for (final SynonymEntry entry in entries) {
      for (final SynonymPattern pattern in entry.patterns) {
        final String key =
            pattern.caseSensitive ? pattern.text : pattern.text.toLowerCase();
        final SynonymMatch? existing = index[key];
        if (existing != null && existing.nutrient != entry.nutrient) {
          throw ArgumentError(
            'Wording "${pattern.text}" maps to both '
            '${existing.nutrient.name} and ${entry.nutrient.name}. An '
            'ambiguous table makes resolution order-dependent.',
          );
        }
        index[key] = SynonymMatch(nutrient: entry.nutrient, pattern: pattern);
      }
    }
    return index;
  }

  /// Resolves a label wording to a nutrient, or null when nothing matches.
  ///
  /// Returns null rather than a best guess. A confident wrong answer is the
  /// failure this project exists to avoid (FR-PAR-05, P1).
  SynonymMatch? match(String labelText) {
    if (labelText.isEmpty) {
      return null;
    }
    final SynonymMatch? caseSensitiveHit = _index[labelText];
    if (caseSensitiveHit != null) {
      return caseSensitiveHit;
    }
    final SynonymMatch? hit = _index[labelText.toLowerCase()];
    if (hit == null || hit.pattern.caseSensitive) {
      return null;
    }
    return hit;
  }

  /// The units [nutrient] plausibly carries, or empty when it has no entry.
  List<Unit> expectedUnitsFor(NutrientId nutrient) {
    for (final SynonymEntry entry in entries) {
      if (entry.nutrient == nutrient) {
        return entry.expectedUnits;
      }
    }
    return const <Unit>[];
  }

  @override
  String toString() => 'SynonymTable(${entries.length} entries)';
}
