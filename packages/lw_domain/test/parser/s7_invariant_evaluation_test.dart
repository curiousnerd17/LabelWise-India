import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  int nextIndex = 0;

  TypedField field(
    NutrientId nutrient,
    Quantity value, {
    Basis basis = Basis.per100g,
  }) =>
      TypedField(
        nutrient: nutrient,
        quantity: value,
        basis: basis,
        labelStrength: ParseStrength.exact,
        basisStrength: ParseStrength.exact,
        unitStrength: ParseStrength.exact,
        unitWasExpected: true,
        region: box(0, 0, 100, 60),
        sourceIndices: <int>[nextIndex++],
        matchedBy: RuleId('rule.resolve.synonym'),
      );

  /// Grams, as a scaled quantity. `Unit.gram` tracks hundredths.
  Quantity g(int hundredths, {Qualifier qualifier = Qualifier.exact}) =>
      Quantity.qualified(hundredths, Unit.gram, qualifier);

  /// Kilocalories. `Unit.kilocalorie` tracks tenths.
  Quantity kcal(int tenths) => Quantity.exact(tenths, Unit.kilocalorie);

  TypedFields input(List<TypedField> fields) =>
      TypedFields(fields: fields, nutritionPanelPresent: true);

  ValidatedFields run(
    TypedFields typed, {
    ServingFacts? serving,
    ToleranceTable? tolerances,
    ApproximationDeltas? deltas,
  }) {
    final StageResult<ValidatedFields> out = evaluateInvariants(
      typed,
      serving: serving,
      tolerances: tolerances,
      deltas: deltas,
    );
    expect(out.isSuccess, isTrue, reason: 'expected S7 success');
    return out.valueOrNull!;
  }

  InvariantResult only(ValidatedFields v, InvariantId id, {Basis? basis}) =>
      v.results.firstWhere(
        (InvariantResult r) =>
            r.invariantId == id && (basis == null || r.basis == basis),
      );

  setUp(() => nextIndex = 0);

  group('S7 — failure paths are values, not exceptions (FR-PAR-17)', () {
    test('FR-PAR-17 nothing supplied yields regionNotFound', () {
      final StageResult<ValidatedFields> out =
          evaluateInvariants(TypedFields());
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
      expect(out.failureOrNull!.stage, PipelineStage.invariantEvaluation);
    });

    test('FR-PAR-17 the serving checks are recorded even for an empty panel',
        () {
      // FR-CNF-04 requires "inapplicable for want of data" to be recorded,
      // not omitted. An empty result list would say nothing was checked.
      final ValidatedFields v = run(input(<TypedField>[]));
      expect(only(v, InvariantId.inv09).outcome, InvariantOutcome.inapplicable);
      expect(only(v, InvariantId.inv10).outcome, InvariantOutcome.inapplicable);
    });

    test('FR-PAR-01 S7 never modifies the values it judges', () {
      // A failing value is still the value the label declared. Correcting it
      // would replace the manufacturer's claim with our guess (P1).
      final TypedFields typed = input(<TypedField>[
        field(NutrientId.saturatedFat, g(900)),
        field(NutrientId.totalFat, g(100)),
      ]);
      final ValidatedFields v = run(typed);
      expect(v.fields, typed.fields);
    });
  });

  group('S7 — INV-01, values are non-negative', () {
    test('INV-01 a panel of ordinary values passes', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(800)),
        field(NutrientId.totalFat, g(1200)),
      ]));
      expect(only(v, InvariantId.inv01).outcome, InvariantOutcome.passed);
    });

    test('INV-01 a declared zero passes, since zero is a declaration', () {
      final ValidatedFields v =
          run(input(<TypedField>[field(NutrientId.transFat, g(0))]));
      expect(only(v, InvariantId.inv01).outcome, InvariantOutcome.passed);
    });

    test('INV-01 a bounded declaration passes on its lower bound', () {
      // `< 0.5 g` denotes [0, 0.5) — still non-negative (ADR-0027).
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.transFat, g(50, qualifier: Qualifier.lessThan)),
      ]));
      expect(only(v, InvariantId.inv01).outcome, InvariantOutcome.passed);
    });
  });

  group('S7 — INV-02 to INV-05, the containment checks', () {
    test('INV-02 saturated fat within total fat passes', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(500)),
        field(NutrientId.totalFat, g(1200)),
      ]));
      expect(only(v, InvariantId.inv02).outcome, InvariantOutcome.passed);
    });

    test('INV-02 saturated fat exceeding total fat fails, with a deviation',
        () {
      // The misread this check exists to catch. 15 g saturated inside 12 g
      // total is arithmetically impossible however the label rounded.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(1500)),
        field(NutrientId.totalFat, g(1200)),
      ]));
      final InvariantResult r = only(v, InvariantId.inv02);
      expect(r.outcome, InvariantOutcome.failed);
      // 15 − (12 + 0.1 grace) = 2.9 g.
      expect(r.observedDeviation, const Quantity.exact(290, Unit.gram));
      expect(r.toleranceApplied,
          ToleranceTable.defaults.forInvariant(InvariantId.inv02));
    });

    test('DATA_MODEL 4.4 the grace absorbs independent rounding', () {
      // Saturated rounded up, total rounded down: 5.05 g against 5.0 g is a
      // legitimate panel, and failing it would make the check noise.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(505)),
        field(NutrientId.totalFat, g(500)),
      ]));
      expect(only(v, InvariantId.inv02).outcome, InvariantOutcome.passed);
    });

    test('FR-CNF-14 an overlapping bound is indeterminate, never failed', () {
      // DATA_MODEL 4.3a's worked example, with the grace composed in as §4.3a
      // requires: saturated `< 0.5 g` against total `0.3 g` spans the 0.4 g
      // ceiling. The declarations do not settle it, and treating that as a
      // failure would cap confidence on evidence that does not exist.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(50, qualifier: Qualifier.lessThan)),
        field(NutrientId.totalFat, g(30)),
      ]));
      final InvariantResult r = only(v, InvariantId.inv02);
      expect(r.outcome, InvariantOutcome.indeterminate);
      expect(r.outcome.capsConfidence, isFalse);
      expect(r.observedDeviation, isNull);
    });

    test('FR-CNF-04 a missing participant makes the check inapplicable', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(500)),
      ]));
      final InvariantResult r = only(v, InvariantId.inv02);
      expect(r.outcome, InvariantOutcome.inapplicable);
      expect(r.toleranceApplied, isNull);
    });

    test('INV-03 trans fat exceeding total fat fails', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.transFat, g(1500)),
        field(NutrientId.totalFat, g(1200)),
      ]));
      expect(only(v, InvariantId.inv03).outcome, InvariantOutcome.failed);
    });

    test('INV-04 added sugars exceeding total sugars fails', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.addedSugars, g(3000)),
        field(NutrientId.totalSugars, g(2000)),
      ]));
      expect(only(v, InvariantId.inv04).outcome, InvariantOutcome.failed);
    });

    test('INV-05 total sugars exceeding carbohydrate fails', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.totalSugars, g(7000)),
        field(NutrientId.carbohydrate, g(6000)),
      ]));
      expect(only(v, InvariantId.inv05).outcome, InvariantOutcome.failed);
    });

    test('INV-05 carries the wider 0.5 g grace', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.totalSugars, g(6040)),
        field(NutrientId.carbohydrate, g(6000)),
      ]));
      expect(only(v, InvariantId.inv05).outcome, InvariantOutcome.passed);
    });
  });

  group('S7 — INV-06, the macronutrient sum', () {
    test('INV-06 an ordinary biscuit panel passes', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(800)),
        field(NutrientId.carbohydrate, g(6000)),
        field(NutrientId.totalFat, g(2000)),
      ]));
      expect(only(v, InvariantId.inv06).outcome, InvariantOutcome.passed);
    });

    test('INV-06 a sum beyond 100 g per 100 g fails', () {
      // Physically impossible, so a misread digit somewhere in the column.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(3000)),
        field(NutrientId.carbohydrate, g(6000)),
        field(NutrientId.totalFat, g(3000)),
      ]));
      expect(only(v, InvariantId.inv06).outcome, InvariantOutcome.failed);
    });

    test('TEST_STRATEGY 12.3 INV-06 is inapplicable on a volume basis', () {
      // 100 ml of a liquid is not 100 g of it. The beverage dry run turns on
      // INAPPLICABLE being a first-class outcome rather than a silent skip.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(800), basis: Basis.per100ml),
        field(NutrientId.carbohydrate, g(6000), basis: Basis.per100ml),
        field(NutrientId.totalFat, g(2000), basis: Basis.per100ml),
      ]));
      expect(only(v, InvariantId.inv06, basis: Basis.per100ml).outcome,
          InvariantOutcome.inapplicable);
    });
  });

  group('S7 — INV-07, the Atwater reconciliation', () {
    test('INV-07 a panel whose energy reconciles exactly passes', () {
      // 4·8 + 4·60 + 9·20 = 452 kcal, computed exactly in micro-joules.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.energy, kcal(4520)),
        field(NutrientId.protein, g(800)),
        field(NutrientId.carbohydrate, g(6000)),
        field(NutrientId.totalFat, g(2000)),
      ]));
      expect(only(v, InvariantId.inv07).outcome, InvariantOutcome.passed);
    });

    test('INV-07 the 15 per cent band absorbs fibre and rounding', () {
      // Declared carbohydrate including fibre pulls the estimate high; the
      // band exists so that ordinary Indian labelling practice does not fail.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.energy, kcal(4200)),
        field(NutrientId.protein, g(800)),
        field(NutrientId.carbohydrate, g(6000)),
        field(NutrientId.totalFat, g(2000)),
      ]));
      expect(only(v, InvariantId.inv07).outcome, InvariantOutcome.passed);
    });

    test('INV-07 an energy figure far outside the band fails', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.energy, kcal(3000)),
        field(NutrientId.protein, g(800)),
        field(NutrientId.carbohydrate, g(6000)),
        field(NutrientId.totalFat, g(2000)),
      ]));
      final InvariantResult r = only(v, InvariantId.inv07);
      expect(r.outcome, InvariantOutcome.failed);
      expect(r.observedDeviation!.unit, Unit.kilocalorie);
      expect(r.observedDeviation!.scaledValue, greaterThan(0));
    });

    test('FR-CNF-04 a missing macronutrient makes INV-07 inapplicable', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.energy, kcal(4520)),
        field(NutrientId.protein, g(800)),
      ]));
      expect(only(v, InvariantId.inv07).outcome, InvariantOutcome.inapplicable);
    });
  });

  group('S7 — INV-08 to INV-10, the serving arithmetic', () {
    const ServingFacts facts = ServingFacts(
      servingSize: Quantity.exact(3000, Unit.gram),
      servingsPerPack: Quantity.exact(400, Unit.count),
      netQuantity: Quantity.exact(12000, Unit.gram),
    );

    test('FR-CNF-04 absent serving facts make all three inapplicable', () {
      // The specified outcome, not a workaround: participating fields absent.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(800), basis: Basis.perServe),
      ]));
      expect(only(v, InvariantId.inv08).outcome, InvariantOutcome.inapplicable);
      expect(only(v, InvariantId.inv09).outcome, InvariantOutcome.inapplicable);
      expect(only(v, InvariantId.inv10).outcome, InvariantOutcome.inapplicable);
    });

    test('INV-08 a per-serve column consistent with per-100 g passes', () {
      // 30 g serve of an 8 g/100 g protein biscuit is 2.4 g per serve.
      final ValidatedFields v = run(
        input(<TypedField>[
          field(NutrientId.protein, g(800)),
          field(NutrientId.protein, g(240), basis: Basis.perServe),
        ]),
        serving: facts,
      );
      expect(only(v, InvariantId.inv08).outcome, InvariantOutcome.passed);
    });

    test('INV-08 a per-serve figure that cannot be scaled from per-100 g fails',
        () {
      final ValidatedFields v = run(
        input(<TypedField>[
          field(NutrientId.protein, g(800)),
          field(NutrientId.protein, g(900), basis: Basis.perServe),
        ]),
        serving: facts,
      );
      final InvariantResult r = only(v, InvariantId.inv08);
      expect(r.outcome, InvariantOutcome.failed);
      expect(r.involves(const NutrientSubject(NutrientId.protein)), isTrue);
    });

    test('INV-09 a serve within the pack passes', () {
      final ValidatedFields v = run(input(<TypedField>[]), serving: facts);
      expect(only(v, InvariantId.inv09).outcome, InvariantOutcome.passed);
    });

    test('INV-09 a serve larger than the pack fails, exactly', () {
      final ValidatedFields v = run(
        input(<TypedField>[]),
        serving: const ServingFacts(
          servingSize: Quantity.exact(15000, Unit.gram),
          netQuantity: Quantity.exact(12000, Unit.gram),
        ),
      );
      final InvariantResult r = only(v, InvariantId.inv09);
      expect(r.outcome, InvariantOutcome.failed);
      expect(r.observedDeviation, const Quantity.exact(3000, Unit.gram));
    });

    test('INV-09 a serve in grams against a pack in millilitres declines', () {
      // Comparing them would require inventing a density.
      final ValidatedFields v = run(
        input(<TypedField>[]),
        serving: const ServingFacts(
          servingSize: Quantity.exact(3000, Unit.gram),
          netQuantity: Quantity.exact(2000, Unit.millilitre),
        ),
      );
      expect(only(v, InvariantId.inv09).outcome, InvariantOutcome.inapplicable);
    });

    test('INV-10 a serving count consistent with the pack passes', () {
      // 120 g pack ÷ 30 g serve = 4 serves.
      final ValidatedFields v = run(input(<TypedField>[]), serving: facts);
      expect(only(v, InvariantId.inv10).outcome, InvariantOutcome.passed);
    });

    test('INV-10 a serving count the pack cannot support fails', () {
      final ValidatedFields v = run(
        input(<TypedField>[]),
        serving: const ServingFacts(
          servingSize: Quantity.exact(3000, Unit.gram),
          servingsPerPack: Quantity.exact(1000, Unit.count),
          netQuantity: Quantity.exact(12000, Unit.gram),
        ),
      );
      expect(only(v, InvariantId.inv10).outcome, InvariantOutcome.failed);
    });
  });

  group('S7 — approximations are bounded or declined, never thrown on', () {
    test(
        'FR-PAR-17 an approximation with no configured delta is '
        'indeterminate', () {
      // ApproximationDeltas.deltaFor throws when unconfigured. S7 must be
      // total, so the guard is checked rather than the throw caught.
      final ValidatedFields v = run(
        input(<TypedField>[]),
        serving: const ServingFacts(
          servingSize: Quantity.exact(3000, Unit.gram),
          servingsPerPack: Quantity.approximately(400, Unit.count),
          netQuantity: Quantity.exact(12000, Unit.gram),
        ),
      );
      expect(
          only(v, InvariantId.inv10).outcome, InvariantOutcome.indeterminate);
    });

    test('ADR-0027 a configured delta widens the interval and settles it', () {
      // "About 4 servings" against a pack that holds 4 — the delta is what
      // lets INV-10 absorb the approximation without a special case.
      final ValidatedFields v = run(
        input(<TypedField>[]),
        serving: const ServingFacts(
          servingSize: Quantity.exact(3000, Unit.gram),
          servingsPerPack: Quantity.approximately(400, Unit.count),
          netQuantity: Quantity.exact(12000, Unit.gram),
        ),
        deltas: const ApproximationDeltas(<Unit, int>{Unit.count: 50}),
      );
      expect(only(v, InvariantId.inv10).outcome, InvariantOutcome.passed);
    });
  });

  group('S7 — per basis, so FR-CNF-05 caps precisely (DATA_MODEL 4.3 v1.5)',
      () {
    test('DATA_MODEL 4.3 each declared basis gets its own result', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(500)),
        field(NutrientId.totalFat, g(1200)),
        field(NutrientId.saturatedFat, g(900), basis: Basis.perServe),
        field(NutrientId.totalFat, g(360), basis: Basis.perServe),
      ]));
      expect(v.resultsFor(InvariantId.inv02), hasLength(2));
      expect(only(v, InvariantId.inv02, basis: Basis.per100g).outcome,
          InvariantOutcome.passed);
      expect(only(v, InvariantId.inv02, basis: Basis.perServe).outcome,
          InvariantOutcome.failed);
    });

    test('FR-CNF-05 a per-serve failure does not cap the per-100 g field', () {
      // The whole reason basis was added in v1.5. Capping a correctly-read
      // column on an unrelated column's failure would discard a good value.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(500)),
        field(NutrientId.totalFat, g(1200)),
        field(NutrientId.saturatedFat, g(900), basis: Basis.perServe),
        field(NutrientId.totalFat, g(360), basis: Basis.perServe),
      ]));
      expect(
          v.capsConfidenceFor(NutrientId.saturatedFat, Basis.perServe), isTrue);
      expect(
          v.capsConfidenceFor(NutrientId.saturatedFat, Basis.per100g), isFalse);
    });

    test('FR-CNF-05 an uninvolved nutrient is never capped', () {
      // A clean sodium reading must not be penalised for a fat failure.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(1500)),
        field(NutrientId.totalFat, g(1200)),
        field(NutrientId.sodium, const Quantity.exact(2500, Unit.milligram)),
      ]));
      expect(v.failures, isNotEmpty);
      expect(v.capsConfidenceFor(NutrientId.sodium, Basis.per100g), isFalse);
      expect(
          v.capsConfidenceFor(NutrientId.saturatedFat, Basis.per100g), isTrue);
    });

    test('FR-CNF-04 a basis with no declared field produces no results', () {
      // There was no column to check, which is different from a column that
      // could not be checked.
      final ValidatedFields v =
          run(input(<TypedField>[field(NutrientId.protein, g(800))]));
      expect(
        v.results.where((InvariantResult r) => r.basis == Basis.perPack),
        isEmpty,
      );
    });
  });

  group('S7 — traceability and determinism', () {
    test('FR-PAR-13 the output records the stage that produced it', () {
      expect(
          run(input(<TypedField>[field(NutrientId.protein, g(800))]))
              .producedByStage,
          PipelineStage.invariantEvaluation);
    });

    test('FR-ERR-03 unresolved candidates pass through untouched', () {
      final UnresolvedCandidate u = UnresolvedCandidate(
        reason: UnresolvedReason.noMatchingRule,
        labelText: 'Riboflavin',
        region: box(0, 0, 10, 10),
        sourceIndices: const <int>[9],
      );
      final ValidatedFields v = run(TypedFields(
        unresolved: <UnresolvedCandidate>[u],
        nutritionPanelPresent: true,
      ));
      expect(v.unresolved, <UnresolvedCandidate>[u]);
    });

    test('ADR-0013 a caller-supplied tolerance table replaces the default', () {
      // Q14 requires the calibrated bands to arrive without a code change.
      final ValidatedFields v = run(
        input(<TypedField>[
          field(NutrientId.saturatedFat, g(505)),
          field(NutrientId.totalFat, g(500)),
        ]),
        tolerances: ToleranceTable(<InvariantId, Tolerance>{
          InvariantId.inv02: const Tolerance.exact(),
        }),
      );
      expect(only(v, InvariantId.inv02).outcome, InvariantOutcome.failed,
          reason: 'an exact band no longer absorbs the rounding');
    });

    test('FR-PAR-02 repeated evaluation of one input is identical', () {
      final TypedFields typed = input(<TypedField>[
        field(NutrientId.energy, kcal(4520)),
        field(NutrientId.protein, g(800)),
        field(NutrientId.carbohydrate, g(6000)),
        field(NutrientId.totalFat, g(2000)),
      ]);
      expect(run(typed).results, run(typed).results);
      expect(run(typed).toString(), run(typed).toString());
    });
  });
}
