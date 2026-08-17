import 'package:lw_domain/src/label/checked_arithmetic.dart';
import 'package:lw_domain/src/label/dimension.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/label/serving_facts.dart';
import 'package:lw_domain/src/label/unit.dart';
import 'package:lw_domain/src/parser/classified_regions.dart';
import 'package:lw_domain/src/parser/label_layout.dart';
import 'package:lw_domain/src/parser/normalised_text.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/qualifier_lexicon.dart';
import 'package:lw_domain/src/parser/serving_markers.dart';
import 'package:lw_domain/src/parser/serving_resolution.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/parser/unit_lexicon.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';

/// **S5b — serving resolution (FR-PAR-08).**
///
/// Extracts the declared serving size, servings per pack and net quantity.
/// Until this stage existed, `ServingFacts` was never populated, which made
/// INV-08/09/10 permanently `INAPPLICABLE` and FR-L1-03 and FR-L1-05 —
/// whole-pack values and serving reconciliation — impossible to compute.
///
/// **Conservative by construction.** The stage never chooses between
/// disagreeing readings, never infers a count from arithmetic, never converts
/// across dimensions, and never upgrades a parse strength. Where a label is
/// ambiguous it says so, because a wrong serving size is worse than no serving
/// size: every per-serve figure downstream is scaled by it.
///
/// Reads the nutrition panel and `other` regions. The ingredient list is
/// excluded — a serving figure is never declared inside it, and scanning it
/// would only create opportunities to misread.
StageResult<ServingResolution> resolveServing(
  ClassifiedRegions regions, {
  ServingMarkerTable? markers,
  UnitLexicon? units,
  QualifierLexicon? qualifiers,
}) {
  if (regions.regions.isEmpty) {
    // FR-PAR-17: nothing to read is a structured failure, not an empty
    // success. S3 declines a label with no region, so reaching this means S5b
    // was called with an empty result.
    return const StageFailure<ServingResolution>(
      ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        stage: PipelineStage.servingResolution,
      ),
    );
  }

  final ServingMarkerTable markerTable = markers ?? ServingMarkerTable.defaults;
  final UnitLexicon unitTable = units ?? UnitLexicon.defaults;
  final QualifierLexicon qualifierTable =
      qualifiers ?? QualifierLexicon.defaults;

  final Map<ServingField, List<ServingCandidate>> found =
      <ServingField, List<ServingCandidate>>{};
  final Set<ServingField> sawAmbiguousLine = <ServingField>{};

  for (final ClassifiedRegion region in regions.regions) {
    if (region.kind == RegionKind.ingredientList) {
      continue;
    }
    for (final LayoutLine line in region.lines) {
      final String text =
          line.elements.map((NormalisedElement e) => e.text).join(' ');
      final ServingMarker? marker = markerTable.strongestMatch(text);
      if (marker == null) {
        continue;
      }
      final _Reading reading =
          _read(text, marker, unitTable, qualifierTable, line);
      switch (reading) {
        case _ReadingAmbiguous():
          sawAmbiguousLine.add(marker.field);
        case _ReadingNone():
          break;
        case _ReadingOk(candidate: final ServingCandidate c):
          (found[marker.field] ??= <ServingCandidate>[]).add(c);
      }
    }
  }

  final Map<ServingField, ServingOutcome> outcomes =
      <ServingField, ServingOutcome>{};
  Quantity? size;
  Quantity? perPack;
  Quantity? net;

  // ServingField.values order, not discovery order: the output must not depend
  // on where on the label a figure happened to be printed (FR-PAR-02).
  for (final ServingField field in ServingField.values) {
    final List<ServingCandidate> candidates =
        found[field] ?? const <ServingCandidate>[];
    final ServingOutcome outcome =
        _resolve(field, candidates, sawAmbiguousLine.contains(field));
    outcomes[field] = outcome;
    if (outcome is ServingResolved) {
      switch (field) {
        case ServingField.servingSize:
          size = outcome.candidate.quantity;
        case ServingField.servingsPerPack:
          perPack = outcome.candidate.quantity;
        case ServingField.netQuantity:
          net = outcome.candidate.quantity;
      }
    }
  }

  return StageSuccess<ServingResolution>(
    ServingResolution(
      facts: ServingFacts(
        servingSize: size,
        servingsPerPack: perPack,
        netQuantity: net,
      ),
      outcomes: outcomes,
    ),
  );
}

