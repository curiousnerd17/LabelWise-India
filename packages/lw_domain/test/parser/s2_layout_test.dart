import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  /// Builds S1 output directly, so S2 is tested in isolation
  /// (ARCHITECTURE 6.2: each stage independently testable).
  NormalisedText layoutInput(List<(String, RegionRef)> items) => NormalisedText(
        elements: <NormalisedElement>[
          for (int i = 0; i < items.length; i++)
            NormalisedElement(
              sourceIndex: i,
              originalText: items[i].$1,
              text: items[i].$1,
              region: items[i].$2,
            ),
        ],
      );

  LabelLayout run(NormalisedText t) {
    final StageResult<LabelLayout> out = reconstructLayout(t);
    expect(out.isSuccess, isTrue, reason: 'expected S2 success');
    return out.valueOrNull!;
  }

  group('S2 — line clustering by geometry alone (FR-PAR-03)', () {
    test('FR-PAR-03 elements sharing a vertical band form one line', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('Energy', box(100, 1000, 400, 1060)),
        ('400', box(600, 1005, 800, 1065)),
        ('kcal', box(850, 1000, 950, 1060)),
      ]));
      expect(l.lines, hasLength(1));
      expect(
        l.lines.single.elements.map((NormalisedElement e) => e.text),
        <String>['Energy', '400', 'kcal'],
      );
    });

    test('FR-PAR-03 vertically separated elements form separate lines', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('Energy', box(100, 1000, 400, 1060)),
        ('Protein', box(100, 2000, 400, 2060)),
      ]));
      expect(l.lines, hasLength(2));
    });

    test('FR-PAR-03 elements within a line are ordered left to right', () {
      // Input deliberately out of reading order: S2 must impose order from
      // geometry, not trust the engine's sequence.
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('kcal', box(850, 1000, 950, 1060)),
        ('Energy', box(100, 1000, 400, 1060)),
        ('400', box(600, 1000, 800, 1060)),
      ]));
      expect(
        l.lines.single.elements.map((NormalisedElement e) => e.text),
        <String>['Energy', '400', 'kcal'],
      );
    });

    test('FR-PAR-03 lines are ordered top to bottom', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('third', box(100, 3000, 400, 3060)),
        ('first', box(100, 1000, 400, 1060)),
        ('second', box(100, 2000, 400, 2060)),
      ]));
      expect(
        l.lines.map((LayoutLine x) => x.elements.single.text),
        <String>['first', 'second', 'third'],
      );
    });

    test('FR-PAR-03 partial vertical overlap above threshold shares a line',
        () {
      // Real OCR boxes rarely align exactly. The threshold is a named constant
      // so the tuning point is visible rather than buried in a comparison.
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('a', box(100, 1000, 200, 1100)),
        ('b', box(300, 1040, 400, 1140)),
      ]));
      expect(l.lines, hasLength(1));
      expect(LayoutThresholds.sameLineOverlapRatioPercent, 50);
    });

    test('FR-PAR-03 overlap below threshold splits the line', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('a', box(100, 1000, 200, 1100)),
        ('b', box(300, 1090, 400, 1190)),
      ]));
      expect(l.lines, hasLength(2));
    });
  });

  group('S2 — column detection (FR-PAR-03)', () {
    test('FR-PAR-03 a two-column panel yields two columns', () {
      // The per-100g / per-serve pairing FR-PAR-04 depends on. S2 finds the
      // bands; assigning meaning to them is S5's job.
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('Energy', box(100, 1000, 900, 1060)),
        ('400', box(3000, 1000, 3400, 1060)),
        ('Protein', box(100, 2000, 900, 2060)),
        ('12', box(3000, 2000, 3400, 2060)),
      ]));
      expect(l.columns, hasLength(2));
      expect(l.columns.first.left, lessThan(l.columns.last.left));
    });

    test('FR-PAR-03 a single-column panel yields one column', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('Energy 400 kcal', box(100, 1000, 900, 1060)),
        ('Protein 12 g', box(100, 2000, 900, 2060)),
      ]));
      expect(l.columns, hasLength(1));
    });

    test('FR-PAR-03 three columns are detected', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('Nutrient', box(100, 1000, 800, 1060)),
        ('Per100g', box(3000, 1000, 3700, 1060)),
        ('PerServe', box(6000, 1000, 6700, 1060)),
      ]));
      expect(l.columns, hasLength(3));
    });

    test('FR-PAR-03 columns are ordered left to right', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('right', box(6000, 1000, 6700, 1060)),
        ('left', box(100, 1000, 800, 1060)),
      ]));
      expect(l.columns.first.left, lessThan(l.columns.last.left));
      expect(l.columns.first.index, 0);
      expect(l.columns.last.index, 1);
    });

    test('FR-PAR-03 the column gap threshold is a named constant', () {
      expect(LayoutThresholds.columnGapNormalised, 400);
    });
  });

  group('S2 — degenerate input (FR-PAR-17)', () {
    test('FR-PAR-17 no elements yields layoutIndeterminate', () {
      final StageResult<LabelLayout> out = reconstructLayout(
        NormalisedText(elements: const <NormalisedElement>[]),
      );
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.layoutIndeterminate);
      expect(out.failureOrNull!.stage, PipelineStage.layoutReconstruction);
    });

    test('FR-PAR-17 all-degenerate geometry yields layoutIndeterminate', () {
      // Zero-area boxes carry no positional information, so lines cannot be
      // formed. Guessing would be worse than declining.
      final StageResult<LabelLayout> out = reconstructLayout(
        layoutInput(<(String, RegionRef)>[
          ('a', box(100, 100, 100, 100)),
          ('b', box(200, 200, 200, 200)),
        ]),
      );
      expect(out.failureOrNull!.kind, ParseFailureKind.layoutIndeterminate);
    });

    test('FR-PAR-14 a single element produces a valid one-line layout', () {
      final LabelLayout l =
          run(layoutInput(<(String, RegionRef)>[('x', box(0, 0, 100, 60))]));
      expect(l.lines, hasLength(1));
      expect(l.columns, hasLength(1));
    });

    test('FR-PAR-17 a mix of degenerate and real elements still succeeds', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('zero', box(100, 100, 100, 100)),
        ('real', box(100, 1000, 900, 1060)),
      ]));
      expect(l.lines, isNotEmpty);
    });
  });

  group('S2 — traceability (approved design goal)', () {
    test('FR-PAR-13 every line records the source indices that formed it', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('Energy', box(100, 1000, 400, 1060)),
        ('400', box(600, 1000, 800, 1060)),
      ]));
      expect(l.lines.single.sourceIndices, <int>[0, 1]);
    });

    test('FR-PAR-13 every column records the source indices it spans', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('Energy', box(100, 1000, 900, 1060)),
        ('400', box(3000, 1000, 3400, 1060)),
      ]));
      expect(l.columns.first.sourceIndices, <int>[0]);
      expect(l.columns.last.sourceIndices, <int>[1]);
    });

    test('FR-PAR-13 each line carries its bounding region', () {
      final LabelLayout l = run(layoutInput(<(String, RegionRef)>[
        ('a', box(100, 1000, 400, 1060)),
        ('b', box(600, 1010, 800, 1070)),
      ]));
      expect(l.lines.single.region, box(100, 1000, 800, 1070));
    });

    test('FR-PAR-13 the layout records the stage that produced it', () {
      final LabelLayout l =
          run(layoutInput(<(String, RegionRef)>[('x', box(0, 0, 10, 10))]));
      expect(l.producedByStage, PipelineStage.layoutReconstruction);
    });
  });

  group('S2 — semantic freedom (ARCHITECTURE 6.3)', () {
    test(
        'FR-CAT-01 identical geometry yields identical layout whatever the '
        'text says', () {
      // S2 must be reusable for cosmetics and medicine labels in Stage 3, which
      // share the physical layout problem and none of the vocabulary.
      List<(String, RegionRef)> shape(String a, String b) =>
          <(String, RegionRef)>[
            (a, box(100, 1000, 900, 1060)),
            (b, box(3000, 1000, 3400, 1060)),
          ];
      final LabelLayout nutrition = run(layoutInput(shape('Energy', '400')));
      final LabelLayout cosmetic = run(layoutInput(shape('Aqua', 'INCI')));
      expect(nutrition.lines.length, cosmetic.lines.length);
      expect(nutrition.columns.length, cosmetic.columns.length);
      expect(
        nutrition.lines.single.sourceIndices,
        cosmetic.lines.single.sourceIndices,
      );
    });
  });
}
