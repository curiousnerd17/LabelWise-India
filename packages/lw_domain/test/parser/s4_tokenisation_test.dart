import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  /// Builds S3 output directly, so S4 is tested in isolation
  /// (ARCHITECTURE 6.2: each stage independently testable).
  ///
  /// One element per line unless a line is given as several column cells.
  ClassifiedRegions regionsOf({
    List<Object> nutrition = const <Object>[],
    List<Object> ingredients = const <Object>[],
    bool withColumns = false,
  }) {
    int nextIndex = 0;
    final List<LayoutColumn> columns = <LayoutColumn>[];
    final List<int> leftBand = <int>[];
    final List<int> rightBand = <int>[];

    List<LayoutLine> build(List<Object> rows, int yBase) {
      final List<LayoutLine> lines = <LayoutLine>[];
      for (int i = 0; i < rows.length; i++) {
        final Object row = rows[i];
        final List<String> cells =
            row is List<String> ? row : <String>[row as String];
        final int top = yBase + i * 100;
        final List<NormalisedElement> elements = <NormalisedElement>[];
        for (int c = 0; c < cells.length; c++) {
          final int left = c == 0 ? 100 : 3000;
          final RegionRef r = box(left, top, left + 800, top + 60);
          elements.add(NormalisedElement(
            sourceIndex: nextIndex,
            originalText: cells[c],
            text: cells[c],
            region: r,
          ));
          (c == 0 ? leftBand : rightBand).add(nextIndex);
          nextIndex++;
        }
        lines.add(LayoutLine(
          elements: elements,
          region: box(100, top, 3800, top + 60),
        ));
      }
      return lines;
    }

    final List<LayoutLine> nLines = build(nutrition, 1000);
    final List<LayoutLine> iLines = build(ingredients, 5000);

    if (withColumns) {
      columns.add(LayoutColumn(
        index: 0,
        left: 100,
        right: 900,
        sourceIndices: leftBand,
      ));
      if (rightBand.isNotEmpty) {
        columns.add(LayoutColumn(
          index: 1,
          left: 3000,
          right: 3800,
          sourceIndices: rightBand,
        ));
      }
    }

    return ClassifiedRegions(
      regions: <ClassifiedRegion>[
        if (nLines.isNotEmpty)
          ClassifiedRegion(
            kind: RegionKind.nutritionPanel,
            lines: nLines,
            region: nLines.first.region,
            matchStrength: ParseStrength.exact,
          ),
        if (iLines.isNotEmpty)
          ClassifiedRegion(
            kind: RegionKind.ingredientList,
            lines: iLines,
            region: iLines.first.region,
            matchStrength: ParseStrength.exact,
          ),
      ],
      columns: columns,
    );
  }

  Candidates run(ClassifiedRegions r) {
    final StageResult<Candidates> out = tokenise(r);
    expect(out.isSuccess, isTrue, reason: 'expected S4 success');
    return out.valueOrNull!;
  }

  group('S4 — failure paths are values, not exceptions (FR-PAR-17)', () {
    test('FR-PAR-17 nothing classified yields regionNotFound', () {
      final StageResult<Candidates> out = tokenise(
        ClassifiedRegions(regions: const <ClassifiedRegion>[]),
      );
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
      expect(out.failureOrNull!.stage, PipelineStage.tokenisation);
    });

    test('FR-ERR-03 an unreadable panel is present-but-empty, not absent', () {
      // The distinction FR-ERR-03 exists for. One empty list would leave S5
      // unable to tell "we could not read it" from "the label declares none".
      final Candidates c =
          run(regionsOf(nutrition: <Object>['Nutrition Facts']));
      expect(c.nutritionCandidates, isEmpty);
      expect(c.nutritionPanelPresent, isTrue);
      expect(c.ingredientListPresent, isFalse);
    });
  });

  group('S4 — nutrition quadruples (FR-PAR-04, FR-PAR-18)', () {
    test('FR-PAR-04 a line splits into label, value and unit', () {
      final Candidates c = run(regionsOf(nutrition: <Object>['Protein 8 g']));
      expect(c.nutritionCandidates, hasLength(1));
      final NutritionCandidate n = c.nutritionCandidates.single;
      expect(n.labelText, 'Protein');
      expect(n.valueText, '8');
      expect(n.unitText, 'g');
      expect(n.qualifier, Qualifier.exact);
    });

    test('FR-PAR-05 a line with no unit reports none, and parses weakly', () {
      // S5 turns a null unit into an unresolved field. Inventing "g" here
      // would manufacture a declaration the label never made.
      final NutritionCandidate n = run(regionsOf(
        nutrition: <Object>['Energy 400'],
      )).nutritionCandidates.single;
      expect(n.unitText, isNull);
      expect(n.parseStrength, ParseStrength.heuristic);
    });

    test('FR-PAR-18 a detached less-than bound is read, not absorbed', () {
      final NutritionCandidate n = run(regionsOf(
        nutrition: <Object>['Trans Fat < 0.5 g'],
      )).nutritionCandidates.single;
      expect(n.labelText, 'Trans Fat');
      expect(n.qualifier, Qualifier.lessThan);
      expect(n.valueText, '0.5');
      expect(n.unitText, 'g');
    });

    test('FR-PAR-18 a flush bound reads identically', () {
      final NutritionCandidate n = run(regionsOf(
        nutrition: <Object>['Trans Fat <0.5 g'],
      )).nutritionCandidates.single;
      expect(n.qualifier, Qualifier.lessThan);
      expect(n.valueText, '0.5');
    });

    test('FR-PAR-18 an approximate serving count keeps its qualifier', () {
      final NutritionCandidate n = run(regionsOf(
        nutrition: <Object>['Servings Per Pack About 4'],
      )).nutritionCandidates.single;
      expect(n.labelText, 'Servings Per Pack');
      expect(n.qualifier, Qualifier.approximately);
      expect(n.valueText, '4');
    });

    test('FR-PAR-04 the value carries the column band that gives it a basis',
        () {
      final Candidates c = run(regionsOf(
        nutrition: <Object>[
          <String>['Protein', '8 g'],
        ],
        withColumns: true,
      ));
      expect(c.nutritionCandidates.single.columnIndex, 1);
    });

    test('FR-PAR-05 no band means no column, never a guessed one', () {
      final Candidates c = run(regionsOf(nutrition: <Object>['Protein 8 g']));
      expect(c.nutritionCandidates.single.columnIndex, isNull);
    });

    test('FR-PAR-05 a line with no number yields no candidate', () {
      // A heading is not a declaration. Emitting it as one would give S5 a
      // label to resolve and no value to attach.
      final Candidates c = run(regionsOf(
        nutrition: <Object>['Nutritional Information', 'Protein 8 g'],
      ));
      expect(c.nutritionCandidates, hasLength(1));
      expect(c.nutritionCandidates.single.labelText, 'Protein');
    });

    test('FR-PAR-05 a number with no label yields no candidate', () {
      final Candidates c = run(regionsOf(
        nutrition: <Object>['400', 'Protein 8 g'],
      ));
      expect(c.nutritionCandidates, hasLength(1));
    });

    test('FR-PAR-13 every candidate traces to the line it came from', () {
      final Candidates c = run(regionsOf(
        nutrition: <Object>['Protein 8 g', 'Total Fat 12 g'],
      ));
      expect(c.nutritionCandidates[0].sourceIndices, <int>[0]);
      expect(c.nutritionCandidates[1].sourceIndices, <int>[1]);
    });

    test('FR-PAR-16 a non-nutrition vocabulary tokenises identically', () {
      // S4 recognises the shape of a declaration, not the meaning of any word
      // in it. This is the Stage 3 reuse boundary, exercised.
      final NutritionCandidate food = run(regionsOf(
        nutrition: <Object>['Protein 8 g'],
      )).nutritionCandidates.single;
      final NutritionCandidate cosmetic = run(regionsOf(
        nutrition: <Object>['Glycerin 8 g'],
      )).nutritionCandidates.single;
      expect(food.valueText, cosmetic.valueText);
      expect(food.unitText, cosmetic.unitText);
      expect(food.parseStrength, cosmetic.parseStrength);
    });
  });

  group('S4 — ingredient tokenisation (FR-PAR-10, FR-PAR-12)', () {
    test('FR-PAR-10 declaration order is preserved and 1-based', () {
      // Order is legally meaningful: descending by weight. Losing it destroys
      // the only quantitative information the list carries.
      final Candidates c = run(regionsOf(
        ingredients: <Object>['Ingredients: Wheat flour, Sugar, Salt'],
      ));
      expect(
        c.ingredientTokens.map((IngredientToken t) => t.rawText),
        <String>['Wheat flour', 'Sugar', 'Salt'],
      );
      expect(
        c.ingredientTokens.map((IngredientToken t) => t.position),
        <int>[1, 2, 3],
      );
    });

    test('FR-PAR-12 a parenthetical group becomes nested children', () {
      final Candidates c = run(regionsOf(
        ingredients: <Object>[
          'Ingredients: Sugar, Emulsifier (INS 322, INS 471), Salt',
        ],
      ));
      expect(c.ingredientTokens, hasLength(3));
      final IngredientToken e = c.ingredientTokens[1];
      expect(e.rawText, 'Emulsifier (INS 322, INS 471)');
      expect(
        e.children.map((IngredientToken t) => t.rawText),
        <String>['INS 322', 'INS 471'],
      );
      expect(e.children.map((IngredientToken t) => t.position), <int>[1, 2]);
      expect(e.depth, 2);
    });

    test('FR-PAR-12 the heading is stripped at its colon', () {
      final Candidates c = run(regionsOf(
        ingredients: <Object>['INGREDIENTS: Wheat flour'],
      ));
      expect(c.ingredientTokens.single.rawText, 'Wheat flour');
    });

    test('FR-PAR-12 without a colon nothing is stripped', () {
      // No structural evidence of a heading means no heading is assumed.
      final Candidates c = run(regionsOf(
        ingredients: <Object>['Wheat flour, Sugar'],
      ));
      expect(c.ingredientTokens, hasLength(2));
      expect(c.ingredientTokens.first.rawText, 'Wheat flour');
    });

    test('FR-PAR-10 a list wrapping across lines is joined before splitting',
        () {
      final Candidates c = run(regionsOf(
        ingredients: <Object>['Ingredients: Wheat flour, Su', 'gar, Salt'],
      ));
      expect(
        c.ingredientTokens.map((IngredientToken t) => t.rawText),
        <String>['Wheat flour', 'Su gar', 'Salt'],
      );
    });

    test('R-M5-3 an unclosed bracket closes at the end and is marked weak', () {
      // OCR drops brackets routinely. Refusing the list over one missing
      // character would discard every ingredient on the packet.
      final Candidates c = run(regionsOf(
        ingredients: <Object>['Ingredients: Wheat flour, Emulsifier (INS 322'],
      ));
      expect(c.ingredientTokens, hasLength(2));
      expect(c.ingredientTokens[0].parseStrength, ParseStrength.exact);
      expect(c.ingredientTokens[1].parseStrength, ParseStrength.heuristic);
      expect(c.ingredientTokens[1].children.single.rawText, 'INS 322');
    });

    test('R-M5-3 a stray closing bracket is literal text, not structure', () {
      final Candidates c = run(regionsOf(
        ingredients: <Object>['Ingredients: Wheat flour), Sugar'],
      ));
      expect(c.ingredientTokens, hasLength(2));
      expect(c.ingredientTokens[0].rawText, 'Wheat flour)');
      expect(c.ingredientTokens[0].children, isEmpty);
    });

    test('FR-PAR-10 empty segments between commas are dropped', () {
      final Candidates c = run(regionsOf(
        ingredients: <Object>['Ingredients: Wheat flour, , Sugar'],
      ));
      expect(
        c.ingredientTokens.map((IngredientToken t) => t.rawText),
        <String>['Wheat flour', 'Sugar'],
      );
      expect(c.ingredientTokens.last.position, 2,
          reason: 'positions must stay contiguous after a drop');
    });

    test('FR-PAR-13 every ingredient traces to the region it came from', () {
      final Candidates c = run(regionsOf(
        ingredients: <Object>['Ingredients: Wheat flour, Sugar'],
      ));
      for (final IngredientToken t in c.ingredientTokens) {
        expect(t.sourceIndices, isNotEmpty);
        expect(t.sourceIndices, <int>[0]);
      }
    });
  });

  group('S4 — tolerance and traceability (AR5, M5 owner requirement)', () {
    test('AR5 a misclassified region still produces usable output', () {
      // S3 classifies on structural cues and will sometimes be wrong. S4 must
      // apply its rules to whatever it is handed rather than assume S3 was
      // right — DATA_MODEL 7.9 accepted that cost explicitly.
      final ClassifiedRegions swapped = ClassifiedRegions(
        regions: <ClassifiedRegion>[
          ClassifiedRegion(
            kind: RegionKind.ingredientList,
            lines: regionsOf(nutrition: <Object>['Protein 8 g'])
                .nutritionPanel!
                .lines,
            region: box(0, 0, 10, 10),
            matchStrength: ParseStrength.heuristic,
          ),
        ],
      );
      final Candidates c = run(swapped);
      expect(c.ingredientTokens, hasLength(1));
      expect(c.ingredientTokens.single.rawText, 'Protein 8 g');
      expect(c.hasNutrition, isFalse);
    });

    test('FR-PAR-14 a partial label produces a complete result for its half',
        () {
      final Candidates c = run(regionsOf(
        ingredients: <Object>['Ingredients: Salt'],
      ));
      expect(c.hasIngredients, isTrue);
      expect(c.hasNutrition, isFalse);
      expect(c.nutritionPanelPresent, isFalse);
    });

    test('FR-PAR-13 the output records the stage that produced it', () {
      expect(run(regionsOf(nutrition: <Object>['Protein 8 g'])).producedByStage,
          PipelineStage.tokenisation);
    });

    test('FR-PAR-02 repeated tokenisation of one input is identical', () {
      final ClassifiedRegions r = regionsOf(
        nutrition: <Object>['Protein 8 g', 'Trans Fat < 0.5 g'],
        ingredients: <Object>['Ingredients: Sugar, Emulsifier (INS 322)'],
      );
      final Candidates first = run(r);
      final Candidates second = run(r);
      expect(first.nutritionCandidates, second.nutritionCandidates);
      expect(first.ingredientTokens, second.ingredientTokens);
      expect(first.sourceIndices, second.sourceIndices);
      expect(first.toString(), second.toString());
    });
  });
}
