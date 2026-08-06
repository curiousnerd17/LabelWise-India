import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';

/// One printed form that declares which reference quantity a column carries.
final class BasisMarker {
  /// Records a marker.
  ///
  /// [text] is folded to lower case and trimmed once, here, so that matching
  /// cannot depend on how a marker was typed.
  ///
  /// Throws [ArgumentError] when [text] is blank.
  BasisMarker({
    required String text,
    required this.basis,
    required this.strength,
  }) : text = text.trim().toLowerCase() {
    if (this.text.isEmpty) {
      throw ArgumentError.value(text, 'text', 'A marker must carry text.');
    }
  }

  /// The printed form, lower-cased and trimmed.
  final String text;

  /// The reference quantity it declares.
  final Basis basis;

  /// How firmly a hit counts — signal S2, carried into confidence.
  final ParseStrength strength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BasisMarker &&
          text == other.text &&
          basis == other.basis &&
          strength == other.strength;

  @override
  int get hashCode => Object.hash(text, basis, strength);

  @override
  String toString() => 'BasisMarker("$text" -> ${basis.name})';
}

/// The column headings S5 can read a basis from.
///
/// **Injected, not hard-coded**, matching the pattern approved for
/// `RegionMarkerTable` at S3. Unlike that table this vocabulary is legitimately
/// nutrition-specific: S5 is the first stage of the nutrition-specific half of
/// the pipeline (`ARCHITECTURE.md` §11), so basis wording belongs here rather
/// than in S1–S4.
///
/// It is **not** rule pack data. The rule pack holds the nutrient synonym
/// table (§6.3); basis wording is a fixed, small, structural vocabulary that
/// the four priority categories share, so keeping it in code costs no
/// contribution path (FR-KB-12) and avoids a schema extension.
final class BasisMarkerTable {
  /// Creates a marker table.
  BasisMarkerTable(List<BasisMarker> markers)
      : markers = List<BasisMarker>.unmodifiable(markers);

  /// The headings Indian nutrition panels use.
  ///
  /// The bare `100 g` and `100 ml` forms are heuristic on purpose: they appear
  /// in headings that mean per-100 g and in serving descriptions such as
  /// `Per Serve (100 g)` that do not. Marking them weakly lets a stronger
  /// marker on the same heading win, and lets S8 discount them when nothing
  /// stronger appears.
  static final BasisMarkerTable defaults = BasisMarkerTable(<BasisMarker>[
    BasisMarker(
      text: 'per 100 g',
      basis: Basis.per100g,
      strength: ParseStrength.exact,
    ),
    BasisMarker(
      text: 'per 100g',
      basis: Basis.per100g,
      strength: ParseStrength.normalised,
    ),
    BasisMarker(
      text: '100 g',
      basis: Basis.per100g,
      strength: ParseStrength.heuristic,
    ),
    BasisMarker(
      text: 'per 100 ml',
      basis: Basis.per100ml,
      strength: ParseStrength.exact,
    ),
    BasisMarker(
      text: 'per 100ml',
      basis: Basis.per100ml,
      strength: ParseStrength.normalised,
    ),
    BasisMarker(
      text: '100 ml',
      basis: Basis.per100ml,
      strength: ParseStrength.heuristic,
    ),
    BasisMarker(
      text: 'per serve',
      basis: Basis.perServe,
      strength: ParseStrength.exact,
    ),
    BasisMarker(
      text: 'per serving',
      basis: Basis.perServe,
      strength: ParseStrength.exact,
    ),
    BasisMarker(
      text: 'per pack',
      basis: Basis.perPack,
      strength: ParseStrength.exact,
    ),
    BasisMarker(
      text: 'per packet',
      basis: Basis.perPack,
      strength: ParseStrength.normalised,
    ),
  ]);

  /// The markers, in declaration order.
  final List<BasisMarker> markers;

  /// The strongest marker contained in [headerText], or null when none is.
  ///
  /// Matching is a case-insensitive substring test: headings arrive with
  /// surrounding punctuation and extra words, such as `Per Serve (30 g)`.
  ///
  /// When several markers hit, the strongest wins; ties resolve to the first
  /// in declaration order. Both rules exist so the assigned basis cannot
  /// depend on table ordering or iteration order (FR-PAR-02).
  BasisMarker? strongestMatch(String headerText) {
    if (headerText.isEmpty || markers.isEmpty) {
      return null;
    }
    final String folded = headerText.toLowerCase();
    BasisMarker? best;
    for (final BasisMarker m in markers) {
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
  String toString() => 'BasisMarkerTable(${markers.length} markers)';
}

/// Strongest first. An exhaustive switch, so adding a fourth parse strength is
/// a compile error here rather than a silent reordering of which marker wins.
int _rank(ParseStrength strength) => switch (strength) {
      ParseStrength.exact => 0,
      ParseStrength.normalised => 1,
      ParseStrength.heuristic => 2,
    };
