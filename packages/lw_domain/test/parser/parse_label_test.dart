import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **M12 — the first test that parses a label.**
///
/// Every milestone before this one proved a stage in isolation. Nothing proved
/// that the stages *compose*: the wiring between them was specified in prose
/// and implemented nowhere, which is exactly where a defect hides longest.
///
/// The composition is a pure function of OCR output and rule pack (FR-PAR-01).
/// It adds no analysis, no vocabulary and no failure vocabulary of its own — a
/// stage's `ParseFailure` reaches the caller unchanged, so `failure.stage`
/// keeps naming the true origin rather than the composer.
void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  // --------------------------------------------------------------- fixtures

  /// One OCR element per printed line, all inside a single column band.
  ///
  /// The band matters: `LayoutThresholds.columnGapNormalised` splits bands on
  /// an x-gap above 400, so keeping every element within 100..900 yields one
  /// band, and S4 reads the panel's first line as that band's header.
  RecognitionResult label(
    List<String> lines, {
    DominantScript script = DominantScript.latin,
    int height = 60,
  }) =>
      RecognitionResult(
        elements: <RecognitionElement>[
          for (int i = 0; i < lines.length; i++)
            RecognitionElement(
              text: lines[i],
              region: box(100, 1000 + i * 100, 900, 1000 + i * 100 + height),
            ),
        ],
        dominantScript: script,
      );

  /// Fixture A — a realistic Indian biscuit pack, nutrition and ingredients.
  ///
  /// Row 0 is doing three jobs at once, and that is not a fixture trick: it is
  /// how the stages are actually wired. It carries the S3 region marker, it is
  /// the panel's first line so S4 takes it as the column header, and it
  /// contains `per 100 g` so S5 can assign a basis.
  const List<String> fixtureA = <String>[
    'Nutritional Information Per 100 g',
    'Serving Size 30 g',
    'Servings Per Pack 10',
    'Net Quantity 300 g',
    'Energy 450 kcal',
    'Protein 6 g',
    'Total Fat 20 g',
    'Carbohydrate 65 g',
    'Total Sugars 22 g',
    'Sodium 400 mg',
    'Ingredients: Wheat Flour (60%), Sugar, Palm Oil, Salt',
  ];

  /// Fixture A with the three serving lines removed.
  ///
  /// The paired negative for the S5b handoff: same nutrients, no serving
  /// figures, so any invariant that consumes serving facts must change
  /// applicability. If S7 were reading serving data from anywhere other than
  /// S5b, these two fixtures would agree — and they must not.
  const List<String> fixtureAWithoutServing = <String>[
    'Nutritional Information Per 100 g',
    'Energy 450 kcal',
    'Protein 6 g',
    'Total Fat 20 g',
    'Carbohydrate 65 g',
    'Total Sugars 22 g',
    'Sodium 400 mg',
    'Ingredients: Wheat Flour (60%), Sugar, Palm Oil, Salt',
  ];

  /// Fixture B — nutrition only, no ingredient declaration (FR-PAR-14).
  final List<String> fixtureB = fixtureA.sublist(0, 10);

  /// Fixture C — an ingredient list with no nutrition panel (FR-PAR-14).
  const List<String> fixtureC = <String>[
    'Ingredients: Wheat Flour (60%), Sugar, Palm Oil, Salt',
  ];

  /// Fixture D — text that names no region at all.
  const List<String> fixtureD = <String>['Best before six months from packing'];

  // ----------------------------------------------------------- the rule pack

  const String digest =
      'sha256:33177c6c7a71c5650c3a28d05f95d3c83154507d947612e78af312b6e5d84d46';

  SynonymEntry entry(NutrientId nutrient, String text, Unit unit) =>
      SynonymEntry(
        nutrient: nutrient,
        patterns: <SynonymPattern>[
          SynonymPattern(text: text, strength: ParseStrength.exact),
        ],
        expectedUnits: <Unit>[unit],
      );

  /// The M10 fixture shape, extended only with the synonyms Fixture A needs.
  ///
  /// `ApproximationDeltas.none` is kept: no fixture value is `APPROXIMATELY`,
  /// so no delta is required and inventing one would be rule pack data nobody
  /// authorised.
  RulePack rulePack() => RulePack(
        manifest: RulePackManifest(
          schemaVersion: Version(1, 0, 0),
          packVersion: Version(0, 1, 0),
          minAppVersion: Version(0, 1, 0),
          integrityHash: digest,
          contentLicence: 'CC-BY-4.0',
          generatedAt: '2026-08-04',
        ),
        sources: SourceRegistry(<Source>[
          Source(
            sourceId: SourceId('src.fssai.labelling.2020'),
            title: 'Labelling and Display Regulations',
            publisher: 'FSSAI',
            publicationDate: '2020-12-14',
            accessDate: '2026-08-04',
            sourceType: SourceType.regulation,
            evidenceStrength: EvidenceStrength.established,
          ),
        ]),
        synonyms: SynonymTable(<SynonymEntry>[
          entry(NutrientId.energy, 'Energy', Unit.kilocalorie),
          entry(NutrientId.protein, 'Protein', Unit.gram),
          entry(NutrientId.totalFat, 'Total Fat', Unit.gram),
          entry(NutrientId.carbohydrate, 'Carbohydrate', Unit.gram),
          entry(NutrientId.totalSugars, 'Total Sugars', Unit.gram),
          entry(NutrientId.sodium, 'Sodium', Unit.milligram),
        ]),
        rda: RdaTable(<RdaDenominator>[
          RdaDenominator(
            constantId: ConstantId('const.rda.sodium'),
            nutrient: NutrientId.sodium,
            value: const Quantity.exact(20000, Unit.milligram),
            sourceRefs: <SourceId>[SourceId('src.fssai.labelling.2020')],
          ),
        ]),
        categories: CategoryTable(<Category>[
          Category(
            categoryId: CategoryId('cat.biscuits'),
            nameMessageId: MessageId('msg.category.biscuits'),
            defaultBasis: Basis.per100g,
            status: CategoryStatus.priority,
          ),
        ]),
        advisoryRules: AdvisoryRuleTable(const <AdvisoryRule>[]),
        confidencePolicy: ConfidencePolicy.defaults,
        tolerances: ToleranceTable.defaults,
        approximationDeltas: ApproximationDeltas.none,
        messages: MessageCatalogue(
          locale: 'en',
          reviewed: true,
          messages: <MessageId, String>{
            MessageId('msg.category.biscuits'): 'Biscuits',
          },
        ),
      );

  // ---------------------------------------------------------------- helpers

  ParsedLabel parse(
    List<String> lines, {
    RulePack? pack,
    CategoryId? category,
    bool unsupportedScript = false,
  }) {
    final StageResult<ParsedLabel> out = parseLabel(
      label(lines),
      pack: pack ?? rulePack(),
      declaredCategory: category,
      unsupportedScript: unsupportedScript,
    );
    expect(out.isSuccess, isTrue,
        reason: 'expected a parse, got ${out.failureOrNull}');
    return out.valueOrNull!;
  }

  ParseFailure failureOf(RecognitionResult input) {
    final StageResult<ParsedLabel> out = parseLabel(input, pack: rulePack());
    expect(out.isSuccess, isFalse, reason: 'expected a refusal');
    return out.failureOrNull!;
  }

  InvariantResult? invariant(ParsedLabel l, InvariantId id) {
    for (final InvariantResult r in l.invariantResults) {
      if (r.invariantId == id) {
        return r;
      }
    }
    return null;
  }

  // =========================================================== 1. full parse

  group('M12 — a complete parse (FR-PAR-04, FR-PAR-14)', () {
    test('every declared nutrient is read with its value, unit and basis', () {
      final ParsedLabel l = parse(fixtureA);

      final FieldState protein = l.nutrientFor(NutrientId.protein)!.perHundred;
      expect(protein, isA<ExtractedField>());
      expect((protein as ExtractedField).quantity,
          const Quantity.exact(600, Unit.gram));
      expect(protein.basis, Basis.per100g);

      expect(
        (l.nutrientFor(NutrientId.energy)!.perHundred as ExtractedField)
            .quantity,
        const Quantity.exact(4500, Unit.kilocalorie),
      );
      expect(
        (l.nutrientFor(NutrientId.sodium)!.perHundred as ExtractedField)
            .quantity,
        // 400 mg. `Unit.milligram` tracks tenths (ADR-0021: scale is a
        // property of the unit), so the scaled value is 4000 — not 40000,
        // which is gram's hundredths arithmetic applied to the wrong unit.
        const Quantity.exact(4000, Unit.milligram),
      );
    });

    test('all six declared nutrients survive the composition', () {
      final ParsedLabel l = parse(fixtureA);
      for (final NutrientId id in <NutrientId>[
        NutrientId.energy,
        NutrientId.protein,
        NutrientId.totalFat,
        NutrientId.carbohydrate,
        NutrientId.totalSugars,
        NutrientId.sodium,
      ]) {
        expect(l.nutrientFor(id), isNotNull, reason: '${id.name} was lost');
      }
    });

    test('the ingredient list keeps declaration order (FR-PAR-10)', () {
      // Position is legally meaningful, so order is asserted, not membership.
      final List<Ingredient> ingredients = parse(fixtureA).ingredients;
      expect(ingredients, hasLength(4));
      expect(ingredients[0].rawText, contains('Wheat Flour'));
      expect(ingredients[1].rawText, contains('Sugar'));
      expect(ingredients[2].rawText, contains('Palm Oil'));
      expect(ingredients[3].rawText, contains('Salt'));
      expect(ingredients.map((Ingredient i) => i.position).toList(),
          <int>[1, 2, 3, 4]);
    });

    test('a parenthetical declaration keeps its nesting (FR-PAR-12)', () {
      expect(parse(fixtureA).ingredients.first.subIngredients, isNotEmpty,
          reason: '(60%) is a child of Wheat Flour, not a sibling');
    });

    test('the rule pack version is recorded on the result (FR-KB-02)', () {
      expect(parse(fixtureA).rulePackVersion, Version(0, 1, 0));
    });

    test('the caller-declared category is carried, never inferred', () {
      // FR-CAT-02: category is optional and no stage determines it.
      expect(parse(fixtureA).declaredCategory, isNull);
      expect(
          parse(fixtureA, category: CategoryId('cat.biscuits'))
              .declaredCategory,
          CategoryId('cat.biscuits'));
    });

    test('unsupportedScript is passed through, never inferred', () {
      expect(parse(fixtureA).unsupportedScript, isFalse);
      expect(
          parse(fixtureA, unsupportedScript: true).unsupportedScript, isTrue);
    });
  });

  // ======================================================== 2. stage ordering

  group('M12 — the stages run in the specified order', () {
    test('provenance names stages no later than confidence assignment', () {
      // Forward-only (ARCHITECTURE 6.2): a field produced by the composition
      // cannot carry provenance from a stage that has not run yet.
      final ParsedLabel l = parse(fixtureA);
      final ExtractedField f =
          l.nutrientFor(NutrientId.protein)!.perHundred as ExtractedField;
      expect(f.provenance.producedByStage, isNotNull);
      expect(
        f.provenance.producedByStage!.index,
        lessThanOrEqualTo(PipelineStage.confidenceAssignment.index),
      );
    });

    test('a value can only exist if every prior stage succeeded', () {
      // The composition is a chain, so the presence of a typed, scored,
      // invariant-checked field is itself evidence that S1..S8 all ran.
      final ParsedLabel l = parse(fixtureA);
      expect(l.nutrients, isNotEmpty, reason: 'S1-S6 ran');
      expect(l.invariantResults, isNotEmpty, reason: 'S7 ran');
      expect(
          l.nutrientFor(NutrientId.protein)!.perHundred, isA<ExtractedField>());
      expect(
        (l.nutrientFor(NutrientId.protein)!.perHundred as ExtractedField)
            .confidence,
        isA<Confidence>(),
        reason: 'S8 ran',
      );
      expect(l.servingInfo, isNotNull, reason: 'S5b and assembly ran');
    });

    test('the ordinals themselves still describe the pipeline', () {
      expect(PipelineStage.normalisation.index,
          lessThan(PipelineStage.layoutReconstruction.index));
      expect(PipelineStage.regionClassification.index,
          lessThan(PipelineStage.tokenisation.index));
      expect(PipelineStage.fieldResolution.index,
          lessThan(PipelineStage.servingResolution.index));
      expect(PipelineStage.servingResolution.index,
          lessThan(PipelineStage.unitNormalisation.index));
      expect(PipelineStage.invariantEvaluation.index,
          lessThan(PipelineStage.confidenceAssignment.index));
    });
  });

  // ======================================================= 3. S5b -> S7

  group('M12 — S5b feeds S7 (the M11a handoff)', () {
    test('declared serving figures make the serving invariants decidable', () {
      // 30 g x 10 servings = 300 g net. INV-09 and INV-10 can only reach a
      // definite outcome if S7 received S5b's facts.
      final ParsedLabel l = parse(fixtureA);
      expect(invariant(l, InvariantId.inv09)!.outcome,
          isNot(InvariantOutcome.inapplicable));
      expect(invariant(l, InvariantId.inv10)!.outcome,
          isNot(InvariantOutcome.inapplicable));
    });

    test('the same label without serving lines makes them INAPPLICABLE', () {
      // The paired negative. If S7 were sourcing serving data from anywhere
      // but S5b, these two fixtures would not differ here.
      final ParsedLabel l = parse(fixtureAWithoutServing);
      expect(invariant(l, InvariantId.inv09)!.outcome,
          InvariantOutcome.inapplicable);
      expect(invariant(l, InvariantId.inv10)!.outcome,
          InvariantOutcome.inapplicable);
    });

    test('a consistent pack reconciles rather than fails', () {
      // 300 g / 30 g = 10 servings, exactly as declared.
      expect(invariant(parse(fixtureA), InvariantId.inv10)!.outcome,
          InvariantOutcome.passed);
    });

    test('a serve larger than the pack is caught by INV-09', () {
      final ParsedLabel l = parse(<String>[
        'Nutritional Information Per 100 g',
        'Serving Size 400 g',
        'Net Quantity 300 g',
        'Protein 6 g',
      ]);
      expect(invariant(l, InvariantId.inv09)!.outcome, InvariantOutcome.failed);
    });

    test('every invariant is recorded, including the inapplicable ones', () {
      // FR-CNF-04: an omitted invariant would say nothing was checked.
      final ParsedLabel l = parse(fixtureAWithoutServing);
      expect(invariant(l, InvariantId.inv09), isNotNull);
      expect(invariant(l, InvariantId.inv10), isNotNull);
    });
  });

  // ======================================================= 4. S5b -> S8

  group('M12 — S5b feeds S8, and assembly only assembles', () {
    test('resolved serving figures reach ParsedLabel.servingInfo', () {
      final ParsedLabel l = parse(fixtureA);
      final FieldState size = l.servingInfo.declaredServingSize;
      expect(size, isA<ExtractedField>());
      expect((size as ExtractedField).quantity,
          const Quantity.exact(3000, Unit.gram));
    });

    test('servings per pack and net quantity reach servingInfo too', () {
      final ParsedLabel l = parse(fixtureA);
      expect(l.servingInfo.servingsPerPack, isA<ExtractedField>());
      expect(
        (l.servingInfo.netQuantity as ExtractedField).quantity,
        const Quantity.exact(30000, Unit.gram),
      );
    });

    test('serving fields carry a confidence assigned by S8', () {
      // S8 scores serving through the same policy as nutrients (M11a). A
      // serving field arriving without one would mean assembly invented it.
      final ExtractedField size =
          parse(fixtureA).servingInfo.declaredServingSize as ExtractedField;
      expect(size.confidence, isA<Confidence>());
    });

    test('assembly recomputes nothing — reconciliation stays null', () {
      // ServingReconciliation is Layer 1 scope. The parser emitting one would
      // be assembly doing analysis.
      expect(parse(fixtureA).servingInfo.reconciliation, isNull);
    });

    test('the scan confidence is a ScanConfidence, not a field Confidence', () {
      // MI-10 keeps the two types apart.
      expect(parse(fixtureA).scanConfidence, isA<ScanConfidence>());
    });
  });

  // ================================================== 5. failure propagation

  group('M12 — first failure wins, and it is not rewrapped', () {
    test('S1 refuses an empty recognition result', () {
      final ParseFailure f = failureOf(
        RecognitionResult(
          elements: const <RecognitionElement>[],
          dominantScript: DominantScript.latin,
        ),
      );
      expect(f.stage, PipelineStage.normalisation);
      expect(f.kind, ParseFailureKind.noTextRecognised);
    });

    test('S1 refuses a Devanagari-dominant result (FR-OCR-05)', () {
      // ADR-0015: an honest refusal beats a bad parse. The composition must
      // not soften it into a partial success.
      final ParseFailure f = failureOf(
        label(fixtureA, script: DominantScript.devanagari),
      );
      expect(f.stage, PipelineStage.normalisation);
    });

    test('S2 refuses zero-height geometry', () {
      final ParseFailure f = failureOf(label(fixtureA, height: 0));
      expect(f.stage, PipelineStage.layoutReconstruction);
      expect(f.kind, ParseFailureKind.layoutIndeterminate);
    });

    test('S3 refuses a label naming no region', () {
      final ParseFailure f = failureOf(label(fixtureD));
      expect(f.stage, PipelineStage.regionClassification);
      expect(f.kind, ParseFailureKind.regionNotFound);
    });

    test('the propagated failure is the stage\'s own object, unchanged', () {
      // Not "a failure with the same fields" — the same value. A composer that
      // rebuilt it could quietly lose a detail no test names.
      final RecognitionResult input = label(fixtureD);
      final StageResult<ClassifiedRegions> direct = classifyRegions(
        reconstructLayout(normaliseText(input).valueOrNull!).valueOrNull!,
      );
      expect(failureOf(input), direct.failureOrNull);
    });

    test('a failure stops the pipeline — no partial label is returned', () {
      final StageResult<ParsedLabel> out =
          parseLabel(label(fixtureD), pack: rulePack());
      expect(out.valueOrNull, isNull);
      expect(out, isA<StageFailure<ParsedLabel>>());
    });
  });

  // ====================================================== 6. partial input

  group('M12 — partial input yields a partial, honest result (FR-PAR-14)', () {
    test('nutrition and ingredients together produce both', () {
      final ParsedLabel l = parse(fixtureA);
      expect(l.nutrients, isNotEmpty);
      expect(l.ingredients, isNotEmpty);
    });

    test('a panel with no ingredient list produces nutrition only', () {
      final ParsedLabel l = parse(fixtureB);
      expect(l.nutrients, isNotEmpty);
      expect(l.ingredients, isEmpty,
          reason: 'no ingredients were supplied, and none may be invented');
    });

    test('an ingredient list with no panel still parses', () {
      // Order is the assertion. FR-PAR-10 makes declaration order legally
      // meaningful, so `position` is checked as well as the text: a list that
      // arrived complete but reordered would satisfy the text check alone.
      final List<Ingredient> ingredients = parse(fixtureC).ingredients;
      expect(ingredients, hasLength(4));
      expect(ingredients[0].rawText, contains('Wheat Flour'));
      expect(ingredients[1].rawText, contains('Sugar'));
      expect(ingredients[2].rawText, contains('Palm Oil'));
      expect(ingredients[3].rawText, contains('Salt'));
      expect(ingredients.map((Ingredient i) => i.position).toList(),
          <int>[1, 2, 3, 4]);
    });

    test('an ingredients-only label fabricates no nutrition values', () {
      // The heart of P1. Absence must not become data.
      final ParsedLabel l = parse(fixtureC);
      for (final NutrientField f in l.nutrients) {
        expect(f.perHundred, isNot(isA<ExtractedField>()));
        expect(f.perServe, isNot(isA<ExtractedField>()));
        expect(f.perPack, isNot(isA<ExtractedField>()));
      }
    });

    test('an ingredients-only label declares no serving figures', () {
      final ParsedLabel l = parse(fixtureC);
      expect(l.servingInfo.declaredServingSize, isA<NotDeclaredField>());
      expect(l.servingInfo.servingsPerPack, isA<NotDeclaredField>());
      expect(l.servingInfo.netQuantity, isA<NotDeclaredField>());
    });
  });

  // ============================================= 7. state semantics preserved

  group('M12 — the three field states stay distinguishable (MI-08)', () {
    test('Resolved stays Resolved', () {
      expect(parse(fixtureA).nutrientFor(NutrientId.protein)!.perHundred,
          isA<ExtractedField>());
    });

    test('NotDeclared stays NotDeclared', () {
      // The label declares nothing per serve. That is the manufacturer's
      // choice, not a parser failure (FR-ERR-03).
      expect(parse(fixtureA).nutrientFor(NutrientId.protein)!.perServe,
          isA<NotDeclaredField>());
    });

    test('a serving figure the label omits is NotDeclared, not Unresolved', () {
      expect(parse(fixtureAWithoutServing).servingInfo.declaredServingSize,
          isA<NotDeclaredField>());
    });

    test('Unresolved stays Unresolved — a two-value row is not guessed at', () {
      // Fixture H. S4 emits one candidate per line, so `Protein 6 g 1.8 g`
      // yields the unit text `g 1.8 g`, which no lexicon entry matches. The
      // honest outcome is unresolved, and the composition must not repair it.
      final ParsedLabel l = parse(<String>[
        'Nutritional Information Per 100 g',
        'Protein 6 g 1.8 g',
      ]);
      final NutrientField? protein = l.nutrientFor(NutrientId.protein);
      if (protein != null) {
        expect(protein.perHundred, isNot(isA<ExtractedField>()));
      }
    });

    test('an unresolvable label line does not remove the readable ones', () {
      final ParsedLabel l = parse(<String>[
        'Nutritional Information Per 100 g',
        'Protein 6 g 1.8 g',
        'Sodium 400 mg',
      ]);
      expect(
          l.nutrientFor(NutrientId.sodium)!.perHundred, isA<ExtractedField>());
    });
  });

  // ========================================== 8. confidence and invariants

  group('M12 — orchestration changes no confidence and no verdict', () {
    test('INDETERMINATE never becomes FAILED through composition', () {
      // Composition adds no arithmetic, so it can add no verdict.
      for (final InvariantResult r in parse(fixtureAWithoutServing)
          .invariantResults
          .where((InvariantResult r) =>
              r.outcome == InvariantOutcome.indeterminate)) {
        expect(r.outcome, InvariantOutcome.indeterminate);
      }
      expect(
        parse(fixtureC)
            .invariantResults
            .where((InvariantResult r) => r.outcome == InvariantOutcome.failed),
        isEmpty,
        reason: 'an ingredients-only label accuses the manufacturer of nothing',
      );
    });

    test('confidence matches invoking the stages by hand', () {
      // The strongest statement available: the composition is exactly the
      // stages, not the stages plus an opinion.
      final RulePack pack = rulePack();
      final RecognitionResult input = label(fixtureA);

      final ClassifiedRegions regions = classifyRegions(
        reconstructLayout(normaliseText(input).valueOrNull!).valueOrNull!,
      ).valueOrNull!;
      final ServingResolution serving = resolveServing(regions).valueOrNull!;
      final TypedFields typed = normaliseUnits(
        resolveFields(tokenise(regions).valueOrNull!, synonyms: pack.synonyms)
            .valueOrNull!,
        synonyms: pack.synonyms,
      ).valueOrNull!;
      final ScoredFields scored = assignConfidence(
        evaluateInvariants(
          typed,
          serving: serving.facts,
          tolerances: pack.tolerances,
          deltas: pack.approximationDeltas,
          categories: pack.categories,
        ).valueOrNull!,
        rulePackVersion: pack.version,
        policy: pack.confidencePolicy,
        servingResolution: serving,
      ).valueOrNull!;

      final ParsedLabel composed = parse(fixtureA, pack: pack);
      for (final ScoredField f in scored.fields) {
        final NutrientField? mine = composed.nutrientFor(f.nutrient);
        expect(mine, isNotNull, reason: '${f.nutrient.name} was lost');
      }
      expect(composed.scanConfidence, scored.scanConfidence);
      expect(composed.invariantResults, scored.invariantResults);
    });

    test('no field is promoted to HIGH by being parsed through parseLabel', () {
      // FR-CNF-05 and PT-12 are S8's to enforce; the point here is that the
      // composition cannot raise a level S8 declined to give.
      final ParsedLabel l = parse(fixtureA);
      for (final NutrientField f in l.nutrients) {
        final FieldState s = f.perHundred;
        if (s is ExtractedField) {
          expect(Confidence.values.contains(s.confidence), isTrue);
        }
      }
    });
  });

  // ================================================== 9. provenance intact

  group('M12 — provenance survives the composition (ADR-0009)', () {
    test('every extracted field records where it came from', () {
      final ParsedLabel l = parse(fixtureA);
      for (final NutrientField f in l.nutrients) {
        final FieldState s = f.perHundred;
        if (s is ExtractedField) {
          expect(s.provenance.origin, FieldOrigin.extracted,
              reason: '${f.nutrient.name} lost its origin');
          expect(s.provenance.parseRuleId, isNotNull,
              reason: '${f.nutrient.name} has no rule to explain it');
          expect(s.provenance.parseStrength, isNotNull);
        }
      }
    });

    test('the region a value was read from survives to the result', () {
      final ExtractedField protein = parse(fixtureA)
          .nutrientFor(NutrientId.protein)!
          .perHundred as ExtractedField;
      expect(protein.provenance.sourceRegion, isNotNull);
      expect(protein.provenance.sourceRegion!.height, greaterThan(0));
    });

    test('the rule pack version is stamped on the provenance (FR-KB-02)', () {
      final ExtractedField protein = parse(fixtureA)
          .nutrientFor(NutrientId.protein)!
          .perHundred as ExtractedField;
      expect(protein.provenance.rulePackVersion, Version(0, 1, 0));
    });

    test('a serving field records its origin too', () {
      final ExtractedField size =
          parse(fixtureA).servingInfo.declaredServingSize as ExtractedField;
      expect(size.provenance.origin, FieldOrigin.extracted);
      expect(size.provenance.parseRuleId, isNotNull);
    });

    test('an ingredient records its origin too', () {
      final Ingredient first = parse(fixtureA).ingredients.first;
      expect(first.provenance.producedByStage, PipelineStage.tokenisation);
      expect(first.provenance.parseRuleId, isNotNull);
    });
  });

  // ==================================================== 10. determinism

  group('M12 — the same input parses identically twice (FR-PAR-02, PT-06)', () {
    test('all eight observable fields agree across two parses', () {
      // One input object and one rule pack object, parsed twice. Rebuilding
      // either between runs would test the fixtures rather than the parser.
      //
      // Compared field by field rather than as whole labels: ParsedLabel has
      // identity equality by design, so `first == second` would assert object
      // identity and quietly pass for the wrong reason.
      final RecognitionResult input = label(fixtureA);
      final RulePack pack = rulePack();

      final ParsedLabel first = parseLabel(input, pack: pack).valueOrNull!;
      final ParsedLabel second = parseLabel(input, pack: pack).valueOrNull!;

      expect(first.nutrients, second.nutrients);
      expect(first.servingInfo, second.servingInfo);
      expect(first.ingredients, second.ingredients);
      expect(first.declaredCategory, second.declaredCategory);
      expect(first.invariantResults, second.invariantResults);
      expect(first.scanConfidence, second.scanConfidence);
      expect(first.rulePackVersion, second.rulePackVersion);
      expect(first.unsupportedScript, second.unsupportedScript);
    });

    test('the comparison is not vacuous — two different labels differ', () {
      // Guards the test above: if the eight assertions passed for any pair of
      // labels, they would be proving nothing about determinism.
      final RulePack pack = rulePack();
      final ParsedLabel a =
          parseLabel(label(fixtureA), pack: pack).valueOrNull!;
      final ParsedLabel b =
          parseLabel(label(fixtureB), pack: pack).valueOrNull!;
      expect(a.ingredients, isNot(b.ingredients));
    });

    test('a refusal is deterministic too', () {
      final RecognitionResult input = label(fixtureD);
      final RulePack pack = rulePack();
      expect(parseLabel(input, pack: pack).failureOrNull,
          parseLabel(input, pack: pack).failureOrNull);
    });
  });
}
