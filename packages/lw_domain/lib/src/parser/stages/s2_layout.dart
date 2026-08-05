import 'package:lw_domain/src/parser/label_layout.dart';
import 'package:lw_domain/src/parser/normalised_text.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/region_ref.dart';

/// **S2 — Layout reconstruction.** Physical structure from geometry alone.
///
/// Deliberately semantic-free (`ARCHITECTURE.md` §6.3). S2 never consults
/// nutrient names, which means it can be tested with no nutrition knowledge
/// and reused unchanged for cosmetics and medicine labels in Stage 3. The cost
/// is that S2 sometimes produces a structure S3 must correct — an acceptable
/// price for a reusable half of the pipeline.
///
/// Determinism (FR-PAR-02) is structural here: every collection is sorted by
/// an explicit geometric key before being emitted, so no result depends on the
/// order the engine happened to return elements in.
StageResult<LabelLayout> reconstructLayout(NormalisedText normalised) {
  final List<NormalisedElement> elements = normalised.elements;
  if (elements.isEmpty) {
    return const StageFailure<LabelLayout>(
      ParseFailure(
        kind: ParseFailureKind.layoutIndeterminate,
        stage: PipelineStage.layoutReconstruction,
      ),
    );
  }

  // A zero-area box carries no positional information. If every element is
  // degenerate, lines cannot be formed and guessing would be worse than
  // declining (P1).
  final List<NormalisedElement> positioned = elements
      .where((NormalisedElement e) => e.region.height > 0)
      .toList(growable: false);
  if (positioned.isEmpty) {
    return const StageFailure<LabelLayout>(
      ParseFailure(
        kind: ParseFailureKind.layoutIndeterminate,
        stage: PipelineStage.layoutReconstruction,
      ),
    );
  }

  return StageSuccess<LabelLayout>(LabelLayout(
    lines: _clusterLines(positioned),
    columns: _detectColumns(positioned),
  ));
}

/// Groups elements into lines by vertical overlap.
///
/// Sorted by top edge first, so the grouping is a single forward pass and the
/// result cannot depend on input order.
List<LayoutLine> _clusterLines(List<NormalisedElement> elements) {
  final List<NormalisedElement> byTop = <NormalisedElement>[...elements]..sort(
      (NormalisedElement a, NormalisedElement b) {
        final int byTopEdge = a.region.top.compareTo(b.region.top);
        return byTopEdge != 0
            ? byTopEdge
            : a.region.left.compareTo(b.region.left);
      },
    );

  final List<List<NormalisedElement>> groups = <List<NormalisedElement>>[];
  for (final NormalisedElement element in byTop) {
    final List<NormalisedElement>? open = groups.isEmpty ? null : groups.last;
    if (open != null && _sharesLine(open, element)) {
      open.add(element);
    } else {
      groups.add(<NormalisedElement>[element]);
    }
  }

  return <LayoutLine>[
    for (final List<NormalisedElement> group in groups) _buildLine(group),
  ];
}

/// Whether [candidate] belongs on the same line as an open group.
///
/// Compared against the group's last member, whose vertical span is the most
/// recent evidence of where the line sits.
bool _sharesLine(List<NormalisedElement> group, NormalisedElement candidate) {
  final RegionRef last = group.last.region;
  final RegionRef next = candidate.region;
  final int overlapTop = last.top > next.top ? last.top : next.top;
  final int overlapBottom =
      last.bottom < next.bottom ? last.bottom : next.bottom;
  final int overlap = overlapBottom - overlapTop;
  if (overlap <= 0) {
    return false;
  }
  final int shorter = last.height < next.height ? last.height : next.height;
  if (shorter <= 0) {
    return false;
  }
  return overlap * 100 >=
      shorter * LayoutThresholds.sameLineOverlapRatioPercent;
}

LayoutLine _buildLine(List<NormalisedElement> group) {
  final List<NormalisedElement> ordered = <NormalisedElement>[...group]..sort(
      (NormalisedElement a, NormalisedElement b) {
        final int byLeft = a.region.left.compareTo(b.region.left);
        return byLeft != 0 ? byLeft : a.sourceIndex.compareTo(b.sourceIndex);
      },
    );
  int left = ordered.first.region.left;
  int top = ordered.first.region.top;
  int right = ordered.first.region.right;
  int bottom = ordered.first.region.bottom;
  for (final NormalisedElement e in ordered) {
    if (e.region.left < left) {
      left = e.region.left;
    }
    if (e.region.top < top) {
      top = e.region.top;
    }
    if (e.region.right > right) {
      right = e.region.right;
    }
    if (e.region.bottom > bottom) {
      bottom = e.region.bottom;
    }
  }
  return LayoutLine(
    elements: ordered,
    region: RegionRef(left: left, top: top, right: right, bottom: bottom),
  );
}

/// Groups elements into vertical bands separated by a horizontal gap.
///
/// A two-band result is what a per-100 g / per-serve panel looks like
/// geometrically. What the bands *mean* is S5's business.
List<LayoutColumn> _detectColumns(List<NormalisedElement> elements) {
  final List<NormalisedElement> byLeft = <NormalisedElement>[...elements]..sort(
      (NormalisedElement a, NormalisedElement b) {
        final int byLeftEdge = a.region.left.compareTo(b.region.left);
        return byLeftEdge != 0
            ? byLeftEdge
            : a.sourceIndex.compareTo(b.sourceIndex);
      },
    );

  final List<List<NormalisedElement>> bands = <List<NormalisedElement>>[];
  int bandRight = byLeft.first.region.right;
  bands.add(<NormalisedElement>[byLeft.first]);
  for (int i = 1; i < byLeft.length; i++) {
    final NormalisedElement e = byLeft[i];
    final int gap = e.region.left - bandRight;
    if (gap > LayoutThresholds.columnGapNormalised) {
      bands.add(<NormalisedElement>[e]);
      bandRight = e.region.right;
    } else {
      bands.last.add(e);
      if (e.region.right > bandRight) {
        bandRight = e.region.right;
      }
    }
  }

  return <LayoutColumn>[
    for (int i = 0; i < bands.length; i++) _buildColumn(i, bands[i]),
  ];
}

LayoutColumn _buildColumn(int index, List<NormalisedElement> band) {
  int left = band.first.region.left;
  int right = band.first.region.right;
  for (final NormalisedElement e in band) {
    if (e.region.left < left) {
      left = e.region.left;
    }
    if (e.region.right > right) {
      right = e.region.right;
    }
  }
  final List<int> indices = <int>[
    for (final NormalisedElement e in band) e.sourceIndex,
  ]..sort();
  return LayoutColumn(
    index: index,
    left: left,
    right: right,
    sourceIndices: indices,
  );
}
