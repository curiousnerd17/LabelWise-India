import 'package:lw_domain/src/label/qualifier.dart';

/// The result of reading a qualifier off the front of a declared value.
final class QualifierReading {
  /// Records a reading.
  const QualifierReading({required this.qualifier, required this.remainder});

  /// The qualifier found, or `Qualifier.exact` when the value carried none.
  final Qualifier qualifier;

  /// The value text with the qualifier marker removed and trimmed.
  final String remainder;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QualifierReading &&
          qualifier == other.qualifier &&
          remainder == other.remainder;

  @override
  int get hashCode => Object.hash(qualifier, remainder);

  @override
  String toString() => 'QualifierReading(${qualifier.name}, "$remainder")';
}

/// One printed form that declares a qualifier.
final class QualifierEntry {
  /// Records a marker.
  ///
  /// Throws [ArgumentError] when [marker] is blank, or when [qualifier] is
  /// `Qualifier.exact` — exact is the **absence** of a marker (ADR-0027
  /// decision 5), so a marker declaring it would make the default reachable
  /// two ways and the reading order-dependent.
  QualifierEntry({required String marker, required this.qualifier})
      : marker = marker.trim().toLowerCase() {
    if (this.marker.isEmpty) {
      throw ArgumentError.value(marker, 'marker', 'A marker must carry text.');
    }
    if (qualifier == Qualifier.exact) {
      throw ArgumentError.value(
        qualifier,
        'qualifier',
        'Exact is the absence of a marker, not a marker.',
      );
    }
  }

  /// The printed form, lower-cased and trimmed.
  final String marker;

  /// What it declares.
  final Qualifier qualifier;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QualifierEntry &&
          marker == other.marker &&
          qualifier == other.qualifier;

  @override
  int get hashCode => Object.hash(marker, qualifier);

  @override
  String toString() => 'QualifierEntry("$marker" -> ${qualifier.name})';
}

/// The printed forms S4 recognises as qualifiers (FR-PAR-18, ADR-0027).
///
/// Lexical, not semantic. `<` means the same thing on a shampoo bottle as on a
/// biscuit packet, which is why reading it here does not cost S1–S4 their
/// domain independence (`ARCHITECTURE.md` §11).
///
/// S4 is the last stage that sees the raw text in which `<` or `About` is
/// printed: S5 resolves labels to nutrients and S6 normalises units, and
/// neither re-reads the value. If the qualifier is not read here it is lost,
/// and a `< 0.5 g` trans fat declaration silently becomes `0.5 g`.
final class QualifierLexicon {
  /// Creates a lexicon.
  QualifierLexicon(List<QualifierEntry> entries)
      : entries = List<QualifierEntry>.unmodifiable(entries);

  /// The forms found on Indian food labels, per `ANNOTATION_GUIDE.md` §4.2
  /// and §4.4.
  static final QualifierLexicon defaults = QualifierLexicon(<QualifierEntry>[
    QualifierEntry(marker: '<', qualifier: Qualifier.lessThan),
    QualifierEntry(marker: 'less than', qualifier: Qualifier.lessThan),
    QualifierEntry(marker: '>', qualifier: Qualifier.greaterThan),
    QualifierEntry(marker: 'greater than', qualifier: Qualifier.greaterThan),
    QualifierEntry(marker: 'more than', qualifier: Qualifier.greaterThan),
    QualifierEntry(marker: '~', qualifier: Qualifier.approximately),
    QualifierEntry(marker: 'about', qualifier: Qualifier.approximately),
    QualifierEntry(marker: 'approximately', qualifier: Qualifier.approximately),
    QualifierEntry(marker: 'approx', qualifier: Qualifier.approximately),
  ]);

  /// The markers, in declaration order.
  final List<QualifierEntry> entries;

  /// Reads a leading qualifier off [valueText].
  ///
  /// Returns `Qualifier.exact` with the trimmed input when no marker leads it,
  /// which is the canonical representation of an unqualified value.
  ///
  /// The **longest** matching marker wins, so `approximately` is not read as
  /// `approx` followed by stray text. An alphabetic marker must end at a word
  /// boundary, so `About` is a qualifier and `Aboutu` is not; symbol markers
  /// need no boundary because `<0.5` is printed exactly that way.
  QualifierReading read(String valueText) {
    final String trimmed = valueText.trim();
    if (trimmed.isEmpty || entries.isEmpty) {
      return QualifierReading(qualifier: Qualifier.exact, remainder: trimmed);
    }
    final String folded = trimmed.toLowerCase();

    QualifierEntry? best;
    for (final QualifierEntry e in entries) {
      if (!folded.startsWith(e.marker)) {
        continue;
      }
      if (!_endsAtBoundary(folded, e.marker)) {
        continue;
      }
      if (best == null || e.marker.length > best.marker.length) {
        best = e;
      }
    }

    if (best == null) {
      return QualifierReading(qualifier: Qualifier.exact, remainder: trimmed);
    }
    return QualifierReading(
      qualifier: best.qualifier,
      remainder: trimmed.substring(best.marker.length).trim(),
    );
  }

  @override
  String toString() => 'QualifierLexicon(${entries.length} markers)';
}

/// Whether [marker] ends at a word boundary within [folded].
///
/// Only alphabetic markers need one. A symbol marker such as `<` is printed
/// flush against its number.
bool _endsAtBoundary(String folded, String marker) {
  if (!_isAlphabetic(marker[marker.length - 1])) {
    return true;
  }
  if (folded.length == marker.length) {
    return true;
  }
  return !_isAlphabetic(folded[marker.length]);
}

bool _isAlphabetic(String c) {
  final int code = c.codeUnitAt(0);
  return (code >= 97 && code <= 122) || (code >= 65 && code <= 90);
}