/// Reconciles the readings for one field.
///
/// **Never first-wins, last-wins or nearest-wins.** Two readings reconcile only
/// when they denote the same value; anything else is reported with every
/// candidate retained, so a correction UI can show the user what was found
/// rather than a choice nobody made.
ServingOutcome _resolve(
  ServingField field,
  List<ServingCandidate> candidates,
  bool sawAmbiguousLine,
) {
  if (candidates.isEmpty) {
    // A line that named the field but could not be read is not the same as no
    // line at all — the first is unresolved, the second absent (MI-08).
    return sawAmbiguousLine
        ? ServingUnresolved(
            reason: UnresolvedReason.ambiguousMatch,
            candidates: const <ServingCandidate>[],
          )
        : const ServingNotDeclared();
  }
  if (candidates.length == 1 && !sawAmbiguousLine) {
    return ServingResolved(candidates.single);
  }

  final ServingCandidate first = candidates.first;
  for (final ServingCandidate other in candidates.skip(1)) {
    if (!_equivalent(first, other)) {
      return ServingUnresolved(
        reason: UnresolvedReason.ambiguousMatch,
        candidates: candidates,
      );
    }
  }
  if (sawAmbiguousLine) {
    // Agreeing readings alongside a line we could not parse: the agreement may
    // be a coincidence of the two we could read.
    return ServingUnresolved(
      reason: UnresolvedReason.ambiguousMatch,
      candidates: candidates,
    );
  }

  // Every reading agrees. Merge them: the strongest wording wins the strength,
  // and every source index is retained so provenance names all of them.
  ServingCandidate strongest = first;
  final List<int> merged = <int>[];
  for (final ServingCandidate c in candidates) {
    if (_stronger(c.parseStrength, strongest.parseStrength)) {
      strongest = c;
    }
    for (final int i in c.sourceIndices) {
      if (!merged.contains(i)) {
        merged.add(i);
      }
    }
  }
  merged.sort();
  return ServingResolved(
    ServingCandidate(
      field: strongest.field,
      quantity: strongest.quantity,
      parseStrength: strongest.parseStrength,
      region: strongest.region,
      sourceIndices: merged,
      matchedBy: strongest.matchedBy,
    ),
  );
}

/// Whether two readings denote the same declaration.
///
/// Equality is `Quantity`'s, which **includes the qualifier** (MI-14), so
/// `about 30 g` and `30 g` are two different declarations and do not reconcile.
/// Values in different units are compared after conversion within their
/// dimension; across dimensions they never reconcile, because converting grams
/// to millilitres would invent a density.
bool _equivalent(ServingCandidate a, ServingCandidate b) {
  if (a.quantity.qualifier != b.quantity.qualifier) {
    return false;
  }
  if (!a.quantity.unit.isConvertibleTo(b.quantity.unit)) {
    return false;
  }
  return a.quantity.convertTo(b.quantity.unit) == b.quantity;
}

bool _stronger(ParseStrength a, ParseStrength b) => a.index < b.index;

/// What one line yielded.
sealed class _Reading {
  const _Reading();
}

final class _ReadingOk extends _Reading {
  const _ReadingOk(this.candidate);
  final ServingCandidate candidate;
}

final class _ReadingNone extends _Reading {
  const _ReadingNone();
}

final class _ReadingAmbiguous extends _Reading {
  const _ReadingAmbiguous();
}

