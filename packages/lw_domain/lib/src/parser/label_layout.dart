import 'package:lw_domain/src/parser/normalised_text.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';

/// The geometric thresholds S2 uses to cluster elements.
///
/// Named constants rather than literals buried in comparisons, so the tuning
/// surface is visible. No frozen document specifies these values; they are
/// **provisional** and should be revisited once the golden corpus exists, in
/// the same spirit as the tolerance bands in `rulepack/rules/confidence.json`.
///
/// They are deliberately **not** rule pack data: they are geometric and
/// category-agnostic, which is what lets S2 stay reusable for cosmetics and
/// medicine labels in Stage 3 (`ARCHITECTURE.md` §6.3).
final class LayoutThresholds {
  const LayoutThresholds._();

  /// Two elements share a line when their vertical spans overlap by at least
  /// this percentage of the shorter span.
  ///
  /// Real OCR boxes rarely align exactly, so an exact-match rule would split
  /// every line. Fifty percent tolerates ordinary jitter while still splitting
  /// genuinely separate rows.
  static const int sameLineOverlapRatioPercent = 50;

  /// Horizontal gap, in normalised units, that separates one column from the
  /// next.
  ///
  /// Four percent of the label width. Below this, two elements are words in
  /// the same column; above it, they belong to different columns.
  static const int columnGapNormalised = 400;
}

/// A row of elements sharing a vertical band.
///
/// Produced from geometry alone. S2 knows nothing about nutrients
/// (`ARCHITECTURE.md` §6.3), so a line of cosmetic ingredients and a line of
/// nutrition values are indistinguishable here — which is the point.
final class LayoutLine {
  /// Records a line and the elements that formed it.
  LayoutLine({
    required List<NormalisedElement> elements,
    required this.region,
  }) : elements = List<NormalisedElement>.unmodifiable(elements);

  /// The elements on this line, ordered left to right by geometry.
  ///
  /// Order comes from position, not from the engine's sequence — an engine
  /// that returns elements out of reading order must not corrupt the line.
  final List<NormalisedElement> elements;

  /// The bounding box of every element on the line.
  final RegionRef region;

  /// Source indices of the elements that formed this line, in line order.
  ///
  /// Lets a later stage or a diagnostic trace a line back to the recognition
  /// elements without holding references to them.
  List<int> get sourceIndices => List<int>.unmodifiable(
        elements.map((NormalisedElement e) => e.sourceIndex),
      );

  @override
  String toString() => 'LayoutLine(${elements.length} elements, $region)';
}

/// A vertical band of the label occupied by one column of content.
///
/// A two-column band is what a per-100 g / per-serve panel looks like
/// geometrically. Assigning meaning to a column is S5's job, not S2's.
final class LayoutColumn {
  /// Records a detected column.
  LayoutColumn({
    required this.index,
    required this.left,
    required this.right,
    required List<int> sourceIndices,
  }) : sourceIndices = List<int>.unmodifiable(sourceIndices);

  /// Position of this column from the left, starting at zero.
  final int index;

  /// Left edge of the band, in normalised units.
  final int left;

  /// Right edge of the band, in normalised units.
  final int right;

  /// Source indices of every element falling in this band, ascending.
  final List<int> sourceIndices;

  @override
  String toString() => 'LayoutColumn($index, $left..$right)';
}

/// The output of S2 — the physical structure of the label.
///
/// Purely geometric. Contains no nutrition vocabulary and makes no semantic
/// claim, which is what makes it reusable beyond food labels and testable
/// without any nutrition knowledge.
final class LabelLayout {
  /// Records the reconstructed layout.
  LabelLayout({
    required List<LayoutLine> lines,
    required List<LayoutColumn> columns,
  })  : lines = List<LayoutLine>.unmodifiable(lines),
        columns = List<LayoutColumn>.unmodifiable(columns);

  /// Lines, ordered top to bottom.
  final List<LayoutLine> lines;

  /// Columns, ordered left to right.
  final List<LayoutColumn> columns;

  /// The stage that produced this, recorded for diagnostics.
  PipelineStage get producedByStage => PipelineStage.layoutReconstruction;

  @override
  String toString() =>
      'LabelLayout(${lines.length} lines, ${columns.length} columns)';
}
