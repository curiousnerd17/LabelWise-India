import 'package:lw_domain/src/label/qualifier.dart';
import 'package:lw_domain/src/parser/candidates.dart';
import 'package:lw_domain/src/parser/classified_regions.dart';
import 'package:lw_domain/src/parser/label_layout.dart';
import 'package:lw_domain/src/parser/normalised_text.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/qualifier_lexicon.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';

/// **S4 — Tokenisation.** Candidate shapes, with no meaning attached yet.
///
/// Nutrition lines become `(label, value, unit?, qualifier)` quadruples with a
/// column association; the ingredient list becomes an ordered, nested token
/// tree. Per `ARCHITECTURE.md` §6.1 as amended in v1.1 — the original triple
/// predated ADR-0027, and S4 is the last stage that sees the raw text in which
/// `<` or `About` is printed.
///
/// **No nutrition vocabulary.** S4 recognises the *shape* of a declaration —
/// words, then a number, then perhaps a unit — not the meaning of any word in
/// it. `Energy` and `Aqua` tokenise identically. That is what keeps S1–S4
/// reusable for cosmetics and medicine labels (`ARCHITECTURE.md` §11).
///
/// Pure and total: no I/O, no clock, no randomness (FR-PAR-01), and every
/// input yields a `StageResult` rather than an exception (FR-PAR-17).
///
/// **Tolerant of a misclassified region** (AR5, `DATA_MODEL.md` §7.9). S3
/// classifies on structural cues and will sometimes be wrong. S4 therefore
/// applies its rules to whatever region it is handed and lets weak output be
/// weak, rather than assuming the classification was correct.
///
/// [qualifiers] defaults to `QualifierLexicon.defaults` when omitted. It is a
/// nullable parameter rather than a defaulted one only because Dart requires
/// default values to be compile-time constants, and a marker is validated at
/// construction.
StageResult<Candidates> tokenise(
  ClassifiedRegions regions, {
  QualifierLexicon? qualifiers,
}) {
  // FR-PAR-17: nothing to tokenise is a structured failure, not an empty
  // success. S3 already declines a label in which neither region was found,
  // so reaching this means S4 was called with an unusable classification.
  if (!regions.hasNutritionPanel && !regions.hasIngredientList) {
    return const StageFailure<Candidates>(
      ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        stage: PipelineStage.tokenisation,
      ),
    );
  }

  final QualifierLexicon lexicon = qualifiers ?? QualifierLexicon.defaults;
  final ClassifiedRegion? panel = regions.nutritionPanel;
  final ClassifiedRegion? list = regions.ingredientList;

  return StageSuccess<Candidates>(
    Candidates(
      nutritionCandidates: panel == null
          ? const <NutritionCandidate>[]
          : _readPanel(panel, regions, lexicon),
      ingredientTokens:
          list == null ? const <IngredientToken>[] : _readIngredients(list),
      nutritionPanelPresent: regions.hasNutritionPanel,
      ingredientListPresent: regions.hasIngredientList,
    ),
  );
}

// ---------------------------------------------------------------- nutrition

/// Reads one candidate per line that carries both a label and a number.
///
/// A line with no digit declares nothing measurable; a line with no words
/// before its number has no label to resolve. Neither yields a candidate, and
/// neither is an error — FR-PAR-05 requires silence over invention.
List<NutritionCandidate> _readPanel(
  ClassifiedRegion panel,
  ClassifiedRegions regions,
  QualifierLexicon lexicon,
) {
  final List<NutritionCandidate> out = <NutritionCandidate>[];
  for (final LayoutLine line in panel.lines) {
    final NutritionCandidate? c = _readLine(line, regions, lexicon);
    if (c != null) {
      out.add(c);
    }
  }
  return out;
}

NutritionCandidate? _readLine(
  LayoutLine line,
  ClassifiedRegions regions,
  QualifierLexicon lexicon,
) {
  final List<String> tokens = _lineText(line).split(' ')
    ..removeWhere((String t) => t.isEmpty);
  if (tokens.isEmpty) {
    return null;
  }

  final int firstNumeric = tokens.indexWhere(_containsDigit);
  if (firstNumeric < 0) {
    return null;
  }

  // A qualifier marker sits between the label and the number when it is
  // printed detached: "Trans Fat < 0.5 g". Pulling it into the value part is
  // what stops it being mistaken for the last word of the label.
  int valueStart = firstNumeric;
  if (firstNumeric > 0 &&
      lexicon.read(tokens[firstNumeric - 1]).qualifier != Qualifier.exact) {
    valueStart = firstNumeric - 1;
  }

  final String label = tokens.sublist(0, valueStart).join(' ').trim();
  if (label.isEmpty) {
    return null;
  }

  final QualifierReading reading =
      lexicon.read(tokens.sublist(valueStart).join(' '));
  final List<String> valueTokens = reading.remainder.split(' ')
    ..removeWhere((String t) => t.isEmpty);
  if (valueTokens.isEmpty || !_containsDigit(valueTokens.first)) {
    return null;
  }

  final String unit = valueTokens.sublist(1).join(' ').trim();
  final List<int> indices = line.sourceIndices;

  return NutritionCandidate(
    labelText: label,
    valueText: valueTokens.first,
    unitText: unit.isEmpty ? null : unit,
    qualifier: reading.qualifier,
    columnIndex: _columnOfValue(line, regions),
    region: line.region,
    sourceIndices: indices,
    parseStrength: unit.isEmpty ? ParseStrength.heuristic : ParseStrength.exact,
  );
}