/// Reads one marked line.
///
/// **One marker, one number.** A line carrying two numeric literals is
/// ambiguous by construction — `30 g x 4 servings` may declare a serve size, a
/// pack count, a multipack count, or two of them, and nothing in the text
/// settles which. Refusing is the only honest reading.
_Reading _read(
  String text,
  ServingMarker marker,
  UnitLexicon units,
  QualifierLexicon qualifiers,
  LayoutLine line,
) {
  final String remainder = _withoutMarker(text, marker.text);
  final QualifierReading qualified = qualifiers.read(remainder);
  final List<_Number> numbers = _numbersIn(qualified.remainder);
  if (numbers.isEmpty) {
    return const _ReadingNone();
  }
  if (numbers.length > 1) {
    return const _ReadingAmbiguous();
  }

  final _Number number = numbers.single;
  final Unit? unit = _unitFor(marker.field, qualified.remainder, number, units);
  if (unit == null) {
    return const _ReadingAmbiguous();
  }
  final int? scaled = _scaleToUnit(number, unit);
  if (scaled == null || scaled <= 0) {
    // Zero and negative are not declarations a pack can make: a zero serve
    // divides by nothing and a negative one is a misread. Overflow lands here
    // too, so an absurd magnitude never enters the pipeline at all.
    return const _ReadingAmbiguous();
  }

  return _ReadingOk(
    ServingCandidate(
      field: marker.field,
      quantity: Quantity.qualified(scaled, unit, qualified.qualifier),
      parseStrength: marker.strength,
      region: line.region,
      sourceIndices: line.sourceIndices,
      matchedBy: _S5bRules.marker,
    ),
  );
}

/// [text] with the marker wording removed and leading separators stripped.
///
/// **The marker is removed, not sliced past.** A value is not always printed
/// *after* the wording that names it: `Serving Size: 30 g` puts it after, and
/// `About 4 servings` puts it before. Taking the substring after the marker
/// reads the second as empty, which silently loses both the count and the
/// `About` qualifier — and, worse, makes a two-number line look like no
/// declaration at all rather than an ambiguous one.
///
/// Removing the marker instead handles prefix and suffix wordings through one
/// path, so no second parser and no positional special case is needed.
///
/// Leading separator punctuation is then stripped so the remainder begins at
/// the value. `QualifierLexicon.read` matches a qualifier only as a **prefix**
/// of the text it is given, so `": approx 30 g"` would read as unqualified —
/// the qualifier must be first for the existing lexicon to see it. `~` and `<`
/// are deliberately not stripped: they *are* qualifiers.
String _withoutMarker(String text, String marker) {
  final int at = text.toLowerCase().indexOf(marker);
  final String withoutMarker = at < 0
      ? text
      // A space replaces the marker so that removing it cannot glue the tokens
      // on either side into one.
      : '${text.substring(0, at)} ${text.substring(at + marker.length)}';
  return _stripLeadingSeparators(withoutMarker);
}

/// [text] with leading whitespace and separator punctuation removed.
String _stripLeadingSeparators(String text) {
  int start = 0;
  while (start < text.length && _isSeparator(text[start])) {
    start++;
  }
  return text.substring(start).trim();
}

/// Whether [c] separates a label from its value rather than forming part of it.
bool _isSeparator(String c) =>
    c == ' ' ||
    c == '\t' ||
    c == ':' ||
    c == ';' ||
    c == '=' ||
    c == '.' ||
    c == ',' ||
    c == '-' ||
    c == '–' ||
    c == '—';

/// The unit for [field], or null when it cannot be determined.
///
/// `servingsPerPack` is dimensionless and is never printed with a unit, so it
/// is [Unit.count] by definition. The other two must carry a mass or volume
/// unit; anything else — a serve declared in kilocalories — is refused rather
/// than assumed.
Unit? _unitFor(
  ServingField field,
  String remainder,
  _Number number,
  UnitLexicon units,
) {
  if (field == ServingField.servingsPerPack) {
    // A stray unit beside a count means the line is not what it appeared to
    // be: "servings 30 g" is not a pack count.
    final UnitVariant? stray = units.resolve(_wordAfter(remainder, number.end));
    return stray == null ? Unit.count : null;
  }
  final UnitVariant? variant = units.resolve(_wordAfter(remainder, number.end));
  if (variant == null) {
    return null;
  }
  final Dimension dimension = variant.unit.dimension;
  if (dimension != Dimension.mass && dimension != Dimension.volume) {
    return null;
  }
  return variant.unit;
}

