import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  SynonymTable table() => SynonymTable(<SynonymEntry>[
        SynonymEntry(
          nutrient: NutrientId.energy,
          patterns: const <SynonymPattern>[
            SynonymPattern(text: 'Energy', strength: ParseStrength.exact),
            SynonymPattern(text: 'Calories', strength: ParseStrength.heuristic),
          ],
          expectedUnits: const <Unit>[Unit.kilocalorie, Unit.kilojoule],
        ),
        SynonymEntry(
          nutrient: NutrientId.protein,
          patterns: const <SynonymPattern>[
            SynonymPattern(text: 'Protein', strength: ParseStrength.exact),
          ],
          expectedUnits: const <Unit>[Unit.gram],
        ),
        SynonymEntry(
          nutrient: NutrientId.transFat,
          patterns: const <SynonymPattern>[
            SynonymPattern(text: 'Trans Fat', strength: ParseStrength.exact),
          ],
          expectedUnits: const <Unit>[Unit.gram],
        ),
      ]);

  NutritionCandidate candidate(
    String label,
    String value, {
    String? unit = 'g',
    int? column = 1,
    Qualifier qualifier = Qualifier.exact,
    List<int> at = const <int>[0],
  }) =>
      NutritionCandidate(
        labelText: label,
        valueText: value,
        unitText: unit,
        qualifier: qualifier,
        columnIndex: column,
        region: box(0, 0, 100, 60),
        sourceIndices: at,
        parseStrength: ParseStrength.exact,
      );

  ColumnHeader head(int index, String text) => ColumnHeader(
        columnIndex: index,
        text: text,
        region: box(0, 0, 100, 60),
        sourceIndices: const <int>[99],
      );

  Candidates input(
    List<NutritionCandidate> cs, {
    List<ColumnHeader> headers = const <ColumnHeader>[],
    List<IngredientToken> ingredients = const <IngredientToken>[],
  }) =>
      Candidates(
        nutritionCandidates: cs,
        ingredientTokens: ingredients,
        columnHeaders: headers,
        nutritionPanelPresent: true,
        ingredientListPresent: ingredients.isNotEmpty,
      );

  ResolvedFields run(Candidates c, {BasisMarkerTable? bases}) {
    final StageResult<ResolvedFields> out =
        resolveFields(c, synonyms: table(), bases: bases);
    expect(out.isSuccess, isTrue, reason: 'expected S5 success');
    return out.valueOrNull!;
  }

  final List<ColumnHeader> per100 = <ColumnHeader>[
    head(0, 'Nutrient'),
    head(1, 'Per 100 g'),
  ];

  group('S5 — failure paths are values, not exceptions (FR-PAR-17)', () {
    test('FR-PAR-17 nothing supplied yields regionNotFound', () {
      final StageResult<ResolvedFields> out =
          resolveFields(Candidates(), synonyms: table());
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
      expect(out.failureOrNull!.stage, PipelineStage.fieldResolution);
    });

    test('FR-PAR-14 an ingredients-only label resolves successfully', () {
      final StageResult<ResolvedFields> out = resolveFields(
        Candidates(
          ingredientTokens: <IngredientToken>[
            IngredientToken(
              position: 1,
              rawText: 'Salt',
              region: box(0, 0, 10, 10),
              sourceIndices: const <int>[0],
              parseStrength: ParseStrength.exact,
            ),
          ],
          ingredientListPresent: true,
        ),
        synonyms: table(),
      );
      expect(out.isSuccess, isTrue);
      expect(out.valueOrNull!.fields, isEmpty);
      expect(out.valueOrNull!.ingredientTokens, hasLength(1));
    });
  });

  group('S5 — synonym resolution (FR-PAR-13, ADR-0012)', () {
    test('FR-PAR-13 a label resolves to its nutrient at the match strength',
        () {
      final ResolvedFields r = run(input(
          <NutritionCandidate>[candidate('Protein', '8')],
          headers: per100));
      expect(r.fields, hasLength(1));
      expect(r.fields.single.nutrient, NutrientId.protein);
      expect(r.fields.single.labelStrength, ParseStrength.exact);
    });

    test('FR-PAR-13 a heuristic synonym is recorded as heuristic', () {
      // Strength is signal S2. Recording a fuzzy match as exact would tell S8
      // the parse was firmer than it was.
      final ResolvedFields r = run(input(
          <NutritionCandidate>[candidate('Calories', '400')],
          headers: per100));
      expect(r.fields.single.nutrient, NutrientId.energy);
      expect(r.fields.single.labelStrength, ParseStrength.heuristic);
    });

    test('FR-PAR-13 matching is case-insensitive through the table', () {
      final ResolvedFields r = run(input(
          <NutritionCandidate>[candidate('PROTEIN', '8')],
          headers: per100));
      expect(r.fields.single.nutrient, NutrientId.protein);
    });

    test('FR-PAR-05 an unknown label is unresolved, never guessed', () {
      // Returning a best-effort nutrient would produce a confident wrong
      // answer, which FR-PAR-05 and P1 both forbid.
      final ResolvedFields r = run(input(
          <NutritionCandidate>[candidate('Riboflavin', '2')],
          headers: per100));
      expect(r.fields, isEmpty);
      expect(r.unresolved.single.reason, UnresolvedReason.noMatchingRule);
      expect(r.unresolved.single.labelText, 'Riboflavin');
    });

    test('FR-PAR-13 the resolving rule is recorded', () {
      final ResolvedFields r = run(input(
          <NutritionCandidate>[candidate('Protein', '8')],
          headers: per100));
      expect(r.fields.single.matchedBy, RuleId('rule.resolve.synonym'));
    });
  });

  group('S5 — basis from column headers (ARCHITECTURE 6.1)', () {
    test('FR-PAR-04 a per-100 g header assigns the per-100 g basis', () {
      final ResolvedFields r = run(input(
          <NutritionCandidate>[candidate('Protein', '8')],
          headers: per100));
      expect(r.fields.single.basis, Basis.per100g);
      expect(r.fields.single.basisStrength, ParseStrength.exact);
    });

    test('FR-PAR-04 a per-serve header assigns the per-serve basis', () {
      final ResolvedFields r = run(input(
        <NutritionCandidate>[candidate('Protein', '8')],
        headers: <ColumnHeader>[head(1, 'Per Serve (30 g)')],
      ));
      expect(r.fields.single.basis, Basis.perServe);
    });

    test('FR-PAR-04 a per-100 ml header assigns the volume basis', () {
      final ResolvedFields r = run(input(
        <NutritionCandidate>[candidate('Protein', '8')],
        headers: <ColumnHeader>[head(1, 'Per 100 ml')],
      ));
      expect(r.fields.single.basis, Basis.per100ml);
    });

    test('FR-PAR-04 a per-pack header assigns the pack basis', () {
      final ResolvedFields r = run(input(
        <NutritionCandidate>[candidate('Protein', '8')],
        headers: <ColumnHeader>[head(1, 'Per Pack')],
      ));
      expect(r.fields.single.basis, Basis.perPack);
    });

    test('FR-PAR-04 a single-column heading still yields a basis', () {
      // The common Indian layout: the basis is stated once, in the panel
      // heading, above one column of values.
      final ResolvedFields r = run(input(
        <NutritionCandidate>[candidate('Protein', '8', column: 0)],
        headers: <ColumnHeader>[
          head(0, 'Nutritional Information per 100 g'),
        ],
      ));
      expect(r.fields.single.basis, Basis.per100g);
    });

    test('FR-PAR-05 no column band means no basis, and so unresolved', () {
      // A right value on the wrong basis is wrong by a factor of three or
      // more. FR-PAR-05 requires silence over a default.
      final ResolvedFields r = run(input(
        <NutritionCandidate>[candidate('Protein', '8', column: null)],
        headers: per100,
      ));
      expect(r.fields, isEmpty);
      expect(r.unresolved.single.reason, UnresolvedReason.basisNotDetermined);
    });

    test('FR-PAR-05 a band with no heading is unresolved, never defaulted', () {
      final ResolvedFields r =
          run(input(<NutritionCandidate>[candidate('Protein', '8')]));
      expect(r.unresolved.single.reason, UnresolvedReason.basisNotDetermined);
    });

    test('FR-PAR-05 an uninterpretable heading is unresolved', () {
      final ResolvedFields r = run(input(
        <NutritionCandidate>[candidate('Protein', '8')],
        headers: <ColumnHeader>[head(1, 'Amount')],
      ));
      expect(r.unresolved.single.reason, UnresolvedReason.basisNotDetermined);
    });

    test('ADR-0013 a caller-supplied basis table replaces the default', () {
      final ResolvedFields r = run(
        input(
          <NutritionCandidate>[candidate('Protein', '8')],
          headers: <ColumnHeader>[head(1, 'Je 100 g')],
        ),
        bases: BasisMarkerTable(<BasisMarker>[
          BasisMarker(
            text: 'je 100 g',
            basis: Basis.per100g,
            strength: ParseStrength.normalised,
          ),
        ]),
      );
      expect(r.fields.single.basis, Basis.per100g);
      expect(r.fields.single.basisStrength, ParseStrength.normalised);
    });
  });

  group('S5 — ambiguity is reported, never silently resolved', () {
    test('FR-PAR-05 two candidates for one nutrient and basis are ambiguous',
        () {
      // OCR duplicates lines. Emitting two conflicting Protein figures for the
      // same basis would let a later stage pick one arbitrarily.
      final ResolvedFields r = run(input(
        <NutritionCandidate>[
          candidate('Protein', '8', at: const <int>[0]),
          candidate('Protein', '9', at: const <int>[1]),
        ],
        headers: per100,
      ));
      expect(r.fields, isEmpty);
      expect(r.unresolved, hasLength(2));
      bool ambiguous(UnresolvedCandidate u) =>
          u.reason == UnresolvedReason.ambiguousMatch;
      expect(r.unresolved.every(ambiguous), isTrue);
    });

    test('FR-PAR-04 the same nutrient on two bases is not ambiguous', () {
      // Per-100 g and per-serve protein are two legitimate declarations, not a
      // conflict. Treating them as one would discard half the panel.
      final ResolvedFields r = run(input(
        <NutritionCandidate>[
          candidate('Protein', '8', column: 1, at: const <int>[0]),
          candidate('Protein', '2', column: 2, at: const <int>[1]),
        ],
        headers: <ColumnHeader>[head(1, 'Per 100 g'), head(2, 'Per Serve')],
      ));
      expect(r.fields, hasLength(2));
      expect(r.unresolved, isEmpty);
      expect(
        r.fields.map((ResolvedField f) => f.basis),
        <Basis>[Basis.per100g, Basis.perServe],
      );
    });
  });

  group('S5 — the value is carried, never interpreted (S6 owns typing)', () {
    test('ADR-0027 the qualifier survives resolution untouched', () {
      final ResolvedFields r = run(input(
        <NutritionCandidate>[
          candidate('Trans Fat', '0.5', qualifier: Qualifier.lessThan),
        ],
        headers: per100,
      ));
      expect(r.fields.single.qualifier, Qualifier.lessThan);
      expect(r.fields.single.valueText, '0.5');
    });

    test('FR-PAR-05 a missing unit is carried forward for S6 to judge', () {
      // S5 resolves labels and bases. Whether a unit is readable is S6's
      // question, and answering it here would split one decision across two
      // stages.
      final ResolvedFields r = run(input(
        <NutritionCandidate>[candidate('Protein', '8', unit: null)],
        headers: per100,
      ));
      expect(r.fields.single.unitText, isNull);
    });
  });

  group('S5 — provenance and traceability (M6 owner requirement)', () {
    test('FR-PAR-13 the output records the stage that produced it', () {
      expect(
        run(input(<NutritionCandidate>[candidate('Protein', '8')],
                headers: per100))
            .producedByStage,
        PipelineStage.fieldResolution,
      );
    });

    test('FR-PAR-13 every resolved field keeps its source indices', () {
      final ResolvedFields r = run(input(
        <NutritionCandidate>[
          candidate('Protein', '8', at: const <int>[3, 4])
        ],
        headers: per100,
      ));
      expect(r.fields.single.sourceIndices, <int>[3, 4]);
      expect(r.fields.single.region, box(0, 0, 100, 60));
    });

    test('FR-PAR-13 an unresolved candidate keeps its source indices too', () {
      // FR-ERR-03 needs the failure to be as traceable as the success.
      final ResolvedFields r = run(input(
        <NutritionCandidate>[
          candidate('Riboflavin', '2', at: const <int>[7])
        ],
        headers: per100,
      ));
      expect(r.unresolved.single.sourceIndices, <int>[7]);
    });

    test('FR-PAR-10 ingredient tokens pass through untouched', () {
      final IngredientToken t = IngredientToken(
        position: 1,
        rawText: 'Wheat flour',
        region: box(0, 0, 10, 10),
        sourceIndices: const <int>[5],
        parseStrength: ParseStrength.exact,
      );
      final ResolvedFields r = run(input(
        <NutritionCandidate>[candidate('Protein', '8')],
        headers: per100,
        ingredients: <IngredientToken>[t],
      ));
      expect(r.ingredientTokens, <IngredientToken>[t]);
    });

    test('FR-PAR-02 repeated resolution of one input is identical', () {
      final Candidates c = input(
        <NutritionCandidate>[
          candidate('Protein', '8', at: const <int>[0]),
          candidate('Energy', '400', at: const <int>[1]),
        ],
        headers: per100,
      );
      expect(run(c).fields, run(c).fields);
      expect(run(c).sourceIndices, run(c).sourceIndices);
    });
  });

  group('ResolvedField — value semantics (P4)', () {
    ResolvedField build({
      String value = '8',
      Qualifier qualifier = Qualifier.lessThan,
      Basis basis = Basis.per100g,
    }) =>
        ResolvedField(
          nutrient: NutrientId.protein,
          valueText: value,
          unitText: 'g',
          qualifier: qualifier,
          basis: basis,
          labelStrength: ParseStrength.exact,
          basisStrength: ParseStrength.normalised,
          region: box(0, 0, 100, 60),
          sourceIndices: const <int>[3, 4],
          matchedBy: RuleId('rule.resolve.synonym'),
        );

    test('P4 compares by value, not identity', () {
      // S6 and S7 pass these across stage boundaries and compare them to
      // check determinism. Equality that fell back to identity would make
      // every such comparison fail for reasons unrelated to the data.
      final ResolvedField a = build();
      final ResolvedField b = build(value: String.fromCharCodes('8'.codeUnits));
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('P4 a different declaration is a different value', () {
      final ResolvedField a = build();
      expect(a, isNot(build(value: '9')),
          reason: 'the declared number is part of the field');
      expect(a, isNot(build(qualifier: Qualifier.exact)),
          reason: 'a bound is not the same declaration as a point (MI-14)');
      expect(a, isNot(build(basis: Basis.perServe)),
          reason: 'the same number on another basis is another declaration');
    });
  });
}
