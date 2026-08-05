import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  NormalisedElement el(int index, String text, RegionRef region) =>
      NormalisedElement(
        sourceIndex: index,
        originalText: text,
        text: text,
        region: region,
      );

  /// One line holding one element, at a vertical band derived from [index].
  LayoutLine line(int index, String text) {
    final RegionRef r = box(100, index * 100, 900, index * 100 + 60);
    return LayoutLine(
      elements: <NormalisedElement>[el(index, text, r)],
      region: r,
    );
  }

  ClassifiedRegion regionOf(RegionKind kind, List<LayoutLine> lines) =>
      ClassifiedRegion(
        kind: kind,
        lines: lines,
        region: lines.first.region,
        matchStrength: ParseStrength.exact,
      );

  group('RegionKind — the three kinds ARCHITECTURE 6.1 names', () {
    test('FR-PAR-17 exactly three kinds exist, named as specified', () {
      // S3's output vocabulary is closed. A fourth kind would be a silent
      // widening of what later stages must handle.
      expect(RegionKind.values, hasLength(3));
      expect(
        RegionKind.values.map((RegionKind k) => k.name),
        <String>['nutritionPanel', 'ingredientList', 'other'],
      );
    });

    test('FR-ERR-03 other is a classification, not a discard', () {
      // Text that could not be classified still existed on the label. Losing
      // it would make "not declared" indistinguishable from "not read".
      expect(RegionKind.other.isClassified, isFalse);
      expect(RegionKind.nutritionPanel.isClassified, isTrue);
      expect(RegionKind.ingredientList.isClassified, isTrue);
    });
  });

  group('RegionMarkerTable — structural cues, injectable (Q13, ADR-0013)', () {
    test('Q13 the defaults carry markers for both classifiable kinds', () {
      final RegionMarkerTable t = RegionMarkerTable.foodLabelDefaults;
      bool has(RegionKind k) => t.markers.any((RegionMarker m) => m.kind == k);
      expect(has(RegionKind.nutritionPanel), isTrue);
      expect(has(RegionKind.ingredientList), isTrue);
    });

    test('Q13 no default marker classifies a region as other', () {
      // `other` is the absence of a match. A marker for it would make the
      // fallback reachable two ways and the outcome order-dependent.
      expect(
        RegionMarkerTable.foodLabelDefaults.markers
            .every((RegionMarker m) => m.kind != RegionKind.other),
        isTrue,
      );
    });

    test('R-M5-4 the default table stays small', () {
      // A marker set that grows per failing label becomes the synonym table
      // Q13 excluded, in code, where nobody can contribute to it.
      expect(RegionMarkerTable.foodLabelDefaults.markers.length,
          lessThanOrEqualTo(12));
    });

    test('FR-PAR-02 marker text is stored lower-cased for stable matching', () {
      // Matching folds case once, at construction, so the same table cannot
      // match differently depending on how a marker was typed.
      expect(
        RegionMarkerTable.foodLabelDefaults.markers
            .every((RegionMarker m) => m.text == m.text.toLowerCase()),
        isTrue,
      );
    });

    test('FR-PAR-17 a marker with empty text is rejected', () {
      expect(
        () => RegionMarkerTable(<RegionMarker>[
          RegionMarker(
            text: '',
            kind: RegionKind.nutritionPanel,
            strength: ParseStrength.exact,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('FR-ERR-03 a marker classifying as other is rejected', () {
      expect(
        () => RegionMarkerTable(<RegionMarker>[
          RegionMarker(
            text: 'anything',
            kind: RegionKind.other,
            strength: ParseStrength.exact,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('FR-PAR-13 matching is case-insensitive and reports its strength', () {
      final RegionMarkerTable t = RegionMarkerTable(<RegionMarker>[
        RegionMarker(
          text: 'ingredients',
          kind: RegionKind.ingredientList,
          strength: ParseStrength.exact,
        ),
      ]);
      final RegionMarker? m = t.strongestMatch('INGREDIENTS: Wheat flour');
      expect(m, isNotNull);
      expect(m!.kind, RegionKind.ingredientList);
      expect(m.strength, ParseStrength.exact);
    });

    test('FR-PAR-13 the strongest match wins when several apply', () {
      // Strength is signal S2 and feeds confidence. Returning an arbitrary
      // match would make the recorded strength depend on table order.
      final RegionMarkerTable t = RegionMarkerTable(<RegionMarker>[
        RegionMarker(
          text: 'nutrition',
          kind: RegionKind.nutritionPanel,
          strength: ParseStrength.heuristic,
        ),
        RegionMarker(
          text: 'nutritional information',
          kind: RegionKind.nutritionPanel,
          strength: ParseStrength.exact,
        ),
      ]);
      expect(t.strongestMatch('Nutritional Information')!.strength,
          ParseStrength.exact);
    });

    test('FR-PAR-05 unmatched text yields no match, never a guess', () {
      expect(RegionMarkerTable.foodLabelDefaults.strongestMatch('Wheat flour'),
          isNull);
      expect(RegionMarkerTable.foodLabelDefaults.strongestMatch(''), isNull);
    });

    test('ADR-0013 an empty table matches nothing and does not throw', () {
      final RegionMarkerTable t = RegionMarkerTable(const <RegionMarker>[]);
      expect(t.strongestMatch('Nutritional Information'), isNull);
      expect(t.markers, isEmpty);
    });

    test('Q13 a caller-supplied table classifies non-food vocabulary', () {
      // The reuse boundary in one test. S3 carries no food knowledge of its
      // own; swapping the table is what makes it a cosmetics parser.
      final RegionMarkerTable cosmetics = RegionMarkerTable(<RegionMarker>[
        RegionMarker(
          text: 'inci',
          kind: RegionKind.ingredientList,
          strength: ParseStrength.exact,
        ),
      ]);
      expect(cosmetics.strongestMatch('INCI: Aqua, Glycerin')!.kind,
          RegionKind.ingredientList);
      expect(cosmetics.strongestMatch('Nutritional Information'), isNull);
    });

    test('FR-KB-01 the marker list is unmodifiable once built', () {
      expect(
        () => RegionMarkerTable.foodLabelDefaults.markers.add(
          RegionMarker(
            text: 'x',
            kind: RegionKind.nutritionPanel,
            strength: ParseStrength.exact,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('ClassifiedRegion — the provenance chain is unbroken (M3/M4)', () {
    test('FR-PAR-13 records kind, geometry and the strength that matched', () {
      final ClassifiedRegion r =
          regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(0, 'a')]);
      expect(r.kind, RegionKind.nutritionPanel);
      expect(r.region, box(100, 0, 900, 60));
      expect(r.matchStrength, ParseStrength.exact);
    });

    test('FR-PAR-13 source indices are derived, ascending, never stored', () {
      // Derived rather than duplicated: a stored copy can drift from the
      // lines it claims to describe, and nothing would detect that.
      final ClassifiedRegion r = regionOf(
        RegionKind.ingredientList,
        <LayoutLine>[line(2, 'c'), line(0, 'a'), line(1, 'b')],
      );
      expect(r.sourceIndices, <int>[0, 1, 2]);
    });

    test('FR-PAR-13 the rule that classified it is recorded when known', () {
      final ClassifiedRegion r = ClassifiedRegion(
        kind: RegionKind.nutritionPanel,
        lines: <LayoutLine>[line(0, 'a')],
        region: box(0, 0, 10, 10),
        matchStrength: ParseStrength.normalised,
        matchedBy: RuleId('rule.region.marker'),
      );
      expect(r.matchedBy, RuleId('rule.region.marker'));
    });

    test('FR-PAR-17 a region with no lines is rejected', () {
      // A region describing no text carries no information and would break
      // the source-index chain silently.
      expect(
        () => ClassifiedRegion(
          kind: RegionKind.other,
          lines: const <LayoutLine>[],
          region: box(0, 0, 10, 10),
          matchStrength: ParseStrength.heuristic,
        ),
        throwsArgumentError,
      );
    });

    test('FR-KB-01 the line list is unmodifiable once built', () {
      final ClassifiedRegion r =
          regionOf(RegionKind.other, <LayoutLine>[line(0, 'a')]);
      expect(() => r.lines.add(line(1, 'b')), throwsUnsupportedError);
    });

    test('P4 compares by value, not identity', () {
      final ClassifiedRegion a =
          regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(0, 'a')]);
      final ClassifiedRegion b =
          regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(0, 'a')]);
      final ClassifiedRegion other =
          regionOf(RegionKind.ingredientList, <LayoutLine>[line(0, 'a')]);
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(other), reason: 'kind is part of the value');
    });

    test('FR-PAR-13 toString names the kind and its extent', () {
      final ClassifiedRegion r = regionOf(
        RegionKind.nutritionPanel,
        <LayoutLine>[line(0, 'a'), line(1, 'b')],
      );
      expect(r.toString(), 'ClassifiedRegion(nutritionPanel, 2 lines, exact)');
    });
  });

  group('ClassifiedRegions — partial results are the normal case', () {
    test('FR-PAR-13 the output records the stage that produced it', () {
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.other, <LayoutLine>[line(0, 'a')]),
        ],
      );
      expect(rs.producedByStage, PipelineStage.regionClassification);
    });

    test('FR-PAR-14 both panels present are individually reachable', () {
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(0, 'n')]),
          regionOf(RegionKind.ingredientList, <LayoutLine>[line(1, 'i')]),
        ],
      );
      expect(rs.nutritionPanel!.kind, RegionKind.nutritionPanel);
      expect(rs.ingredientList!.kind, RegionKind.ingredientList);
      expect(rs.hasNutritionPanel, isTrue);
      expect(rs.hasIngredientList, isTrue);
    });

    test('FR-PAR-14 an ingredients-only label is a complete result', () {
      // A label carrying no nutrition panel is not a failure. FR-PAR-14
      // requires a complete result for the portion supplied.
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.ingredientList, <LayoutLine>[line(0, 'i')]),
        ],
      );
      expect(rs.nutritionPanel, isNull);
      expect(rs.hasNutritionPanel, isFalse);
      expect(rs.ingredientList, isNotNull);
    });

    test('FR-ERR-03 unclassified regions are retained, not dropped', () {
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(0, 'n')]),
          regionOf(RegionKind.other, <LayoutLine>[line(1, 'x')]),
          regionOf(RegionKind.other, <LayoutLine>[line(2, 'y')]),
        ],
      );
      expect(rs.otherRegions, hasLength(2));
      expect(rs.sourceIndices, <int>[0, 1, 2]);
    });

    test('M1 a second nutrition panel is rejected at construction', () {
      // Two panels would make `nutritionPanel` mean "whichever came first",
      // which is a silent choice later stages cannot see or question.
      expect(
        () => ClassifiedRegions(
          regions: <ClassifiedRegion>[
            regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(0, 'a')]),
            regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(1, 'b')]),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('M1 a second ingredient list is rejected at construction', () {
      expect(
        () => ClassifiedRegions(
          regions: <ClassifiedRegion>[
            regionOf(RegionKind.ingredientList, <LayoutLine>[line(0, 'a')]),
            regionOf(RegionKind.ingredientList, <LayoutLine>[line(1, 'b')]),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('FR-PAR-13 source indices span every region, ascending', () {
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.other, <LayoutLine>[line(3, 'd')]),
          regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(1, 'b')]),
        ],
      );
      expect(rs.sourceIndices, <int>[1, 3]);
    });

    test('FR-KB-01 the region list is unmodifiable once built', () {
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.other, <LayoutLine>[line(0, 'a')]),
        ],
      );
      expect(
        () => rs.regions
            .add(regionOf(RegionKind.other, <LayoutLine>[line(1, 'b')])),
        throwsUnsupportedError,
      );
    });

    test('FR-PAR-04 S2 column bands survive the stage for S4', () {
      // S4's contract requires a column association and its only input is
      // this object, so the bands must cross the boundary intact.
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(0, 'n')]),
        ],
        columns: <LayoutColumn>[
          LayoutColumn(
            index: 0,
            left: 100,
            right: 900,
            sourceIndices: const <int>[0],
          ),
          LayoutColumn(
            index: 1,
            left: 3000,
            right: 3400,
            sourceIndices: const <int>[1],
          ),
        ],
      );
      expect(rs.columns, hasLength(2));
      expect(rs.columnIndexOf(0), 0);
      expect(rs.columnIndexOf(1), 1);
    });

    test('FR-PAR-05 an element in no band reports no column, never a guess',
        () {
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.other, <LayoutLine>[line(0, 'a')]),
        ],
      );
      expect(rs.columns, isEmpty);
      expect(rs.columnIndexOf(0), isNull);
    });

    test('FR-PAR-13 toString summarises what was classified', () {
      final ClassifiedRegions rs = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          regionOf(RegionKind.nutritionPanel, <LayoutLine>[line(0, 'n')]),
          regionOf(RegionKind.other, <LayoutLine>[line(1, 'x')]),
        ],
      );
      expect(rs.toString(), 'ClassifiedRegions(2 regions: nutritionPanel)');
    });
  });
}
