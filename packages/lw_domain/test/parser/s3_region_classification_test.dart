import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  /// Builds S2 output directly, one element per line, so S3 is tested in
  /// isolation (ARCHITECTURE 6.2: each stage independently testable).
  LabelLayout layoutOf(List<String> texts) {
    final List<LayoutLine> lines = <LayoutLine>[];
    for (int i = 0; i < texts.length; i++) {
      final RegionRef r = box(100, i * 100, 900, i * 100 + 60);
      lines.add(LayoutLine(
        elements: <NormalisedElement>[
          NormalisedElement(
            sourceIndex: i,
            originalText: texts[i],
            text: texts[i],
            region: r,
          ),
        ],
        region: r,
      ));
    }
    return LabelLayout(
      lines: lines,
      columns: <LayoutColumn>[
        LayoutColumn(
          index: 0,
          left: 100,
          right: 900,
          sourceIndices: <int>[for (int i = 0; i < texts.length; i++) i],
        ),
      ],
    );
  }

  ClassifiedRegions run(LabelLayout l, {RegionMarkerTable? markers}) {
    final StageResult<ClassifiedRegions> out = markers == null
        ? classifyRegions(l)
        : classifyRegions(l, markers: markers);
    expect(out.isSuccess, isTrue, reason: 'expected S3 success');
    return out.valueOrNull!;
  }

  group('S3 — failure paths are values, not exceptions (FR-PAR-17)', () {
    test('FR-PAR-17 an empty layout yields layoutIndeterminate', () {
      final StageResult<ClassifiedRegions> out = classifyRegions(
        LabelLayout(
          lines: const <LayoutLine>[],
          columns: const <LayoutColumn>[],
        ),
      );
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.layoutIndeterminate);
      expect(out.failureOrNull!.stage, PipelineStage.regionClassification);
    });

    test('FR-PAR-17 a label matching no marker yields regionNotFound', () {
      // Honest refusal beats guessing which block is the panel. S4 given a
      // guessed region would produce confidently wrong candidates.
      final StageResult<ClassifiedRegions> out =
          classifyRegions(layoutOf(<String>['Wheat flour', 'Palm oil']));
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
      expect(out.failureOrNull!.stage, PipelineStage.regionClassification);
    });

    test('Q13 an empty marker table classifies nothing, without throwing', () {
      final StageResult<ClassifiedRegions> out = classifyRegions(
        layoutOf(<String>['Nutritional Information', 'Energy 400 kcal']),
        markers: RegionMarkerTable(const <RegionMarker>[]),
      );
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
    });
  });

  group('S3 — marker-driven classification (Q13, ADR-0013)', () {
    test('FR-PAR-03 a heading opens a nutrition panel', () {
      final ClassifiedRegions r = run(layoutOf(<String>[
        'Nutritional Information',
        'Energy 400 kcal',
        'Protein 8 g',
      ]));
      expect(r.hasNutritionPanel, isTrue);
      expect(r.nutritionPanel!.sourceIndices, <int>[0, 1, 2]);
    });

    test('FR-PAR-03 an ingredient heading opens an ingredient list', () {
      final ClassifiedRegions r = run(layoutOf(<String>[
        'INGREDIENTS: Wheat flour, Sugar',
        'Palm oil, Salt',
      ]));
      expect(r.hasIngredientList, isTrue);
      expect(r.ingredientList!.sourceIndices, <int>[0, 1]);
    });

    test('FR-PAR-03 a region ends where a different kind begins', () {
      final ClassifiedRegions r = run(layoutOf(<String>[
        'Nutritional Information',
        'Energy 400 kcal',
        'Ingredients: Wheat flour',
        'Sugar, Salt',
      ]));
      expect(r.nutritionPanel!.sourceIndices, <int>[0, 1]);
      expect(r.ingredientList!.sourceIndices, <int>[2, 3]);
    });

    test('FR-PAR-13 the strength that matched is recorded', () {
      final ClassifiedRegions r =
          run(layoutOf(<String>['Nutritional Information', 'Energy 400']));
      expect(r.nutritionPanel!.matchStrength, ParseStrength.exact);
    });

    test('FR-PAR-13 the rule that classified the region is recorded', () {
      final ClassifiedRegions r =
          run(layoutOf(<String>['Ingredients: Wheat flour']));
      expect(r.ingredientList!.matchedBy, RuleId('rule.region.marker'));
    });

    test('FR-PAR-03 a same-kind marker continues the region, never splits it',
        () {
      // "Per 100 g" is a column header inside the panel, not a second panel.
      // Splitting on it would carve the header out of the block it labels.
      final ClassifiedRegions r = run(layoutOf(<String>[
        'Nutritional Information',
        'Per 100 g',
        'Energy 400 kcal',
      ]));
      expect(r.regions, hasLength(1));
      expect(r.nutritionPanel!.sourceIndices, <int>[0, 1, 2]);
    });

    test('FR-PAR-13 the strongest marker in a region sets its strength', () {
      // Opened by a heuristic cue, later confirmed by the real heading. The
      // recorded strength must reflect the best evidence, not the first.
      final ClassifiedRegions r = run(layoutOf(<String>[
        'Per Serving',
        'Nutritional Information',
        'Energy 400 kcal',
      ]));
      expect(r.nutritionPanel!.matchStrength, ParseStrength.exact);
    });

    test('FR-ERR-03 text before the first marker is retained as other', () {
      final ClassifiedRegions r = run(layoutOf(<String>[
        'Crunchy Masala Biscuits',
        'Net Qty 100 g',
        'Nutritional Information',
        'Energy 400 kcal',
      ]));
      expect(r.otherRegions, hasLength(1));
      expect(r.otherRegions.single.sourceIndices, <int>[0, 1]);
      expect(r.nutritionPanel!.sourceIndices, <int>[2, 3]);
    });

    test('FR-ERR-03 a repeated kind is demoted to other, never dropped', () {
      // A second nutrition block after the ingredients is ambiguous. Keeping
      // the first and retaining the second as unclassified is deterministic
      // and loses no text; discarding it would violate FR-ERR-03.
      final ClassifiedRegions r = run(layoutOf(<String>[
        'Nutritional Information',
        'Energy 400 kcal',
        'Ingredients: Wheat flour',
        'Nutrition Facts',
        'Protein 8 g',
      ]));
      expect(r.nutritionPanel!.sourceIndices, <int>[0, 1]);
      expect(r.ingredientList!.sourceIndices, <int>[2]);
      expect(r.otherRegions.single.sourceIndices, <int>[3, 4]);
    });
  });

  group('S3 — partial labels are complete results (FR-PAR-14)', () {
    test('FR-PAR-14 a nutrition-only label reports no ingredient list', () {
      final ClassifiedRegions r =
          run(layoutOf(<String>['Nutrition Facts', 'Energy 400 kcal']));
      expect(r.hasNutritionPanel, isTrue);
      expect(r.hasIngredientList, isFalse);
      expect(r.ingredientList, isNull);
    });

    test('FR-PAR-14 an ingredients-only label reports no nutrition panel', () {
      final ClassifiedRegions r =
          run(layoutOf(<String>['Ingredients: Wheat flour, Sugar']));
      expect(r.hasIngredientList, isTrue);
      expect(r.hasNutritionPanel, isFalse);
      expect(r.nutritionPanel, isNull);
    });

    test('FR-PAR-14 a single-line label with a marker succeeds', () {
      final ClassifiedRegions r = run(layoutOf(<String>['Ingredients: Salt']));
      expect(r.regions, hasLength(1));
    });
  });

  group('S3 — traceability (approved design goal, M5 owner requirement)', () {
    test('FR-PAR-13 the output records the stage that produced it', () {
      final ClassifiedRegions r = run(layoutOf(<String>['Ingredients: Salt']));
      expect(r.producedByStage, PipelineStage.regionClassification);
    });

    test('FR-PAR-13 every source index appears in exactly one region', () {
      // The provenance chain M3 and M4 built must not leak here. An index
      // that vanishes is a value no later stage can trace to a pixel.
      final ClassifiedRegions r = run(layoutOf(<String>[
        'Brand Name',
        'Nutritional Information',
        'Energy 400 kcal',
        'Ingredients: Wheat flour',
      ]));
      expect(r.sourceIndices, <int>[0, 1, 2, 3]);
      final int total = r.regions.fold<int>(
        0,
        (int sum, ClassifiedRegion x) => sum + x.sourceIndices.length,
      );
      expect(total, 4, reason: 'no index may appear in two regions');
    });

    test('FR-PAR-13 a region carries the bounding box of its lines', () {
      final ClassifiedRegions r = run(layoutOf(<String>[
        'Nutritional Information',
        'Energy 400 kcal',
      ]));
      expect(r.nutritionPanel!.region, box(100, 0, 900, 160));
    });
  });

  group('S3 — domain independence is the point of Q13', () {
    test('FR-CAT-01 a cosmetics table classifies cosmetic vocabulary', () {
      // The Stage 3 reuse boundary, exercised. S3 holds no food knowledge of
      // its own; the marker table is the whole of its vocabulary.
      final RegionMarkerTable cosmetics = RegionMarkerTable(<RegionMarker>[
        RegionMarker(
          text: 'inci',
          kind: RegionKind.ingredientList,
          strength: ParseStrength.exact,
        ),
      ]);
      final ClassifiedRegions r = run(
        layoutOf(<String>['INCI', 'Aqua, Glycerin, Parfum']),
        markers: cosmetics,
      );
      expect(r.ingredientList!.sourceIndices, <int>[0, 1]);
      expect(r.hasNutritionPanel, isFalse);
    });

    test(
        'FR-PAR-16 identical geometry classifies identically whatever the '
        'words say, given a matching table', () {
      final RegionMarkerTable a = RegionMarkerTable(<RegionMarker>[
        RegionMarker(
          text: 'alpha',
          kind: RegionKind.nutritionPanel,
          strength: ParseStrength.exact,
        ),
      ]);
      final RegionMarkerTable b = RegionMarkerTable(<RegionMarker>[
        RegionMarker(
          text: 'beta',
          kind: RegionKind.nutritionPanel,
          strength: ParseStrength.exact,
        ),
      ]);
      final ClassifiedRegions ra =
          run(layoutOf(<String>['alpha', 'x']), markers: a);
      final ClassifiedRegions rb =
          run(layoutOf(<String>['beta', 'x']), markers: b);
      expect(ra.regions.length, rb.regions.length);
      expect(
          ra.nutritionPanel!.sourceIndices, rb.nutritionPanel!.sourceIndices);
      expect(
          ra.nutritionPanel!.matchStrength, rb.nutritionPanel!.matchStrength);
    });
  });

  group('S3 — determinism (FR-PAR-02)', () {
    test('FR-PAR-02 repeated classification of one layout is identical', () {
      final LabelLayout l = layoutOf(<String>[
        'Brand',
        'Nutritional Information',
        'Energy 400 kcal',
        'Ingredients: Salt',
      ]);
      final ClassifiedRegions first = run(l);
      final ClassifiedRegions second = run(l);
      expect(first.regions, second.regions);
      expect(first.sourceIndices, second.sourceIndices);
      expect(first.toString(), second.toString());
    });
  });
}
