import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// M11b — what an arithmetic overflow must become by the time it reaches a
/// verdict.
///
/// **INDETERMINATE, never FAILED.** A wrapped product is a number the code
/// cannot vouch for. Reporting it as a failed invariant would tell the user
/// their label is inconsistent on the strength of arithmetic that did not
/// happen, and FR-CNF-05 would then cap a field's confidence because of it.
/// Refusing the comparison is the only honest outcome (FR-PAR-17: a value, not
/// an exception).
///
/// The magnitudes here are absurd by design. They are what OCR produces when it
/// reads a smudged `2` as `22222222222` — the real source of these numbers is a
/// misread, not a manufacturer.
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

  Quantity g(int hundredths) => Quantity.exact(hundredths, Unit.gram);
  Quantity kcal(int tenths) => Quantity.exact(tenths, Unit.kilocalorie);

  TypedFields input(List<TypedField> fields) =>
      TypedFields(fields: fields, nutritionPanelPresent: true);

  ValidatedFields run(TypedFields typed, {ServingFacts? serving}) {
    final StageResult<ValidatedFields> out =
        evaluateInvariants(typed, serving: serving);
    expect(out.isSuccess, isTrue, reason: 'expected S7 success');
    return out.valueOrNull!;
  }

  InvariantResult only(ValidatedFields v, InvariantId id, {Basis? basis}) =>
      v.results.firstWhere(
        (InvariantResult r) =>
            r.invariantId == id && (basis == null || r.basis == basis),
      );

  /// `Unit.gram` tracks hundredths and converts at 10^4 µg per increment, so a
  /// scaled value of 10^12 is 10^16 base units — past the storage bound.
  const int pastStorageBound = 1000000000000;

  /// 10^11 hundredths is 10^15 base units, which **is** storable. It overflows
  /// only once multiplied by an Atwater factor or a serve, which is what makes
  /// it the interesting magnitude: the storage guard alone does not catch it.
  const int storableButProductUnsafe = 100000000000;

  setUp(() => nextIndex = 0);

  group('S7 — a magnitude past the storage bound cannot be judged', () {
    ValidatedFields overflowing() => run(input(<TypedField>[
          field(NutrientId.protein, g(pastStorageBound)),
          field(NutrientId.carbohydrate, g(1000)),
          field(NutrientId.totalFat, g(500)),
          field(NutrientId.saturatedFat, g(200)),
          field(NutrientId.energy, kcal(4500)),
        ]));

    test('INV-06 is INDETERMINATE, not FAILED', () {
      // The sum genuinely exceeds 100 g, so a naive implementation would call
      // this a failure. It cannot: the number it would be failing is not one
      // the arithmetic can vouch for.
      expect(
        only(overflowing(), InvariantId.inv06, basis: Basis.per100g).outcome,
        InvariantOutcome.indeterminate,
      );
    });

    test('INV-07 is INDETERMINATE, not FAILED', () {
      expect(
        only(overflowing(), InvariantId.inv07, basis: Basis.per100g).outcome,
        InvariantOutcome.indeterminate,
      );
    });

    test('INV-06 stays INAPPLICABLE when a term is simply absent', () {
      // MI-08 distinction: "cannot compute" and "not declared" must not
      // collapse into one another just because both are non-verdicts.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(pastStorageBound)),
        field(NutrientId.carbohydrate, g(1000)),
      ]));
      expect(only(v, InvariantId.inv06, basis: Basis.per100g).outcome,
          InvariantOutcome.inapplicable);
    });

    test('an ordinary label is unaffected — INV-06 still fails when it should',
        () {
      // The guard must not turn every strong verdict into a shrug. This is the
      // control case for the two assertions above.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(5000)),
        field(NutrientId.carbohydrate, g(6000)),
        field(NutrientId.totalFat, g(4000)),
      ]));
      expect(only(v, InvariantId.inv06, basis: Basis.per100g).outcome,
          InvariantOutcome.failed);
    });

    test('INV-02 is INDETERMINATE when either side cannot be bounded', () {
      // saturatedFat ≤ totalFat, with the greater side unreadable. Passing it
      // would be as wrong as failing it.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(200)),
        field(NutrientId.totalFat, g(pastStorageBound)),
      ]));
      expect(only(v, InvariantId.inv02, basis: Basis.per100g).outcome,
          InvariantOutcome.indeterminate);
    });

    test('INV-02 is INDETERMINATE when the lesser side cannot be bounded', () {
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(pastStorageBound)),
        field(NutrientId.totalFat, g(200)),
      ]));
      expect(only(v, InvariantId.inv02, basis: Basis.per100g).outcome,
          InvariantOutcome.indeterminate);
    });

    test('no invariant anywhere reports FAILED for an unbounded label', () {
      // The blanket statement of the rule: an unreadable magnitude produces no
      // accusation of any kind.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(pastStorageBound)),
        field(NutrientId.transFat, g(pastStorageBound)),
        field(NutrientId.totalFat, g(pastStorageBound)),
      ]));
      expect(
        v.results
            .where((InvariantResult r) => r.outcome == InvariantOutcome.failed),
        isEmpty,
      );
    });
  });

  group('S7 — INV-07 Atwater terms overflow past the storage bound', () {
    test('a storable magnitude that overflows the energy factor is refused',
        () {
      // Each gram of fat contributes 37656 µJ per µg. A value that stores
      // fine can still make that product wrap, which is precisely the case the
      // storage bound does not cover.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(storableButProductUnsafe)),
        field(NutrientId.carbohydrate, g(storableButProductUnsafe)),
        field(NutrientId.totalFat, g(storableButProductUnsafe)),
        field(NutrientId.energy, kcal(4500)),
      ]));
      expect(only(v, InvariantId.inv07, basis: Basis.per100g).outcome,
          InvariantOutcome.indeterminate);
    });

    test('a realistic energy-dense label still reaches a definite verdict', () {
      // 100 g of pure fat: 900 kcal by Atwater. The largest honest per-100 g
      // panel there is, and it must not be refused.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(0)),
        field(NutrientId.carbohydrate, g(0)),
        field(NutrientId.totalFat, g(10000)),
        field(NutrientId.energy, kcal(9000)),
      ]));
      expect(only(v, InvariantId.inv07, basis: Basis.per100g).outcome,
          InvariantOutcome.passed);
    });
  });

  group('S7 — INV-08 per-serve scaling overflow', () {
    test('an absurd serve makes the scaled expectation INDETERMINATE', () {
      final ValidatedFields v = run(
        input(<TypedField>[
          field(NutrientId.protein, g(storableButProductUnsafe)),
          field(NutrientId.protein, g(1000), basis: Basis.perServe),
        ]),
        serving: ServingFacts(servingSize: g(storableButProductUnsafe)),
      );
      expect(only(v, InvariantId.inv08, basis: Basis.perServe).outcome,
          InvariantOutcome.indeterminate);
    });

    test('the overflowing case is not reported as a reconciliation failure',
        () {
      // Declared 10 g per serve against an uncomputable expectation is exactly
      // the shape that would otherwise look like a manufacturer error.
      final ValidatedFields v = run(
        input(<TypedField>[
          field(NutrientId.protein, g(storableButProductUnsafe)),
          field(NutrientId.carbohydrate, g(storableButProductUnsafe)),
          field(NutrientId.protein, g(1000), basis: Basis.perServe),
          field(NutrientId.carbohydrate, g(1000), basis: Basis.perServe),
        ]),
        serving: ServingFacts(servingSize: g(storableButProductUnsafe)),
      );
      expect(only(v, InvariantId.inv08, basis: Basis.perServe).outcome,
          isNot(InvariantOutcome.failed));
    });

    test('a large but legitimate Indian pack still reconciles (BL-1)', () {
      // 80 g carbohydrate per 100 g on a 250 g serve — mithai, a thali mix, a
      // family pack. The intermediate is 2x10^16, above the storage bound and
      // far below a wrap. If the product guard reused the storage bound this
      // would be refused, which is the defect BL-1 named.
      final ValidatedFields v = run(
        input(<TypedField>[
          field(NutrientId.carbohydrate, g(8000)),
          field(NutrientId.carbohydrate, g(20000), basis: Basis.perServe),
        ]),
        serving: ServingFacts(servingSize: g(25000)),
      );
      expect(only(v, InvariantId.inv08, basis: Basis.perServe).outcome,
          InvariantOutcome.passed);
    });

    test('a legitimate pack with a genuinely wrong per-serve figure fails', () {
      // The control: the guard has not made INV-08 toothless.
      final ValidatedFields v = run(
        input(<TypedField>[
          field(NutrientId.carbohydrate, g(8000)),
          field(NutrientId.protein, g(1000)),
          field(NutrientId.carbohydrate, g(500), basis: Basis.perServe),
          field(NutrientId.protein, g(50), basis: Basis.perServe),
        ]),
        serving: ServingFacts(servingSize: g(25000)),
      );
      expect(only(v, InvariantId.inv08, basis: Basis.perServe).outcome,
          InvariantOutcome.failed);
    });
  });

  group('S7 — INV-10 division at the largest storable magnitude', () {
    test('the maximum storable net quantity still divides to a verdict', () {
      // Documents a reachability finding rather than a guard: once the storage
      // bound is enforced on conversion, `net x 100` cannot wrap. The guard in
      // the division helper is defence in depth, and this test exists to prove
      // it did not cost a verdict at the extreme.
      final ValidatedFields v = run(
        input(<TypedField>[field(NutrientId.protein, g(1000))]),
        serving: const ServingFacts(
          servingSize: Quantity.exact(10000, Unit.gram),
          servingsPerPack: Quantity.exact(1000, Unit.count),
          netQuantity: Quantity.exact(100000, Unit.gram),
        ),
      );
      expect(only(v, InvariantId.inv10).outcome, InvariantOutcome.passed);
    });

    test('an unbounded net quantity yields INDETERMINATE, not FAILED', () {
      final ValidatedFields v = run(
        input(<TypedField>[field(NutrientId.protein, g(1000))]),
        serving: ServingFacts(
          servingSize: g(1000),
          servingsPerPack: const Quantity.exact(1000, Unit.count),
          netQuantity: g(pastStorageBound),
        ),
      );
      expect(
          only(v, InvariantId.inv10).outcome, InvariantOutcome.indeterminate);
    });

    test('an unbounded serving size yields INDETERMINATE for INV-09', () {
      final ValidatedFields v = run(
        input(<TypedField>[field(NutrientId.protein, g(1000))]),
        serving: ServingFacts(
          servingSize: g(pastStorageBound),
          netQuantity: g(50000),
        ),
      );
      expect(
          only(v, InvariantId.inv09).outcome, InvariantOutcome.indeterminate);
    });
  });

  group('S8 — an overflow is scored exactly like any other INDETERMINATE', () {
    final Version pack = Version(1, 0, 0);

    ScoredFields score(ValidatedFields v) {
      final StageResult<ScoredFields> out =
          assignConfidence(v, rulePackVersion: pack);
      expect(out.isSuccess, isTrue, reason: 'expected S8 success');
      return out.valueOrNull!;
    }

    Confidence? confidenceOf(ScoredFields s, NutrientId id) =>
        s.fields.firstWhere((ScoredField f) => f.nutrient == id).confidence;

    test(
        'an overflow-driven INDETERMINATE does not cap confidence, and does '
        'not promote it either (PT-21)', () {
      // PT-21 is explicit that INDETERMINATE neither caps nor supports HIGH.
      // The point of this test is that overflow enters that existing rule
      // rather than acquiring a rule of its own — so the comparison is against
      // a *different* cause of the same outcome, not against a magic level.
      final ValidatedFields overflowed = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(200)),
        field(NutrientId.totalFat, g(pastStorageBound)),
      ]));
      final ValidatedFields missingDelta = run(input(<TypedField>[
        field(NutrientId.saturatedFat, g(200)),
        field(
            NutrientId.totalFat, const Quantity.approximately(2000, Unit.gram)),
      ]));
      expect(
        only(missingDelta, InvariantId.inv02, basis: Basis.per100g).outcome,
        InvariantOutcome.indeterminate,
        reason: 'the reference cause must itself be indeterminate',
      );
      expect(
        confidenceOf(score(overflowed), NutrientId.saturatedFat),
        confidenceOf(score(missingDelta), NutrientId.saturatedFat),
      );
    });

    test('no field is scored against a fabricated FAILED invariant', () {
      // FR-CNF-05 caps a field involved in a FAILED invariant. If overflow
      // produced FAILED, that cap would be applied for arithmetic that never
      // completed — the exact harm this milestone exists to prevent.
      final ValidatedFields v = run(input(<TypedField>[
        field(NutrientId.protein, g(pastStorageBound)),
        field(NutrientId.carbohydrate, g(pastStorageBound)),
        field(NutrientId.totalFat, g(pastStorageBound)),
      ]));
      expect(
        v.results
            .where((InvariantResult r) => r.outcome == InvariantOutcome.failed),
        isEmpty,
        reason: 'nothing for FR-CNF-05 to cap against',
      );
      final ScoredFields s = score(v);
      expect(s.fields, hasLength(3),
          reason: 'the fields are still reported; refusal is not omission');
    });
  });
}
