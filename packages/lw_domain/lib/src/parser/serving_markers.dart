import 'package:lw_domain/src/label/serving_facts.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';

/// One printed wording that names a serving figure.
///
/// The direct analogue of `BasisMarker` and `RegionMarker`: text, what it
/// means, and how firmly a match on it counts.
final class ServingMarker {
  /// Records a wording.
  ///
  /// [text] is matched case-insensitively against a whitespace-collapsed line,
  /// so a marker is stored lower-case and callers need not normalise.
  ServingMarker({
    required String text,
    required this.field,
    required this.strength,
  }) : text = text.toLowerCase();

  /// The wording as printed, lower-cased.
  final String text;

  /// Which serving figure this wording names.
  final ServingField field;

  /// How firmly a match counts — signal S2.
  final ParseStrength strength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServingMarker &&
          text == other.text &&
          field == other.field &&
          strength == other.strength;

  @override
  int get hashCode => Object.hash(text, field, strength);

  @override
  String toString() => 'ServingMarker("$text" -> ${field.name})';
}

/// The wordings S5b recognises as naming a serving figure.
///
/// **Built-in default, injectable** — the same arrangement as
/// `RegionMarkerTable`, `BasisMarkerTable`, `UnitLexicon` and
/// `QualifierLexicon`. Serving markers are deliberately *not* rule pack data in
/// M11: none of the other four lexicons is, `synonyms.json` covers nutrient
/// wording only, and promoting one lexicon alone would make it the odd one out.
///
/// ## Vocabulary provenance
///
/// Every entry is classified, because a marker table that mixes gazetted terms
/// with guesses cannot be audited:
///
/// **Specified** — the term the regulation itself uses:
/// * `serving size` — FSSAI (Labelling and Display) Regulations 2020, the
///   per-serving nutritional declaration.
/// * `servings per pack` — the same regulation's servings-per-package figure.
/// * `net quantity` — Legal Metrology (Packaged Commodities) Rules 2011, r.6.
///
/// **Compatibility aliases** — wordings observed in print that mean the same
/// thing, admitted at reduced strength because they are convention rather than
/// specification: `serve size`, `servings per package`, `servings per
/// container`, `number of servings`, `no. of servings`, `net wt`, `net weight`,
/// `net qty`, `net content`.
///
/// **Heuristic** — a bare plural `servings`, which carries meaning only because
/// the singular *per serving* is a column header and the plural is not. It is
/// what makes `About 4 servings` readable.
///
/// ## Deliberately unsupported
///
/// These are **not** markers, and a label printing only these yields
/// `ServingNotDeclared` rather than a guess:
///
/// | Pattern | Why refused |
/// |---|---|
/// | `Pack of 4` | Multipack count or serving count — nothing settles which |
/// | `4 × 30 g`, `30 g × 4` | Serving count, multipack count or net quantity |
/// | `250 ml bottle` | A container description, not a declared net quantity |
/// | bare `serving` | Collides with the `per serving` column header |
/// | bare `quantity`, `weight` | Far too broad on a printed pack |
///
/// Where such a phrase *does* sit beside a real marker, the one-marker-one-
/// number rule in S5b turns it into `ambiguousMatch` rather than a reading.
final class ServingMarkerTable {
  /// Records the table.
  ServingMarkerTable(List<ServingMarker> markers)
      : markers = List<ServingMarker>.unmodifiable(markers);

  /// The default vocabulary. See the class documentation for provenance.
  static final ServingMarkerTable defaults = ServingMarkerTable(<ServingMarker>[
    // ---------------------------------------------------------- serving size
    ServingMarker(
      text: 'serving size',
      field: ServingField.servingSize,
      strength: ParseStrength.exact,
    ),
    ServingMarker(
      text: 'serve size',
      field: ServingField.servingSize,
      strength: ParseStrength.normalised,
    ),
    // ------------------------------------------------------ servings per pack
    // Longest first is not required — strongestMatch sorts by length — but the
    // more specific wordings are listed together for review.
    ServingMarker(
      text: 'servings per pack',
      field: ServingField.servingsPerPack,
      strength: ParseStrength.exact,
    ),
    ServingMarker(
      text: 'servings per package',
      field: ServingField.servingsPerPack,
      strength: ParseStrength.normalised,
    ),
    ServingMarker(
      text: 'servings per container',
      field: ServingField.servingsPerPack,
      strength: ParseStrength.normalised,
    ),
    ServingMarker(
      text: 'number of servings',
      field: ServingField.servingsPerPack,
      strength: ParseStrength.normalised,
    ),
    ServingMarker(
      text: 'no. of servings',
      field: ServingField.servingsPerPack,
      strength: ParseStrength.normalised,
    ),
    ServingMarker(
      text: 'servings',
      field: ServingField.servingsPerPack,
      strength: ParseStrength.heuristic,
    ),
    // ----------------------------------------------------------- net quantity
    ServingMarker(
      text: 'net quantity',
      field: ServingField.netQuantity,
      strength: ParseStrength.exact,
    ),
    ServingMarker(
      text: 'net weight',
      field: ServingField.netQuantity,
      strength: ParseStrength.normalised,
    ),
    ServingMarker(
      text: 'net wt',
      field: ServingField.netQuantity,
      strength: ParseStrength.normalised,
    ),
    ServingMarker(
      text: 'net qty',
      field: ServingField.netQuantity,
      strength: ParseStrength.normalised,
    ),
    ServingMarker(
      text: 'net content',
      field: ServingField.netQuantity,
      strength: ParseStrength.normalised,
    ),
  ]);

  /// Every marker, in declaration order.
  final List<ServingMarker> markers;

  /// The longest marker contained in [lineText], or null.
  ///
  /// **Longest wins, then declaration order** — identical to
  /// `BasisMarkerTable.strongestMatch`. Longest matters here more than
  /// anywhere: `servings` is a substring of `servings per pack`, and preferring
  /// the shorter would read every pack-count line at `HEURISTIC` when an
  /// `EXACT` wording was printed.
  ///
  /// Ties are broken by declaration order rather than by strength, so the table
  /// is deterministic by construction and the output cannot depend on how the
  /// list happened to be sorted.
  ServingMarker? strongestMatch(String lineText) {
    final String haystack = lineText.toLowerCase();
    if (haystack.isEmpty) {
      return null;
    }
    ServingMarker? best;
    for (final ServingMarker m in markers) {
      if (!haystack.contains(m.text)) {
        continue;
      }
      if (best == null || m.text.length > best.text.length) {
        best = m;
      }
    }
    return best;
  }

  @override
  String toString() => 'ServingMarkerTable(${markers.length} markers)';
}
