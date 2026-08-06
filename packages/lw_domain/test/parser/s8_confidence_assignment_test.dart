import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  int nextIndex = 0;
  final Version pack = Version(1, 0, 0);

  TypedField typed(
    NutrientId nutrient, {
    Basis basis = Basis.per100g,
    ParseStrength label = ParseStrength.exact,
    ParseStrength basisStrength = ParseStrength.exact,
    ParseStrength unit = ParseStrength.exact,
    bool unitExpected = true,
  }) =>
      TypedField(
        nutrient: nutrient,
        quantity: const Quantity.exact(800, Unit.gram),
        basis: basis,
        labelStrength: label,
        basisStrength: basisStrength,
        unitStrength: unit,
        unitWasExpected: unitExpected,
        region: box(0, 0, 100, 60),
        sourceIndices: <int>[nextIndex++],
        matchedBy: RuleId('rule.resolve.synonym'),
      );

  InvariantResult check(
    InvariantOutcome outcome, {
    NutrientId nutrient = NutrientId.protein,
    Basis? basis = Basis.per100g,
    InvariantId id = InvariantId.inv02,
  }) =>
      InvariantResult(
        invariantId: id,
        outcome: outcome,
        basis: basis,
        participatingFields: <InvariantSubject>[NutrientSubject(nutrient)],
      );

  ValidatedFields input({
    List<TypedField> fields = const <TypedField>[],
    List<InvariantResult> results = const <InvariantResult>[],
    List<UnresolvedCandidate> unresolved = const <UnresolvedCandidate>[],
    List<IngredientToken> ingredients = const <IngredientToken>[],
    ServingFacts serving = ServingFacts.none,
  }) =>
      ValidatedFields(
        fields: fields,
        results: results,
        unresolved: unresolved,
        ingredientTokens: ingredients,
        serving: serving,
        nutritionPanelPresent: true,
        ingredientListPresent: ingredients.isNotEmpty,
      );

  ScoredFields run(ValidatedFields v, {ConfidencePolicy? policy}) {
    final StageResult<ScoredFields> out =
        assignConfidence(v, rulePackVersion: pack, policy: policy);
    expect(out.isSuccess, isTrue, reason: 'expected S8 success');
    return out.valueOrNull!;
  }

  setUp(() => nextIndex = 0);

  group('S8 — failure paths are values, not exceptions (FR-PAR-17)', () {
    test('FR-PAR-17 nothing supplied yields regionNotFound', () {
      final StageResult<ScoredFields> out =
          assignConfidence(ValidatedFields(), rulePackVersion: pack);
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
      expect(out.failureOrNull!.stage, PipelineStage.confidenceAssignment);
    });
  });

  group('S8 — the policy decides, the stage only orchestrates', () {
    test('ADR-0010 an exact parse with no failure earns HIGH', () {
      final ScoredFields s = run(input(fields: <TypedField>[
        typed(NutrientId.protein),
      ]));
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.high);
    });

    test('ADR-0010 a normalised parse earns MEDIUM', () {
      final ScoredFields s = run(input(fields: <TypedField>[
        typed(NutrientId.protein, label: ParseStrength.normalised),
      ]));
      expect(s.confidenceFor(NutrientId.protein, Basis.per100g),
          Confidence.medium);
    });

    test('ADR-0010 a heuristic parse earns LOW', () {
      final ScoredFields s = run(input(fields: <TypedField>[
        typed(NutrientId.protein, label: ParseStrength.heuristic),
      ]));
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.low);
    });

    test('ADR-0012 the stage makes no decision the policy did not', () {
      // An empty policy classifies everything by its fail-safe. If the stage
      // held any judgement of its own, some field would escape this.
      final ScoredFields s = run(
        input(fields: <TypedField>[
          typed(NutrientId.protein),
          typed(NutrientId.sodium, label: ParseStrength.normalised),
        ]),
        policy: ConfidencePolicy(const <ConfidenceRule>[]),
      );
      expect(
        s.fields.map((ScoredField f) => f.confidence),
        <Confidence>[Confidence.low, Confidence.low],
      );
    });

    test('ADR-0013 a caller-supplied policy replaces the default wholesale',
        () {
      final ScoredFields s = run(
        input(fields: <TypedField>[typed(NutrientId.protein)]),
        policy: ConfidencePolicy(<ConfidenceRule>[
          ConfidenceRule(
              parseStrength: ParseStrength.exact, result: Confidence.medium),
        ]),
      );
      expect(s.confidenceFor(NutrientId.protein, Basis.per100g),
          Confidence.medium);
    });
  });

  group('S8 — FR-CNF-05 is absolute', () {
    test('FR-CNF-05 a failed invariant caps an exact parse to LOW', () {
      // Whatever S1 and S2 say. The arithmetic outranks the parse because it
      // catches the failure that actually harms users — a misread digit.
      final ScoredFields s = run(input(
        fields: <TypedField>[typed(NutrientId.protein)],
        results: <InvariantResult>[check(InvariantOutcome.failed)],
      ));
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.low);
    });

    test('FR-CNF-05 only the fields that took part are capped', () {
      // A clean sodium reading must not be penalised for a protein failure it
      // took no part in.
      final ScoredFields s = run(input(
        fields: <TypedField>[
          typed(NutrientId.protein),
          typed(NutrientId.sodium),
        ],
        results: <InvariantResult>[check(InvariantOutcome.failed)],
      ));
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.low);
      expect(
          s.confidenceFor(NutrientId.sodium, Basis.per100g), Confidence.high);
    });

    test('FR-CNF-05 a per-serve failure does not cap the per-100 g field', () {
      // The reason InvariantResult gained a basis in DATA_MODEL v1.5.
      final ScoredFields s = run(input(
        fields: <TypedField>[
          typed(NutrientId.protein),
          typed(NutrientId.protein, basis: Basis.perServe),
        ],
        results: <InvariantResult>[
          check(InvariantOutcome.failed, basis: Basis.perServe),
        ],
      ));
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.high);
      expect(
          s.confidenceFor(NutrientId.protein, Basis.perServe), Confidence.low);
    });

    test('FR-CNF-05 a failure with no basis caps every basis', () {
      // INV-09 and INV-10 are facts about the pack, not about a column.
      final ScoredFields s = run(input(
        fields: <TypedField>[
          typed(NutrientId.protein),
          typed(NutrientId.protein, basis: Basis.perServe),
        ],
        results: <InvariantResult>[
          check(InvariantOutcome.failed, basis: null, id: InvariantId.inv09),
        ],
      ));
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.low);
      expect(
          s.confidenceFor(NutrientId.protein, Basis.perServe), Confidence.low);
    });

    test('FR-CNF-14 an indeterminate invariant does not cap', () {
      // A label that declared a bound has not been caught out.
      final ScoredFields s = run(input(
        fields: <TypedField>[typed(NutrientId.protein)],
        results: <InvariantResult>[check(InvariantOutcome.indeterminate)],
      ));
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.high);
    });

    test('FR-CNF-04 an inapplicable invariant does not cap', () {
      final ScoredFields s = run(input(
        fields: <TypedField>[typed(NutrientId.protein)],
        results: <InvariantResult>[check(InvariantOutcome.inapplicable)],
      ));
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.high);
    });
  });

  group('S8 — signal gathering (ARCHITECTURE 7.1, 7.2)', () {
    test('FR-CNF-02 only the invariants this field joined reach its signals',
        () {
      final ScoredFields s = run(input(
        fields: <TypedField>[typed(NutrientId.protein)],
        results: <InvariantResult>[
          check(InvariantOutcome.passed),
          check(InvariantOutcome.failed, nutrient: NutrientId.sodium),
        ],
      ));
      expect(s.fields.single.signals.s3InvariantResults, hasLength(1));
      expect(s.fields.single.signals.anyInvariantFailed, isFalse);
    });

    test('ARCHITECTURE 7.1 S2 is the weakest of the three parse strengths', () {
      // Propagation is the meet: a value can never be more confident than its
      // least confident input. An exact label read from a heuristic column
      // heading is a heuristic reading of that value.
      final ScoredFields s = run(input(fields: <TypedField>[
        typed(NutrientId.protein, basisStrength: ParseStrength.heuristic),
      ]));
      expect(s.fields.single.signals.s2ParseStrength, ParseStrength.heuristic);
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.low);
    });

    test('DATA_MODEL 7.4 an unexpected unit weakens the signal, not the parse',
        () {
      // The unit is readable and the value survives; what falls is how firmly
      // it was read. An unusual label is not the same thing as a misread one.
      final ScoredFields s = run(input(fields: <TypedField>[
        typed(NutrientId.protein, unitExpected: false),
      ]));
      expect(s.fields.single.signals.s2ParseStrength, ParseStrength.heuristic);
      expect(s.fields, hasLength(1), reason: 'the field is kept, not dropped');
    });

    test('FR-CNF-03 S1 is recorded absent, never defaulted', () {
      // The Q2 spike has not run and S4 does not carry OCR confidence forward.
      // ARCHITECTURE 7.2 requires the model to work without it and to say so.
      final ScoredFields s = run(input(fields: <TypedField>[
        typed(NutrientId.protein),
      ]));
      expect(s.fields.single.signals.s1OcrConfidence, isNull);
      expect(s.fields.single.signals.s1WasAvailable, isFalse);
    });
  });

  group('S8 — provenance and the value itself (ADR-0009)', () {
    test('FR-PAR-13 provenance records stage, rule, strength and position', () {
      final ScoredField f = run(input(fields: <TypedField>[
        typed(NutrientId.protein, label: ParseStrength.normalised),
      ])).fields.single;
      final ExtractedField e = f.state as ExtractedField;
      expect(e.provenance.producedByStage, PipelineStage.confidenceAssignment);
      expect(e.provenance.parseRuleId, RuleId('rule.resolve.synonym'));
      expect(e.provenance.parseStrength, ParseStrength.normalised);
      expect(e.provenance.sourceRegion, box(0, 0, 100, 60));
    });

    test('FR-KB-02 provenance records the rule pack in force', () {
      final ScoredField f =
          run(input(fields: <TypedField>[typed(NutrientId.protein)]))
              .fields
              .single;
      expect((f.state as ExtractedField).provenance.rulePackVersion, pack);
    });

    test('FR-PAR-01 the value and basis cross the stage unchanged', () {
      // S8 judges; it does not correct. Adjusting a value here would replace
      // the manufacturer's claim with our guess.
      final ScoredField f =
          run(input(fields: <TypedField>[typed(NutrientId.protein)]))
              .fields
              .single;
      expect(f.state.quantityOrNull, const Quantity.exact(800, Unit.gram));
      expect(f.state.basisOrNull, Basis.per100g);
    });

    test('FR-PAR-13 source indices survive the stage', () {
      final ScoredFields s = run(input(fields: <TypedField>[
        typed(NutrientId.protein),
        typed(NutrientId.sodium),
      ]));
      expect(s.fields[0].sourceIndices, <int>[0]);
      expect(s.fields[1].sourceIndices, <int>[1]);
    });
  });

  group('S8 — the scan level (DATA_MODEL 4.5)', () {
    ServingFacts facts() => const ServingFacts(
          servingSize: Quantity.exact(3000, Unit.gram),
          servingsPerPack: Quantity.exact(400, Unit.count),
          netQuantity: Quantity.exact(12000, Unit.gram),
        );

    List<TypedField> everyCritical({
      ParseStrength label = ParseStrength.exact,
    }) =>
        <TypedField>[
          for (final NutrientId n in NutrientId.critical)
            typed(n, label: label),
        ];

    test('FR-ERR-03 an unread critical field makes the scan PARTIAL', () {
      final ScoredFields s = run(input(fields: <TypedField>[
        typed(NutrientId.protein),
      ]));
      expect(s.scanConfidence, ScanConfidence.partial);
    });

    test('DATA_MODEL 4.5 absent serving figures also make it PARTIAL', () {
      // Serving size, servings per pack and net quantity are critical fields
      // (DATA_MODEL 5.3), and none of them is produced by the pipeline yet.
      final ScoredFields s = run(input(fields: everyCritical()));
      expect(s.scanConfidence, ScanConfidence.partial);
    });

    test('DATA_MODEL 4.5 a complete, clean scan reports HIGH', () {
      final ScoredFields s =
          run(input(fields: everyCritical(), serving: facts()));
      expect(s.scanConfidence, ScanConfidence.high);
    });

    test('DATA_MODEL 4.5 two failed invariants make the scan LOW', () {
      final ScoredFields s = run(input(
        fields: everyCritical(),
        serving: facts(),
        results: <InvariantResult>[
          check(InvariantOutcome.failed, nutrient: NutrientId.protein),
          check(InvariantOutcome.failed,
              nutrient: NutrientId.sodium, id: InvariantId.inv03),
        ],
      ));
      expect(s.scanConfidence, ScanConfidence.low);
    });

    test('DATA_MODEL 4.5 one LOW critical field makes the scan LOW', () {
      final ScoredFields s = run(input(
        fields: everyCritical(label: ParseStrength.heuristic),
        serving: facts(),
      ));
      expect(s.scanConfidence, ScanConfidence.low);
    });

    test('MI-10 the scan level is not a field Confidence', () {
      final ScoredFields s =
          run(input(fields: everyCritical(), serving: facts()));
      expect(s.scanConfidence, isA<ScanConfidence>());
      expect(s.scanConfidence, isNot(isA<Confidence>()));
    });
  });

  group('S8 — everything else crosses the stage untouched', () {
    test('FR-ERR-03 unresolved candidates pass through', () {
      final UnresolvedCandidate u = UnresolvedCandidate(
        reason: UnresolvedReason.noMatchingRule,
        labelText: 'Riboflavin',
        region: box(0, 0, 10, 10),
        sourceIndices: const <int>[9],
      );
      expect(run(input(unresolved: <UnresolvedCandidate>[u])).unresolved,
          <UnresolvedCandidate>[u]);
    });

    test('FR-CNF-04 every invariant result passes through', () {
      final InvariantResult r = check(InvariantOutcome.inapplicable);
      expect(run(input(results: <InvariantResult>[r])).invariantResults,
          <InvariantResult>[r]);
    });

    test('FR-PAR-10 ingredient tokens pass through', () {
      final IngredientToken t = IngredientToken(
        position: 1,
        rawText: 'Wheat flour',
        region: box(0, 0, 10, 10),
        sourceIndices: const <int>[5],
        parseStrength: ParseStrength.exact,
      );
      expect(run(input(ingredients: <IngredientToken>[t])).ingredientTokens,
          <IngredientToken>[t]);
    });

    test('FR-PAR-13 the output records the stage that produced it', () {
      expect(
          run(input(fields: <TypedField>[typed(NutrientId.protein)]))
              .producedByStage,
          PipelineStage.confidenceAssignment);
    });

    test('FR-CNF-06 repeated assignment of one input is identical', () {
      final ValidatedFields v = input(
        fields: <TypedField>[
          typed(NutrientId.protein),
          typed(NutrientId.sodium, label: ParseStrength.normalised),
        ],
        results: <InvariantResult>[check(InvariantOutcome.failed)],
      );
      expect(run(v).fields, run(v).fields);
      expect(run(v).scanConfidence, run(v).scanConfidence);
      expect(run(v).sourceIndices, run(v).sourceIndices);
    });
  });
}
