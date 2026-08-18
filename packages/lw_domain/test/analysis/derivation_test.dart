import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **How a Layer 1 number was arrived at (FR-EXP-09).**
///
/// A derived figure with no derivation is a number the user is asked to trust.
/// `Derivation` is what makes the arithmetic auditable: the operation, the
/// declared values it consumed, the gazetted constants it applied — each with
/// its citation — and the result.
///
/// `constantsUsed` is the part that matters most. The 2,000 mg sodium
/// denominator appears as a named constant with a source reference, not as a
/// number that materialised inside the arithmetic.
void main() {
  DerivationInput input(
    FindingSubject field,
    Quantity quantity, {
    Basis basis = Basis.per100g,
    Confidence confidence = Confidence.high,
  }) =>
      DerivationInput(
        field: field,
        quantity: quantity,
        basis: basis,
        confidence: confidence,
      );

  ConstantUsed constant({
    String id = 'const.rda.sodium',
    Quantity? value,
    String source = 'src.fssai.labelling.2020',
  }) =>
      ConstantUsed(
        constantId: ConstantId(id),
        value: value ?? const Quantity.exact(20000, Unit.milligram),
        sourceRef: SourceId(source),
      );

  Derivation derivation({
    DerivationOperation operation = DerivationOperation.rdaPercent,
    List<DerivationInput>? inputs,
    List<ConstantUsed>? constants,
    Quantity? result,
  }) =>
      Derivation(
        operation: operation,
        inputs: inputs ??
            <DerivationInput>[
              input(const FindingNutrient(NutrientId.sodium),
                  const Quantity.exact(4000, Unit.milligram)),
            ],
        constantsUsed: constants ?? <ConstantUsed>[constant()],
        result: result ?? const Quantity.exact(2000, Unit.percent),
      );

  group('DerivationOperation — exactly the six the model names', () {
    test('all six exist', () {
      expect(DerivationOperation.values, <DerivationOperation>[
        DerivationOperation.normaliseTo100,
        DerivationOperation.scaleToServe,
        DerivationOperation.scaleToPack,
        DerivationOperation.rdaPercent,
        DerivationOperation.saltToSodium,
        DerivationOperation.energyConvert,
      ]);
    });

    test('there are no speculative extras', () {
      // A seventh operation would be a Layer 1 capability nothing implements.
      expect(DerivationOperation.values, hasLength(6));
    });
  });

  group('DerivationInput — one declared value the arithmetic consumed', () {
    test('it records the field, quantity, basis and confidence', () {
      final DerivationInput i = input(
        const FindingNutrient(NutrientId.sodium),
        const Quantity.exact(4000, Unit.milligram),
        basis: Basis.per100g,
        confidence: Confidence.medium,
      );
      expect(i.field, const FindingNutrient(NutrientId.sodium));
      expect(i.quantity, const Quantity.exact(4000, Unit.milligram));
      expect(i.basis, Basis.per100g);
      expect(i.confidence, Confidence.medium);
    });

    test('a serving figure is as valid an input as a nutrient', () {
      // Whole-pack scaling consumes one of each, so the union is load-bearing
      // rather than decorative.
      final DerivationInput i = input(
        const FindingServing(ServingField.netQuantity),
        const Quantity.exact(30000, Unit.gram),
        basis: Basis.perPack,
      );
      expect(i.field, const FindingServing(ServingField.netQuantity));
    });

    test('inputs compare by value across every field', () {
      expect(
          input(const FindingNutrient(NutrientId.sodium),
              const Quantity.exact(4000, Unit.milligram)),
          input(const FindingNutrient(NutrientId.sodium),
              const Quantity.exact(4000, Unit.milligram)));
      expect(
        input(const FindingNutrient(NutrientId.sodium),
                const Quantity.exact(4000, Unit.milligram))
            .hashCode,
        input(const FindingNutrient(NutrientId.sodium),
                const Quantity.exact(4000, Unit.milligram))
            .hashCode,
      );
    });

    test('a different field, quantity, basis or confidence differs', () {
      final DerivationInput base = input(
          const FindingNutrient(NutrientId.sodium),
          const Quantity.exact(4000, Unit.milligram));
      expect(
          base,
          isNot(input(const FindingNutrient(NutrientId.protein),
              const Quantity.exact(4000, Unit.milligram))));
      expect(
          base,
          isNot(input(const FindingNutrient(NutrientId.sodium),
              const Quantity.exact(5000, Unit.milligram))));
      expect(
          base,
          isNot(input(const FindingNutrient(NutrientId.sodium),
              const Quantity.exact(4000, Unit.milligram),
              basis: Basis.perServe)));
      expect(
          base,
          isNot(input(const FindingNutrient(NutrientId.sodium),
              const Quantity.exact(4000, Unit.milligram),
              confidence: Confidence.low)));
    });

    test('the qualifier is part of the input, never dropped (MI-16)', () {
      // `< 0.5 g` and `0.5 g` are different declarations, and a derivation that
      // recorded them identically would misstate what it consumed.
      expect(
          input(const FindingNutrient(NutrientId.transFat),
              const Quantity.lessThan(50, Unit.gram)),
          isNot(input(const FindingNutrient(NutrientId.transFat),
              const Quantity.exact(50, Unit.gram))));
    });
  });

  group('ConstantUsed — the citation that makes a number auditable', () {
    test('it records the constant id, its value and its source', () {
      final ConstantUsed c = constant();
      expect(c.constantId, ConstantId('const.rda.sodium'));
      expect(c.value, const Quantity.exact(20000, Unit.milligram));
      expect(c.sourceRef, SourceId('src.fssai.labelling.2020'));
    });

    test('constants compare by value', () {
      expect(constant(), constant());
      expect(constant().hashCode, constant().hashCode);
    });

    test('a different id, value or source differs', () {
      expect(constant(), isNot(constant(id: 'const.rda.energy')));
      expect(constant(),
          isNot(constant(value: const Quantity.exact(6700, Unit.gram))));
      expect(constant(), isNot(constant(source: 'src.icmr.nin.2020')));
    });

    test('it carries the denominator itself, not just a reference to one', () {
      // A finding stored today and read months later must still show the value
      // that was applied, even if the pack has since changed it (FR-HIS-05).
      expect(constant().value.scaledValue, 20000);
      expect(constant().value.unit, Unit.milligram);
    });
  });

  group('Derivation — value semantics', () {
    test('it records operation, inputs, constants and result', () {
      final Derivation d = derivation();
      expect(d.operation, DerivationOperation.rdaPercent);
      expect(d.inputs, hasLength(1));
      expect(d.constantsUsed, hasLength(1));
      expect(d.result, const Quantity.exact(2000, Unit.percent));
    });

    test('two derivations with the same content compare equal', () {
      expect(derivation(), derivation());
      expect(derivation().hashCode, derivation().hashCode);
    });

    test('a different operation differs', () {
      expect(derivation(),
          isNot(derivation(operation: DerivationOperation.scaleToPack)));
    });

    test('a different result differs', () {
      expect(derivation(),
          isNot(derivation(result: const Quantity.exact(2500, Unit.percent))));
    });

    test('different inputs differ', () {
      expect(
        derivation(),
        isNot(derivation(inputs: <DerivationInput>[
          input(const FindingNutrient(NutrientId.protein),
              const Quantity.exact(600, Unit.gram)),
        ])),
      );
    });

    test('different constants differ', () {
      expect(
        derivation(),
        isNot(derivation(
            constants: <ConstantUsed>[constant(id: 'const.rda.energy')])),
      );
    });

    test('input order is part of the value', () {
      // The order is the order the arithmetic consumed them, and reversing it
      // describes a different calculation.
      final DerivationInput a = input(const FindingNutrient(NutrientId.sodium),
          const Quantity.exact(4000, Unit.milligram));
      final DerivationInput b = input(
          const FindingServing(ServingField.netQuantity),
          const Quantity.exact(30000, Unit.gram),
          basis: Basis.perPack);
      expect(
        derivation(inputs: <DerivationInput>[a, b]),
        isNot(derivation(inputs: <DerivationInput>[b, a])),
      );
    });

    test('constant order is preserved', () {
      final ConstantUsed a = constant();
      final ConstantUsed b = constant(id: 'const.rda.energy');
      final Derivation d = derivation(constants: <ConstantUsed>[a, b]);
      expect(d.constantsUsed, <ConstantUsed>[a, b]);
    });

    test('a derivation may legitimately use no constants', () {
      // Whole-pack scaling applies no gazetted constant — it multiplies two
      // declared values. An empty list is a fact about the arithmetic, not a
      // missing field.
      final Derivation d = derivation(
        operation: DerivationOperation.scaleToPack,
        constants: const <ConstantUsed>[],
      );
      expect(d.constantsUsed, isEmpty);
    });
  });

  group('Derivation — immutability', () {
    test('mutating the caller\'s input list does not change the derivation',
        () {
      final List<DerivationInput> supplied = <DerivationInput>[
        input(const FindingNutrient(NutrientId.sodium),
            const Quantity.exact(4000, Unit.milligram)),
      ];
      final Derivation d = derivation(inputs: supplied);
      supplied.add(input(const FindingNutrient(NutrientId.protein),
          const Quantity.exact(600, Unit.gram)));
      expect(d.inputs, hasLength(1),
          reason: 'the derivation copied what it was given');
    });

    test('mutating the caller\'s constant list does not change it either', () {
      final List<ConstantUsed> supplied = <ConstantUsed>[constant()];
      final Derivation d = derivation(constants: supplied);
      supplied.clear();
      expect(d.constantsUsed, hasLength(1));
    });

    test('the stored lists cannot be mutated through the object', () {
      // An audit trail a caller can edit after the fact is not an audit trail.
      final Derivation d = derivation();
      expect(
          () => d.inputs.add(input(const FindingNutrient(NutrientId.protein),
              const Quantity.exact(600, Unit.gram))),
          throwsUnsupportedError);
      expect(() => d.constantsUsed.add(constant()), throwsUnsupportedError);
    });
  });

  group('Derivation — it can express the four real M13 calculations', () {
    test('per-100 normalisation', () {
      // 1.8 g per 30 g serve restated per 100 g.
      final Derivation d = Derivation(
        operation: DerivationOperation.normaliseTo100,
        inputs: <DerivationInput>[
          input(const FindingNutrient(NutrientId.protein),
              const Quantity.exact(180, Unit.gram),
              basis: Basis.perServe),
          input(const FindingServing(ServingField.servingSize),
              const Quantity.exact(3000, Unit.gram),
              basis: Basis.perServe),
        ],
        constantsUsed: const <ConstantUsed>[],
        result: const Quantity.exact(600, Unit.gram),
      );
      expect(d.operation, DerivationOperation.normaliseTo100);
      expect(d.inputs, hasLength(2));
      expect(d.constantsUsed, isEmpty);
    });

    test('whole-pack scaling', () {
      // 400 mg per 100 g across a 300 g pack.
      final Derivation d = Derivation(
        operation: DerivationOperation.scaleToPack,
        inputs: <DerivationInput>[
          input(const FindingNutrient(NutrientId.sodium),
              const Quantity.exact(4000, Unit.milligram)),
          input(const FindingServing(ServingField.netQuantity),
              const Quantity.exact(30000, Unit.gram),
              basis: Basis.perPack),
        ],
        constantsUsed: const <ConstantUsed>[],
        result: const Quantity.exact(12000, Unit.milligram),
      );
      expect(d.result, const Quantity.exact(12000, Unit.milligram));
    });

    test('an RDA calculation carries its constant and citation', () {
      final Derivation d = derivation();
      expect(d.constantsUsed.single.constantId, ConstantId('const.rda.sodium'));
      expect(d.constantsUsed.single.sourceRef,
          SourceId('src.fssai.labelling.2020'));
      expect(d.inputs.single.field, const FindingNutrient(NutrientId.sodium));
    });

    test('serving reconciliation over the three declared figures', () {
      final Derivation d = Derivation(
        operation: DerivationOperation.scaleToPack,
        inputs: <DerivationInput>[
          input(const FindingServing(ServingField.servingSize),
              const Quantity.exact(3000, Unit.gram),
              basis: Basis.perServe),
          input(const FindingServing(ServingField.servingsPerPack),
              const Quantity.exact(1000, Unit.count),
              basis: Basis.perPack),
        ],
        constantsUsed: const <ConstantUsed>[],
        result: const Quantity.exact(30000, Unit.gram),
      );
      expect(
          d.inputs.map((DerivationInput i) => i.field).toList(),
          <FindingSubject>[
            const FindingServing(ServingField.servingSize),
            const FindingServing(ServingField.servingsPerPack),
          ]);
    });
  });
}
