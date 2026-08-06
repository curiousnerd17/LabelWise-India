import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  InvariantResult result({
    InvariantId id = InvariantId.inv02,
    InvariantOutcome outcome = InvariantOutcome.passed,
    Basis? basis = Basis.per100g,
    Quantity? deviation,
    Tolerance? tolerance,
    List<InvariantSubject>? fields,
  }) =>
      InvariantResult(
        invariantId: id,
        outcome: outcome,
        basis: basis,
        observedDeviation: deviation,
        toleranceApplied: tolerance,
        participatingFields: fields ??
            <InvariantSubject>[
              const NutrientSubject(NutrientId.saturatedFat),
              const NutrientSubject(NutrientId.totalFat),
            ],
      );

  group('InvariantId — the ten checks REQUIREMENTS 5.3 names', () {
    test('FR-CNF-04 exactly ten invariants exist, coded INV-01 to INV-10', () {
      expect(InvariantId.values, hasLength(10));
      expect(
        InvariantId.values.map((InvariantId i) => i.code),
        <String>[
          'INV-01',
          'INV-02',
          'INV-03',
          'INV-04',
          'INV-05',
          'INV-06',
          'INV-07',
          'INV-08',
          'INV-09',
          'INV-10',
        ],
      );
    });

    test('DATA_MODEL 4.3 serving arithmetic is not basis-scoped', () {
      // A serving count reconciling against net quantity is one fact about the
      // pack, not a fact about a column. Everything else is per basis.
      expect(InvariantId.inv09.basisScoped, isFalse);
      expect(InvariantId.inv10.basisScoped, isFalse);
      for (final InvariantId id in InvariantId.values) {
        if (id != InvariantId.inv09 && id != InvariantId.inv10) {
          expect(id.basisScoped, isTrue, reason: '${id.code} is per basis');
        }
      }
    });
  });

  group('InvariantOutcome — four outcomes, two signals (DATA_MODEL 4.3a)', () {
    test('FR-CNF-04 exactly four outcomes exist', () {
      expect(InvariantOutcome.values, hasLength(4));
      expect(
        InvariantOutcome.values.map((InvariantOutcome o) => o.name),
        <String>['passed', 'failed', 'indeterminate', 'inapplicable'],
      );
    });

    test('FR-CNF-05 only a failure caps confidence', () {
      // Absolute per DATA_MODEL 4.3a. INDETERMINATE must never be treated as
      // FAILED (FR-CNF-14) — a label that declared a bound has not been
      // caught out, it has simply not settled the question.
      expect(InvariantOutcome.failed.capsConfidence, isTrue);
      expect(InvariantOutcome.passed.capsConfidence, isFalse);
      expect(InvariantOutcome.indeterminate.capsConfidence, isFalse);
      expect(InvariantOutcome.inapplicable.capsConfidence, isFalse);
    });

    test('FR-CNF-14 only a pass supports HIGH', () {
      expect(InvariantOutcome.passed.supportsHigh, isTrue);
      expect(InvariantOutcome.failed.supportsHigh, isFalse);
      expect(InvariantOutcome.indeterminate.supportsHigh, isFalse);
      expect(InvariantOutcome.inapplicable.supportsHigh, isFalse);
    });
  });

  group('InvariantSubject — nutrients and serving fields are both subjects',
      () {
    test('DATA_MODEL 4.3 a nutrient subject names its nutrient', () {
      const InvariantSubject s = NutrientSubject(NutrientId.protein);
      expect((s as NutrientSubject).nutrient, NutrientId.protein);
      expect(s.toString(), 'NutrientSubject(protein)');
    });

    test('DATA_MODEL 4.3 a serving subject names its field', () {
      const InvariantSubject s = ServingSubject(ServingField.netQuantity);
      expect((s as ServingSubject).field, ServingField.netQuantity);
      expect(s.toString(), 'ServingSubject(netQuantity)');
    });

    test('MI-08 the two kinds are never equal to each other', () {
      // A switch over the sealed type is exhaustive at compile time, which is
      // what stops a later stage silently ignoring one kind.
      const InvariantSubject nutrient = NutrientSubject(NutrientId.protein);
      const InvariantSubject serving = ServingSubject(ServingField.servingSize);
      expect(nutrient, isNot(serving));
      expect(nutrient, const NutrientSubject(NutrientId.protein));
      expect(nutrient, isNot(const NutrientSubject(NutrientId.sodium)));
      expect(nutrient.hashCode,
          const NutrientSubject(NutrientId.protein).hashCode);
      expect(serving, const ServingSubject(ServingField.servingSize));
      expect(serving.hashCode,
          const ServingSubject(ServingField.servingSize).hashCode);
    });

    test('DATA_MODEL 5.3 exactly three serving fields exist', () {
      expect(
        ServingField.values.map((ServingField f) => f.name),
        <String>['servingSize', 'servingsPerPack', 'netQuantity'],
      );
    });
  });

  group('InvariantResult — what was checked, and what came of it', () {
    test('FR-CNF-04 records the check, its outcome and its participants', () {
      final InvariantResult r = result(
        outcome: InvariantOutcome.failed,
        deviation: const Quantity.exact(20, Unit.gram),
        tolerance: Tolerance.grace(100000),
      );
      expect(r.invariantId, InvariantId.inv02);
      expect(r.outcome, InvariantOutcome.failed);
      expect(r.basis, Basis.per100g);
      expect(r.observedDeviation, const Quantity.exact(20, Unit.gram));
      expect(r.toleranceApplied, Tolerance.grace(100000));
      expect(r.participatingFields, hasLength(2));
    });

    test('DATA_MODEL 4.3 an inapplicable result carries no deviation', () {
      // "Meaningless for INAPPLICABLE" made structural rather than documented:
      // there was nothing to check, so there is nothing to be out by.
      expect(
        () => result(
          outcome: InvariantOutcome.inapplicable,
          deviation: const Quantity.exact(1, Unit.gram),
        ),
        throwsArgumentError,
      );
      expect(
        () => result(
          outcome: InvariantOutcome.inapplicable,
          tolerance: const Tolerance.exact(),
        ),
        throwsArgumentError,
      );
      expect(
        result(outcome: InvariantOutcome.inapplicable).observedDeviation,
        isNull,
      );
    });

    test('FR-CNF-04 a result with no participating field is rejected', () {
      // FR-CNF-05 has to know which fields to cap. A result naming none could
      // never discharge that.
      expect(
        () => result(fields: const <InvariantSubject>[]),
        throwsArgumentError,
      );
    });

    test('DATA_MODEL 4.3 a non-basis-scoped invariant may carry no basis', () {
      final InvariantResult r = result(
        id: InvariantId.inv09,
        basis: null,
        fields: const <InvariantSubject>[
          ServingSubject(ServingField.servingSize),
          ServingSubject(ServingField.netQuantity),
        ],
      );
      expect(r.basis, isNull);
    });

    test('FR-CNF-05 a result knows whether a given field participated', () {
      // The hook S8 uses to cap only the fields that were actually involved.
      final InvariantResult r = result();
      expect(
        r.involves(const NutrientSubject(NutrientId.saturatedFat)),
        isTrue,
      );
      expect(r.involves(const NutrientSubject(NutrientId.sodium)), isFalse);
    });

    test('P4 compares by value, not identity', () {
      final InvariantResult a = result();
      final InvariantResult b = result();
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(result(outcome: InvariantOutcome.failed)));
      expect(a, isNot(result(basis: Basis.perServe)),
          reason: 'the same check on another basis is another result');
    });

    test('FR-EXP-09 toString names the check, basis and outcome', () {
      expect(result().toString(), 'InvariantResult(INV-02, per100g, passed)');
      expect(
          result(
              id: InvariantId.inv09,
              basis: null,
              fields: const <InvariantSubject>[
                ServingSubject(ServingField.servingSize)
              ]).toString(),
          'InvariantResult(INV-09, -, passed)');
    });
  });

  group('Tolerance — absorbs rounding without absorbing misreads (4.4)', () {
    test('DATA_MODEL 4.4 an exact tolerance allows nothing', () {
      expect(const Tolerance.exact().allowanceFor(1000000), 0);
    });

    test('DATA_MODEL 4.4 an absolute grace is independent of magnitude', () {
      final Tolerance t = Tolerance.grace(100000);
      expect(t.allowanceFor(0), 100000);
      expect(t.allowanceFor(50000000), 100000);
    });

    test('DATA_MODEL 4.4 a relative band scales with the reference', () {
      // INV-07: 15% of the Atwater estimate.
      final Tolerance t =
          Tolerance.relative(percentTenths: 150, floorBaseUnits: 0);
      expect(t.allowanceFor(1000), 150);
      expect(t.allowanceFor(2000), 300);
    });

    test('DATA_MODEL 4.4 the floor holds when the reference is small', () {
      // Without a floor, a small declared energy would be checked to an
      // absurdly tight band and every label would report FAILED.
      final Tolerance t =
          Tolerance.relative(percentTenths: 150, floorBaseUnits: 500);
      expect(t.allowanceFor(1000), 500, reason: 'floor wins below the band');
      expect(t.allowanceFor(10000), 1500, reason: 'band wins above the floor');
    });

    test('INV-01 a negative reference still yields a non-negative allowance',
        () {
      final Tolerance t =
          Tolerance.relative(percentTenths: 150, floorBaseUnits: 0);
      expect(t.allowanceFor(-2000), 300);
    });

    test('FR-PAR-17 a negative grace or percent is rejected', () {
      expect(() => Tolerance.grace(-1), throwsArgumentError);
      expect(
        () => Tolerance.relative(percentTenths: -1, floorBaseUnits: 0),
        throwsArgumentError,
      );
      expect(
        () => Tolerance.relative(percentTenths: 50, floorBaseUnits: -1),
        throwsArgumentError,
      );
    });

    test('P4 compares by value', () {
      expect(Tolerance.grace(100), Tolerance.grace(100));
      expect(Tolerance.grace(100), isNot(Tolerance.grace(200)));
      expect(Tolerance.grace(0), isNot(const Tolerance.exact()),
          reason: 'no tolerance is not the same as a zero-width one');
      expect(Tolerance.grace(100).hashCode, Tolerance.grace(100).hashCode);
      expect(const Tolerance.exact().toString(), 'Tolerance(exact)');
    });
  });

  group('ToleranceTable — provisional, injectable, calibrated later (Q14)', () {
    test('Q14 the defaults cover every invariant', () {
      // A missing entry would silently disable a check. Q14 requires these to
      // be recalibrated against the corpus, not to be absent.
      for (final InvariantId id in InvariantId.values) {
        expect(ToleranceTable.defaults.forInvariant(id), isNotNull,
            reason: '${id.code} needs a band');
      }
    });

    test('DATA_MODEL 4.4 the exact checks carry no tolerance', () {
      expect(ToleranceTable.defaults.forInvariant(InvariantId.inv01),
          const Tolerance.exact());
      expect(ToleranceTable.defaults.forInvariant(InvariantId.inv09),
          const Tolerance.exact());
    });

    test('DATA_MODEL 4.4 the graces match the provisional bands', () {
      // 0.1 g = 100000 micrograms; 2 g = 2000000.
      expect(ToleranceTable.defaults.forInvariant(InvariantId.inv02),
          Tolerance.grace(100000));
      expect(ToleranceTable.defaults.forInvariant(InvariantId.inv05),
          Tolerance.grace(500000));
      expect(ToleranceTable.defaults.forInvariant(InvariantId.inv06),
          Tolerance.grace(2000000));
    });

    test('ADR-0013 a caller-supplied table replaces the default wholesale', () {
      // Q14 requires the calibrated bands to be recorded in the rule pack and
      // applied without a code change.
      final ToleranceTable calibrated = ToleranceTable(<InvariantId, Tolerance>{
        InvariantId.inv02: Tolerance.grace(250000),
      });
      expect(
          calibrated.forInvariant(InvariantId.inv02), Tolerance.grace(250000));
      expect(calibrated.forInvariant(InvariantId.inv03), isNull,
          reason: 'an absent band is visible, not silently defaulted');
    });
  });

  group('ServingFacts — the pack figures INV-08 to INV-10 need', () {
    test('FR-PAR-08 records the three declared serving figures', () {
      const ServingFacts f = ServingFacts(
        servingSize: Quantity.exact(3000, Unit.gram),
        servingsPerPack: Quantity.approximately(400, Unit.count),
        netQuantity: Quantity.exact(10000, Unit.gram),
      );
      expect(f.servingSize, const Quantity.exact(3000, Unit.gram));
      expect(f.servingsPerPack, const Quantity.approximately(400, Unit.count));
      expect(f.netQuantity, const Quantity.exact(10000, Unit.gram));
      expect(f.isEmpty, isFalse);
    });

    test('FR-ERR-03 absent figures are null, and none is the empty case', () {
      expect(ServingFacts.none.servingSize, isNull);
      expect(ServingFacts.none.isEmpty, isTrue);
      const ServingFacts partial =
          ServingFacts(servingSize: Quantity.exact(3000, Unit.gram));
      expect(partial.isEmpty, isFalse);
      expect(partial.netQuantity, isNull);
    });

    test('P4 compares by value', () {
      const ServingFacts a =
          ServingFacts(servingSize: Quantity.exact(3000, Unit.gram));
      const ServingFacts b =
          ServingFacts(servingSize: Quantity.exact(3000, Unit.gram));
      expect(a, b);
      expect(a, isNot(ServingFacts.none));
      expect(a.hashCode, b.hashCode);
      expect(ServingFacts.none.toString(), 'ServingFacts(none)');
    });
  });
}
