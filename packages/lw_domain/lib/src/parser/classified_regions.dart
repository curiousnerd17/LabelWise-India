import 'package:lw_domain/src/parser/label_layout.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';

/// What a region of the label is, structurally.
///
/// The three kinds named in `ARCHITECTURE.md` §6.1, and deliberately no more.
/// S3's output vocabulary is closed: a fourth kind would silently widen what
/// every later stage must handle.
enum RegionKind {
  /// The nutrition panel — the tabular block of declared values.
  nutritionPanel,

  /// The ingredient list — the ordered declaration (FR-PAR-10).
  ingredientList,

  /// Text that exists on the label but matched no marker.
  ///
  /// A classification, not a discard. FR-ERR-03 requires "the label does not
  /// declare this" to stay distinguishable from "we could not read this", and
  /// discarding unmatched text would collapse the two.
  other;

  /// Whether this kind names a region S3 positively identified.
  ///
  /// False only for [other], which is the absence of a match rather than the
  /// presence of one.
  bool get isClassified => this != RegionKind.other;
}

/// One region of the label, with the evidence that classified it.
///
/// Carries the full provenance chain M3 and M4 established: the source indices
/// of every element it covers, the geometry it occupies, and the strength at
/// which it matched. None of the three may be lost between stages.
final class ClassifiedRegion {
  /// Records a classified region.
  ///
  /// Throws [ArgumentError] when [lines] is empty: a region describing no text
  /// carries no information, and admitting one would break the source-index
  /// chain in a way nothing downstream could detect.
  ClassifiedRegion({
    required this.kind,
    required List<LayoutLine> lines,
    required this.region,
    required this.matchStrength,
    this.matchedBy,
  }) : lines = List<LayoutLine>.unmodifiable(lines) {
    if (lines.isEmpty) {
      throw ArgumentError.value(
        lines,
        'lines',
        'A classified region must cover at least one line.',
      );
    }
  }

  /// What this region is.
  final RegionKind kind;

  /// The lines it covers, in the order S2 produced them (top to bottom).
  final List<LayoutLine> lines;

  /// The bounding box of the whole region.
  final RegionRef region;

  /// How firmly the classification held — signal S2, carried into confidence.
  ///
  /// [ParseStrength.heuristic] for a region assigned by position alone,
  /// stronger when a marker matched.
  final ParseStrength matchStrength;

  /// The rule that classified it, when one did. Null for the fallback.
  final RuleId? matchedBy;

  /// Source indices of every element in the region, ascending.
  ///
  /// Derived rather than stored. A stored copy can drift from the lines it
  /// claims to describe, and nothing would detect that drift.
  List<int> get sourceIndices {
    final List<int> all = <int>[
      for (final LayoutLine l in lines) ...l.sourceIndices,
    ]..sort();
    return List<int>.unmodifiable(all);
  }

  /// Equality is over the classification and the elements covered, not over
  /// the line objects.
  ///
  /// `LayoutLine` is an S2 intermediate without value equality (AR5 keeps
  /// intermediates refactorable), so comparing line objects would compare
  /// identity and make two identically classified regions unequal. Source
  /// indices identify the covered elements exactly, which is the property
  /// callers actually mean. The residual gap is narrow and worth naming: two
  /// regions covering the same elements grouped into different lines would
  /// compare equal here.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassifiedRegion &&
          kind == other.kind &&
          region == other.region &&
          matchStrength == other.matchStrength &&
          matchedBy == other.matchedBy &&
          _sameIndices(sourceIndices, other.sourceIndices);

  @override
  int get hashCode => Object.hash(
        kind,
        region,
        matchStrength,
        matchedBy,
        Object.hashAll(sourceIndices),
      );

  @override
  String toString() => 'ClassifiedRegion(${kind.name}, ${lines.length} lines, '
      '${matchStrength.name})';
}

