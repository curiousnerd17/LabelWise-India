import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  final Version pack = Version(1, 0, 0);
  int nextIndex = 0;

  ScoredField scored(
    NutrientId nutrient, {
    Basis basis = Basis.per100g,
    Confidence confidence = Confidence.high,
  }) {
    final int index = nextIndex++;
    return ScoredField(
      nutrient: nutrient,
      basis: basis,
      state: ExtractedField(
        quantity: const Quantity.exact(800, Unit.gram),
        basis: basis,
        provenance: Provenance.extracted(
          producedByStage: PipelineStage.confidenceAssignment,
          parseRuleId: RuleId('rule.resolve.synonym'),
          parseStrength: ParseStrength.exact,
          sourceRegion: box(0, 0, 100, 60),
          rulePackVersion: pack,
        ),
        confidence: confidence,
      ),
      signals: ConfidenceSignals(s2ParseStrength: ParseStrength.exact),
      region: box(0, 0, 100, 60),
      sourceIndices: <int>[index],
    );
  }

  IngredientToken token(
    int position,
    String text, {
    List<IngredientToken> children = const <IngredientToken>[],
    ParseStrength strength = ParseStrength.exact,
  }) =>
      IngredientToken(
        position: position,
        rawText: text,
        region: box(0, 0, 10, 10),
        sourceIndices: <int>[nextIndex++],
        parseStrength: strength,
        children: children,
      );

  ScoredFields input({
    List<ScoredField> fields = const <ScoredField>[],
    List<IngredientToken> ingredients = const <IngredientToken>[],
    List<InvariantResult> results = const <InvariantResult>[],
    List<UnresolvedCandidate> unresolved = const <UnresolvedCandidate>[],
    ScanConfidence scan = ScanConfidence.partial,
  }) =>
      ScoredFields(
        fields: fields,
        ingredientTokens: ingredients,
        invariantResults: results,
        unresolved: unresolved,
        scanConfidence: scan,
        nutritionPanelPresent: true,
        ingredientListPresent: ingredients.isNotEmpty,
      );

  ParsedLabel run(
    ScoredFields s, {
    CategoryId? category,
    bool unsupported = false,
  }) {
    final StageResult<ParsedLabel> out = assembleParsedLabel(
      s,
      rulePackVersion: pack,
      declaredCategory: category,
      unsupportedScript: unsupported,
    );
    expect(out.isSuccess, isTrue, reason: 'expected assembly to succeed');
    return out.valueOrNull!;
  }

  setUp(() => nextIndex = 0);

  group('Assembly — failure is a value, not an exception (FR-PAR-17)', () {
    test('FR-PAR-17 nothing supplied yields regionNotFound', () {
      final StageResult<ParsedLabel> out = assembleParsedLabel(
        ScoredFields(scanConfidence: ScanConfidence.partial),
        rulePackVersion: pack,
      );
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
    });
  });

  group('Assembly — the nutrient triple (DATA_MODEL 5.2, D1)', () {
    test('FR-PAR-04 a per-100 g declaration lands in the perHundred slot', () {
      final ParsedLabel p =
          run(input(fields: <ScoredField>[scored(NutrientId.protein)]));
      final NutrientField f = p.nutrientFor(NutrientId.protein)!;
      expect(f.perHundred, isA<ExtractedField>());
      expect(f.perHundred.basisOrNull, Basis.per100g);
    });

    test('D1 a per-100 ml declaration lands in the same slot', () {
      // The slot is storage; the basis is read from the field. A beverage and
      // a biscuit fill the same slot with different meanings.
      final ParsedLabel p = run(input(fields: <ScoredField>[
        scored(NutrientId.energy, basis: Basis.per100ml),
      ]));
      expect(p.nutrientFor(NutrientId.energy)!.perHundred.basisOrNull,
          Basis.per100ml);
    });

    test('FR-PRS-02 all three slots are filled for a two-column panel', () {
      final ParsedLabel p = run(input(fields: <ScoredField>[
        scored(NutrientId.protein),
        scored(NutrientId.protein, basis: Basis.perServe),
      ]));
      final NutrientField f = p.nutrientFor(NutrientId.protein)!;
      expect(f.perHundred, isA<ExtractedField>());
      expect(f.perServe, isA<ExtractedField>());
      expect(f.perPack, isA<NotDeclaredField>());
    });

    test('FR-ERR-03 an undeclared basis is NotDeclared, not Unresolved', () {
      // The label genuinely did not declare per-serve. Saying we could not
      // read it would blame ourselves for the manufacturer's choice.
      final ParsedLabel p =
          run(input(fields: <ScoredField>[scored(NutrientId.protein)]));
      final NutrientField f = p.nutrientFor(NutrientId.protein)!;
      expect(f.perServe, isA<NotDeclaredField>());
      expect(f.perPack, isA<NotDeclaredField>());
    });

    test('D1 no slot is ever Derived — derivation is Layer 1', () {
      final ParsedLabel p =
          run(input(fields: <ScoredField>[scored(NutrientId.protein)]));
      for (final NutrientField f in p.nutrients) {
        expect(f.perHundred, isNot(isA<DerivedField>()));
        expect(f.perServe, isNot(isA<DerivedField>()));
        expect(f.perPack, isNot(isA<DerivedField>()));
      }
    });

    test('FR-CNF-01 the assigned confidence survives assembly', () {
      final ParsedLabel p = run(input(fields: <ScoredField>[
        scored(NutrientId.protein, confidence: Confidence.low),
      ]));
      expect(p.nutrientFor(NutrientId.protein)!.perHundred.confidenceOrNull,
          Confidence.low);
    });

    test('FR-PAR-02 nutrient order is deterministic, not arrival order', () {
      final ParsedLabel p = run(input(fields: <ScoredField>[
        scored(NutrientId.sodium),
        scored(NutrientId.protein),
        scored(NutrientId.energy),
      ]));
      // NutrientId declaration order: energy, protein, ..., sodium.
      expect(
        p.nutrients.map((NutrientField f) => f.nutrient),
        <NutrientId>[NutrientId.energy, NutrientId.protein, NutrientId.sodium],
      );
    });

    test('FR-PAR-09 a nutrient never read has no entry at all', () {
      // Different from an entry declaring nothing, and FR-ERR-03 turns on
      // keeping such pairs apart.
      final ParsedLabel p =
          run(input(fields: <ScoredField>[scored(NutrientId.protein)]));
      expect(p.nutrientFor(NutrientId.sodium), isNull);
    });
  });

  group('Assembly — serving figures (D2)', () {
    test('D2 all three pack figures are Unresolved, never invented', () {
      // No stage reads them and S8 assigns them no confidence, so an
      // ExtractedField would require inventing one. Unresolved is the honest
      // parser output until serving resolution exists.
      final ParsedLabel p = run(input());
      for (final FieldState f in <FieldState>[
        p.servingInfo.declaredServingSize,
        p.servingInfo.servingsPerPack,
        p.servingInfo.netQuantity,
      ]) {
        expect(f, isA<UnresolvedField>());
        expect((f as UnresolvedField).reason, UnresolvedReason.noMatchingRule);
      }
    });

    test('D2 no serving figure carries an inferred confidence', () {
      expect(run(input()).servingInfo.declaredServingSize.confidenceOrNull,
          isNull);
    });

    test('v1.6 reconciliation is null — it is a Layer 1 output', () {
      expect(run(input()).servingInfo.reconciliation, isNull);
    });
  });

  group('Assembly — ingredients (FR-PAR-10, FR-PAR-12)', () {
    test('FR-PAR-10 declaration order and position are preserved', () {
      final ParsedLabel p = run(input(ingredients: <IngredientToken>[
        token(1, 'Wheat flour'),
        token(2, 'Sugar'),
        token(3, 'Salt'),
      ]));
      expect(
        p.ingredients.map((Ingredient i) => i.rawText),
        <String>['Wheat flour', 'Sugar', 'Salt'],
      );
      expect(p.ingredients.map((Ingredient i) => i.position), <int>[1, 2, 3]);
    });

    test('FR-PAR-12 nesting survives assembly', () {
      final ParsedLabel p = run(input(ingredients: <IngredientToken>[
        token(
          1,
          'Emulsifier (INS 322)',
          children: <IngredientToken>[token(1, 'INS 322')],
        ),
      ]));
      expect(p.ingredients.single.subIngredients.single.rawText, 'INS 322');
    });

    test('v1.6 identification is null throughout — no engine exists', () {
      final ParsedLabel p = run(input(ingredients: <IngredientToken>[
        token(
          1,
          'Emulsifier',
          children: <IngredientToken>[token(1, 'INS 322')],
        ),
      ]));
      expect(p.ingredients.single.identification, isNull);
      expect(p.ingredients.single.subIngredients.single.identification, isNull);
    });

    test('ADR-0009 each ingredient carries provenance from its token', () {
      final ParsedLabel p = run(input(ingredients: <IngredientToken>[
        token(1, 'Wheat flour', strength: ParseStrength.heuristic),
      ]));
      final Provenance pr = p.ingredients.single.provenance;
      expect(pr.origin, FieldOrigin.extracted);
      expect(pr.producedByStage, PipelineStage.tokenisation);
      expect(pr.parseStrength, ParseStrength.heuristic);
      expect(pr.sourceRegion, box(0, 0, 10, 10));
      expect(pr.rulePackVersion, pack);
    });
  });

  group('Assembly — the rest of the contract', () {
    test('FR-CNF-04 invariant results pass through unchanged', () {
      final InvariantResult r = InvariantResult(
        invariantId: InvariantId.inv02,
        outcome: InvariantOutcome.inapplicable,
        basis: Basis.per100g,
        participatingFields: const <InvariantSubject>[
          NutrientSubject(NutrientId.saturatedFat),
        ],
      );
      expect(run(input(results: <InvariantResult>[r])).invariantResults,
          <InvariantResult>[r]);
    });

    test('FR-CNF-07 the scan level passes through unchanged', () {
      expect(run(input(scan: ScanConfidence.low)).scanConfidence,
          ScanConfidence.low);
    });

    test('FR-KB-02 the rule pack version is recorded', () {
      expect(run(input()).rulePackVersion, pack);
    });

    test('FR-CAT-02 category is carried, never determined', () {
      expect(run(input()).declaredCategory, isNull);
      final ParsedLabel p = run(input(), category: CategoryId('cat.biscuits'));
      expect(p.declaredCategory, CategoryId('cat.biscuits'));
    });

    test('D4 unsupportedScript is stored, never inferred', () {
      expect(run(input()).unsupportedScript, isFalse);
      expect(run(input(), unsupported: true).unsupportedScript, isTrue);
    });

    test('FR-PAR-02 repeated assembly of one input is identical', () {
      final ScoredFields s = input(
        fields: <ScoredField>[
          scored(NutrientId.protein),
          scored(NutrientId.sodium),
        ],
        ingredients: <IngredientToken>[token(1, 'Sugar')],
      );
      expect(run(s).nutrients, run(s).nutrients);
      expect(run(s).ingredients, run(s).ingredients);
      expect(run(s).toString(), run(s).toString());
    });
  });
}
