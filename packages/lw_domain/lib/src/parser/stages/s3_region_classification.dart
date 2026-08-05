import 'package:lw_domain/src/parser/classified_regions.dart';
import 'package:lw_domain/src/parser/label_layout.dart';
import 'package:lw_domain/src/parser/normalised_text.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/region_markers.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';

/// Rule identifiers S3 attributes its classifications to.
final class _S3Rules {
  const _S3Rules._();

  /// A marker in the supplied table matched a line.
  static final RuleId marker = RuleId('rule.region.marker');

  /// A second region of an already-classified kind, demoted to `other`.
  static final RuleId duplicate = RuleId('rule.region.duplicate');
}

/// **S3 — Region classification.** What each part of the label is.
///
/// Consumes S2's purely geometric [LabelLayout] and identifies the nutrition
/// panel, the ingredient list, and everything else.
///
/// **Structural cues only** (Q13, `DATA_MODEL.md` §7.9). S3 never consults the
/// rule pack and never reads the nutrient synonym table. Its entire vocabulary
/// is the injected [RegionMarkerTable], which is what keeps S1–S4 reusable for
/// cosmetics and medicine labels (`ARCHITECTURE.md` §11).
///
/// The algorithm is **marker plus contiguity**: a line carrying a marker opens
/// a region of that kind, and the region runs until a marker of a *different*
/// kind appears. Density and geometry refinements are deliberately deferred
/// until the golden corpus exists — tuning a heuristic against invented
/// fixtures tunes it against the author's assumptions, not against labels.
///
/// Pure and total: no I/O, no clock, no randomness (FR-PAR-01), and every
/// input yields a `StageResult` rather than an exception (FR-PAR-17).
///
/// A **partial result is success**, not failure. FR-PAR-14 requires a complete
/// result for the portion supplied, so a label carrying only an ingredient
/// list classifies successfully with no nutrition panel. Failure is reserved
/// for a layout with nothing in it, or one in which *neither* region could be
/// identified.
///
/// [markers] defaults to `RegionMarkerTable.foodLabelDefaults` when omitted.
/// It is a nullable parameter rather than a defaulted one only because Dart
/// requires default values to be compile-time constants, and a marker is
/// validated at construction.
StageResult<ClassifiedRegions> classifyRegions(
  LabelLayout layout, {
  RegionMarkerTable? markers,
}) {
  if (layout.lines.isEmpty) {
    return const StageFailure<ClassifiedRegions>(
      ParseFailure(
        kind: ParseFailureKind.layoutIndeterminate,
        stage: PipelineStage.regionClassification,
      ),
    );
  }

  final RegionMarkerTable table =
      markers ?? RegionMarkerTable.foodLabelDefaults;
  final List<_Run> runs = _splitIntoRuns(layout.lines, table);
  final List<ClassifiedRegion> regions = _demoteDuplicates(runs);

  // FR-PAR-17: a label in which nothing could be identified is a structured
  // failure, not an empty success. S4 handed a guessed region would produce
  // confidently wrong candidates, which is the outcome P1 forbids above all.
  final bool anyClassified =
      regions.any((ClassifiedRegion r) => r.kind.isClassified);
  if (!anyClassified) {
    return const StageFailure<ClassifiedRegions>(
      ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        stage: PipelineStage.regionClassification,
      ),
    );
  }

  return StageSuccess<ClassifiedRegions>(
    ClassifiedRegions(regions: regions, columns: layout.columns),
  );
}

/// One contiguous block of lines sharing a classification.
final class _Run {
  _Run(this.kind, this.strength, this.matchedBy);

  /// Null when no marker named the block; resolved to `other` on output.
  final RegionKind? kind;

  /// The strongest marker strength seen in the run.
  ParseStrength strength;

  /// The rule that named it, when one did.
  RuleId? matchedBy;
  final List<LayoutLine> lines = <LayoutLine>[];
}

/// Walks the lines top to bottom, opening a run at each marker of a new kind.
///
/// A marker matching the kind already open **continues** that run rather than
/// splitting it. `Per 100 g` is a column header inside the panel, not a second
/// panel, and splitting on it would carve the header out of the block it
/// labels. The strongest marker seen in a run sets the run's strength, so a
/// block opened by a weak positional cue and later confirmed by the real
/// heading records the better evidence.
List<_Run> _splitIntoRuns(List<LayoutLine> lines, RegionMarkerTable table) {
  final List<_Run> runs = <_Run>[];
  _Run current = _Run(null, ParseStrength.heuristic, null);

  for (final LayoutLine line in lines) {
    final RegionMarker? hit = table.strongestMatch(_lineText(line));

    if (hit != null && hit.kind != current.kind) {
      if (current.lines.isNotEmpty) {
        runs.add(current);
      }
      current = _Run(hit.kind, hit.strength, _S3Rules.marker);
    } else if (hit != null && _isStronger(hit.strength, current.strength)) {
      current.strength = hit.strength;
      current.matchedBy = _S3Rules.marker;
    }

    current.lines.add(line);
  }

  if (current.lines.isNotEmpty) {
    runs.add(current);
  }
  return runs;
}

/// Keeps the first run of each classified kind and demotes any later one.
///
/// A second nutrition block is genuinely ambiguous. Keeping the first is
/// deterministic; demoting rather than discarding the second keeps the text
/// reachable, which FR-ERR-03 requires — unread text and undeclared text must
/// stay distinguishable.
List<ClassifiedRegion> _demoteDuplicates(List<_Run> runs) {
  final Set<RegionKind> seen = <RegionKind>{};
  final List<ClassifiedRegion> out = <ClassifiedRegion>[];

  for (final _Run run in runs) {
    final RegionKind kind = run.kind ?? RegionKind.other;
    final bool isDuplicate = kind.isClassified && seen.contains(kind);
    if (kind.isClassified && !isDuplicate) {
      seen.add(kind);
    }
    out.add(
      ClassifiedRegion(
        kind: isDuplicate ? RegionKind.other : kind,
        lines: run.lines,
        region: _boundsOf(run.lines),
        matchStrength: isDuplicate ? ParseStrength.heuristic : run.strength,
        matchedBy: isDuplicate ? _S3Rules.duplicate : run.matchedBy,
      ),
    );
  }
  return out;
}

String _lineText(LayoutLine line) =>
    line.elements.map((NormalisedElement e) => e.text).join(' ');

bool _isStronger(ParseStrength candidate, ParseStrength current) =>
    _rank(candidate) < _rank(current);

/// Strongest first. An exhaustive switch, so a fourth parse strength is a
/// compile error here rather than a silent reordering.
int _rank(ParseStrength strength) => switch (strength) {
      ParseStrength.exact => 0,
      ParseStrength.normalised => 1,
      ParseStrength.heuristic => 2,
    };

RegionRef _boundsOf(List<LayoutLine> lines) {
  int left = lines.first.region.left;
  int top = lines.first.region.top;
  int right = lines.first.region.right;
  int bottom = lines.first.region.bottom;
  for (final LayoutLine l in lines) {
    if (l.region.left < left) {
      left = l.region.left;
    }
    if (l.region.top < top) {
      top = l.region.top;
    }
    if (l.region.right > right) {
      right = l.region.right;
    }
    if (l.region.bottom > bottom) {
      bottom = l.region.bottom;
    }
  }
  return RegionRef(left: left, top: top, right: right, bottom: bottom);
}