bool _sameIndices(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// The output of S3 — what each part of the label is.
///
/// A partial result is the normal case, not an error. FR-PAR-14 requires a
/// complete result for the portion supplied, so a label carrying only an
/// ingredient list produces a `ClassifiedRegions` with [nutritionPanel] null
/// rather than a failure.
final class ClassifiedRegions {
  /// Records the classification.
  ///
  /// Throws [ArgumentError] when more than one region carries the same
  /// classified kind. Two nutrition panels would make [nutritionPanel] mean
  /// "whichever came first" — a silent choice later stages could neither see
  /// nor question. [RegionKind.other] may repeat, because it is the absence of
  /// a classification rather than one.
  ClassifiedRegions({
    required List<ClassifiedRegion> regions,
    List<LayoutColumn> columns = const <LayoutColumn>[],
  })  : regions = List<ClassifiedRegion>.unmodifiable(regions),
        columns = List<LayoutColumn>.unmodifiable(columns) {
    for (final RegionKind kind in RegionKind.values) {
      if (!kind.isClassified) {
        continue;
      }
      final int count =
          regions.where((ClassifiedRegion r) => r.kind == kind).length;
      if (count > 1) {
        throw ArgumentError.value(
          regions,
          'regions',
          'Found $count regions of kind ${kind.name}; at most one is allowed.',
        );
      }
    }
  }

  /// Every region found, in the order S3 produced them.
  final List<ClassifiedRegion> regions;

  /// The columns S2 detected, carried through unchanged.
  ///
  /// S3 makes no use of them. They are here because `ARCHITECTURE.md` §6.1
  /// gives S4 the input type `ClassifiedRegions` and requires its candidates
  /// to carry a column association — so the column bands must survive this
  /// stage. Passing the original layout to S4 alongside this object would
  /// break the stage contract; carrying the bands honours it.
  final List<LayoutColumn> columns;

  /// The index of the column containing [sourceIndex], or null when no band
  /// claims it.
  ///
  /// S2 assigns every element to exactly one band, so a null here means the
  /// element was never laid out — which S4 must treat as an undetermined
  /// basis rather than guessing a column (FR-PAR-05).
  int? columnIndexOf(int sourceIndex) {
    for (final LayoutColumn c in columns) {
      if (c.sourceIndices.contains(sourceIndex)) {
        return c.index;
      }
    }
    return null;
  }

  /// The stage that produced this, recorded for diagnostics.
  PipelineStage get producedByStage => PipelineStage.regionClassification;

  /// The nutrition panel, or null when the label carries none (FR-PAR-14).
  ClassifiedRegion? get nutritionPanel => _ofKind(RegionKind.nutritionPanel);

  /// The ingredient list, or null when the label carries none (FR-PAR-14).
  ClassifiedRegion? get ingredientList => _ofKind(RegionKind.ingredientList);

  /// Whether a nutrition panel was identified.
  bool get hasNutritionPanel => nutritionPanel != null;

  /// Whether an ingredient list was identified.
  bool get hasIngredientList => ingredientList != null;

  /// Regions that matched no marker, retained rather than discarded.
  ///
  /// FR-ERR-03 depends on knowing that text existed but went unclassified.
  List<ClassifiedRegion> get otherRegions =>
      List<ClassifiedRegion>.unmodifiable(
        regions.where((ClassifiedRegion r) => r.kind == RegionKind.other),
      );

  /// Source indices covered by every region, ascending.
  List<int> get sourceIndices {
    final List<int> all = <int>[
      for (final ClassifiedRegion r in regions) ...r.sourceIndices,
    ]..sort();
    return List<int>.unmodifiable(all);
  }

  ClassifiedRegion? _ofKind(RegionKind kind) {
    for (final ClassifiedRegion r in regions) {
      if (r.kind == kind) {
        return r;
      }
    }
    return null;
  }

  @override
  String toString() {
    final List<String> found = <String>[
      for (final RegionKind k in RegionKind.values)
        if (k.isClassified && _ofKind(k) != null) k.name,
    ];
    final String summary = found.isEmpty ? 'none' : found.join(', ');
    return 'ClassifiedRegions(${regions.length} regions: $summary)';
  }
}