/// The column band holding the right-most element of the line.
///
/// In a per-100 g / per-serve panel the label sits in the left band and the
/// number in the band that gives it its basis, so the value's band is the one
/// S5 needs. Null when no band claims it — FR-PAR-05 forbids guessing.
int? _columnOfValue(LayoutLine line, ClassifiedRegions regions) {
  if (line.elements.isEmpty) {
    return null;
  }
  NormalisedElement rightmost = line.elements.first;
  for (final NormalisedElement e in line.elements) {
    if (e.region.left > rightmost.region.left) {
      rightmost = e;
    }
  }
  return regions.columnIndexOf(rightmost.sourceIndex);
}

// -------------------------------------------------------------- ingredients

/// Splits the declaration into an ordered, nested token list.
///
/// The lines are joined first: an ingredient list wraps across lines and a
/// per-line split would cut entries in half.
List<IngredientToken> _readIngredients(ClassifiedRegion list) {
  final List<String> texts = list.lines.map(_lineText).toList()
    ..removeWhere((String t) => t.trim().isEmpty);
  final String body = _stripHeading(texts.join(' ').trim());
  final List<int> indices = list.sourceIndices;
  return _splitEntries(body, list.region, indices);
}

/// Removes a leading heading up to and including its colon.
///
/// Structural, not vocabulary-based: a heading is punctuated from its content
/// by a colon on every label in every language, so this stays true for a
/// cosmetics module that swapped the marker table. Absent a colon nothing is
/// stripped, because there is then no structural evidence of a heading.
String _stripHeading(String text) {
  final int colon = text.indexOf(':');
  if (colon < 0) {
    return text.trim();
  }
  return text.substring(colon + 1).trim();
}

/// Splits on commas at bracket depth zero, recursing into bracketed groups.
///
/// **Unbalanced brackets are repaired, never thrown on** (FR-PAR-17). An
/// unclosed group closes at the end of the text and its token is marked
/// `ParseStrength.heuristic`; a stray closing bracket at depth zero is treated
/// as literal text. OCR drops brackets routinely, and refusing the whole list
/// over one missing character would discard every ingredient on the packet.
List<IngredientToken> _splitEntries(
  String text,
  RegionRef region,
  List<int> sourceIndices,
) {
  final List<IngredientToken> out = <IngredientToken>[];
  final List<_Segment> segments = _segment(text);

  for (final _Segment s in segments) {
    // Tested against `raw`, not `name`: an entry that is nothing but a
    // bracketed group has an empty name and must still be kept, or a whole
    // sub-list disappears from a legally ordered declaration.
    if (s.raw.trim().isEmpty) {
      continue;
    }
    out.add(
      IngredientToken(
        position: out.length + 1,
        rawText: s.raw.trim(),
        region: region,
        sourceIndices: sourceIndices,
        parseStrength:
            s.repaired ? ParseStrength.heuristic : ParseStrength.exact,
        children: s.inner.isEmpty
            ? const <IngredientToken>[]
            : _splitEntries(s.inner, region, sourceIndices),
      ),
    );
  }
  return out;
}

/// One comma-delimited entry, with its bracketed group separated out.
final class _Segment {
  _Segment(this.raw, this.name, this.inner, this.repaired);

  /// The entry exactly as printed, brackets included.
  final String raw;

  /// The entry with any bracketed group removed.
  final String name;

  /// The contents of the bracketed group, empty when there was none.
  final String inner;

  /// Whether a missing closing bracket had to be supplied.
  final bool repaired;
}

List<_Segment> _segment(String text) {
  final List<_Segment> out = <_Segment>[];
  final StringBuffer raw = StringBuffer();
  final StringBuffer name = StringBuffer();
  final StringBuffer inner = StringBuffer();
  int depth = 0;
  bool repaired = false;

  void flush() {
    if (raw.toString().trim().isNotEmpty) {
      out.add(_Segment(
        raw.toString(),
        name.toString(),
        inner.toString(),
        repaired,
      ));
    }
    raw.clear();
    name.clear();
    inner.clear();
    repaired = false;
  }

  for (int i = 0; i < text.length; i++) {
    final String c = text[i];
    if (c == '(') {
      depth++;
      raw.write(c);
      if (depth > 1) {
        inner.write(c);
      }
      continue;
    }
    if (c == ')') {
      if (depth == 0) {
        // A closer with no opener is text, not structure.
        raw.write(c);
        name.write(c);
        continue;
      }
      depth--;
      raw.write(c);
      if (depth > 0) {
        inner.write(c);
      }
      continue;
    }
    if (c == ',' && depth == 0) {
      flush();
      continue;
    }
    raw.write(c);
    if (depth > 0) {
      inner.write(c);
    } else {
      name.write(c);
    }
  }

  if (depth > 0) {
    repaired = true;
  }
  flush();
  return out;
}

// ------------------------------------------------------------------ shared

String _lineText(LayoutLine line) =>
    line.elements.map((NormalisedElement e) => e.text).join(' ');

bool _containsDigit(String token) {
  for (int i = 0; i < token.length; i++) {
    final int c = token.codeUnitAt(i);
    if (c >= 48 && c <= 57) {
      return true;
    }
  }
  return false;
}