/// The token immediately after [from], which is where a unit is printed.
String _wordAfter(String text, int from) {
  if (from >= text.length) {
    return '';
  }
  final String rest = text.substring(from).trim();
  if (rest.isEmpty) {
    return '';
  }
  final int space = rest.indexOf(' ');
  final String token = space < 0 ? rest : rest.substring(0, space);
  // Trailing punctuation is printing, not meaning: "30 g." is "30 g".
  return token.replaceAll(RegExp(r'[^A-Za-z%]'), '');
}

/// [number] expressed in [unit]'s increments, or null on overflow.
int? _scaleToUnit(_Number number, Unit unit) {
  final int? whole = checkedMultiply(number.whole, unit.scale);
  if (whole == null) {
    return null;
  }
  if (number.fractionDigits == 0) {
    return isSafeBaseUnitMagnitude(whole) ? whole : null;
  }
  // The fraction is scaled by the unit and truncated at the unit's precision,
  // which is the finest the model tracks. A label printing more decimals than
  // the unit carries is printing precision the model does not claim.
  int fraction = number.fraction;
  int digits = number.fractionDigits;
  int scaled = unit.scale;
  while (digits > 0 && scaled % 10 == 0) {
    scaled ~/= 10;
    digits--;
  }
  while (digits > 0) {
    fraction ~/= 10;
    digits--;
  }
  final int? total = checkedAdd(whole, fraction * scaled);
  return total != null && isSafeBaseUnitMagnitude(total) ? total : null;
}

/// A decimal literal found in a line.
final class _Number {
  const _Number({
    required this.whole,
    required this.fraction,
    required this.fractionDigits,
    required this.end,
  });

  final int whole;
  final int fraction;
  final int fractionDigits;
  final int end;
}

/// Every decimal literal in [text], in order.
///
/// Deliberately simple: digits, optionally a single decimal point, digits. No
/// thousands separators, no exponents, no fractions like `1/2`. A label using
/// any of those is one this stage declines rather than guesses at.
List<_Number> _numbersIn(String text) {
  final List<_Number> found = <_Number>[];
  int i = 0;
  while (i < text.length) {
    if (!_isDigit(text.codeUnitAt(i))) {
      i++;
      continue;
    }
    final int start = i;
    while (i < text.length && _isDigit(text.codeUnitAt(i))) {
      i++;
    }
    final String wholeText = text.substring(start, i);
    int fraction = 0;
    int digits = 0;
    if (i + 1 < text.length &&
        (text[i] == '.' || text[i] == ',') &&
        _isDigit(text.codeUnitAt(i + 1))) {
      final int dot = i;
      i++;
      final int fractionStart = i;
      while (i < text.length && _isDigit(text.codeUnitAt(i))) {
        i++;
      }
      // A comma between digit groups is a thousands separator on Indian packs
      // as often as a decimal mark. Refusing to read either is safer than
      // choosing, so a comma-separated literal is left as two numbers, which
      // the one-number rule then treats as ambiguous.
      if (text[dot] == ',') {
        found.add(_Number(
          whole: int.parse(wholeText),
          fraction: 0,
          fractionDigits: 0,
          end: dot,
        ));
        i = fractionStart;
        continue;
      }
      fraction = int.parse(text.substring(fractionStart, i));
      digits = i - fractionStart;
    }
    final int? whole = int.tryParse(wholeText);
    if (whole == null) {
      // Longer than an int can hold. Refused here rather than wrapped.
      return <_Number>[
        const _Number(whole: -1, fraction: 0, fractionDigits: 0, end: 0),
        const _Number(whole: -1, fraction: 0, fractionDigits: 0, end: 0),
      ];
    }
    found.add(_Number(
      whole: whole,
      fraction: fraction,
      fractionDigits: digits,
      end: i,
    ));
  }
  return found;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// Rule identifiers this stage attributes its work to.
final class _S5bRules {
  const _S5bRules._();

  static final RuleId marker = RuleId('rule.serving.marker');
}
