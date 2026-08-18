import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **The product's signature Layer 1 output** (`DATA_MODEL.md` §6.2).
///
/// Serving-size manipulation is the primary legal deception on Indian
/// packaging, which is why the reconciliation earns a type of its own. It puts
/// the declared serve, the servings per pack and the whole-pack totals side by
/// side and states whether the arithmetic holds.
///
/// `discrepancy` is **factual, not evaluative**. It records that the numbers do
/// not multiply out. Any suggestion that a small serve is *misleading* is
/// Layer 2's business, and putting it here would breach FR-L1-01.
void main() {
  final Version pack = Version(0, 1, 0);

  FieldState declared(int scaled, {Unit unit = Unit.gram}) => ExtractedField(
        quantity: Quantity.exact(scaled, unit),
        basis: Basis.perServe,
        provenance: Provenance.extracted(
          producedByStage: PipelineStage.servingResolution,
          parseRuleId: RuleId('rule.serving.marker'),
          parseStrength: ParseStrength.exact,
          sourceRegion: RegionRef(left: 0, top: 0, right: 100, bottom: 10),
          rulePackVersion: pack,
        ),
        confidence: Confidence.high,
      );

  FieldState packTotal(int scaled, {Unit unit = Unit.milligram}) =>
      DerivedField(
        quantity: Quantity.exact(scaled, unit),
        basis: Basis.perPack,
        provenance: Provenance.factual(
          parseRuleId: RuleId('rule.l1.scale-to-pack'),
          rulePackVersion: pack,
        ),
        confidence: Confidence.high,
      );

  NutrientField nutrient(NutrientId id, int scaled) => NutrientField(
        nutrient: id,
        perHundred: const NotDeclaredField(),
        perServe: const NotDeclaredField(),
        perPack: packTotal(scaled),
      );

  ServingReconciliationResult result({
    FieldState? serve,
    FieldState? serves,
    List<NutrientField>? wholePack,
    ServingDiscrepancy discrepancy = ServingDiscrepancy.none,
  }) =>
      ServingReconciliationResult(
        declaredServe: serve ?? declared(3000),
        servesPerPack: serves ?? declared(1000, unit: Unit.count),
        wholePackValues:
            wholePack ?? <NutrientField>[nutrient(NutrientId.sodium, 12000)],
        discrepancy: discrepancy,
      );

  group('ServingDiscrepancy — four factual states', () {
    test('exactly the four approved states exist', () {
      expect(ServingDiscrepancy.values, <ServingDiscrepancy>[
        ServingDiscrepancy.none,
        ServingDiscrepancy.servesInconsistent,
        ServingDiscrepancy.serveExceedsPack,
        ServingDiscrepancy.notComputable,
      ]);
    });

    test('every state is constructible on a result', () {
      for (final ServingDiscrepancy d in ServingDiscrepancy.values) {
        expect(result(discrepancy: d).discrepancy, d);
      }
    });

    test('the names state arithmetic, never judgement (FR-L1-01)', () {
      // Read them: the serves do not multiply out; the serve is larger than the
      // pack; it could not be computed. None asserts that anything is wrong
      // with the product.
      final List<String> names = ServingDiscrepancy.values
          .map((ServingDiscrepancy d) => d.name)
          .toList();
      for (final String forbidden in <String>[
        'misleading',
        'deceptive',
        'suspicious',
        'violation',
        'unhealthy',
        'bad',
      ]) {
        expect(names, isNot(anyElement(contains(forbidden))));
      }
    });
  });

  group('ServingReconciliationResult — what it records', () {
    test('it implements the domain\'s open ServingReconciliation interface',
        () {
      // The interface was left `abstract interface` rather than `sealed`
      // precisely so the analysis layer could implement it.
      expect(result(), isA<ServingReconciliation>());
    });

    test('the declared serve and servings per pack are carried as read', () {
      final ServingReconciliationResult r = result();
      expect((r.declaredServe as ExtractedField).quantity,
          const Quantity.exact(3000, Unit.gram));
      expect((r.servesPerPack as ExtractedField).quantity,
          const Quantity.exact(1000, Unit.count));
    });

    test('whole-pack totals are NutrientFields, not a new value type', () {
      final ServingReconciliationResult r = result();
      expect(r.wholePackValues, hasLength(1));
      expect(r.wholePackValues.single.nutrient, NutrientId.sodium);
      expect(
        (r.wholePackValues.single.perPack as DerivedField).quantity,
        const Quantity.exact(12000, Unit.milligram),
      );
    });

    test('an undeclared serve is NotDeclared, not an absent field', () {
      // MI-08 one level up: the pack omitting a figure is the manufacturer's
      // choice, and is not the same as our failing to read it.
      final ServingReconciliationResult r =
          result(serve: const NotDeclaredField());
      expect(r.declaredServe, isA<NotDeclaredField>());
      expect(r.declaredServe.quantityOrNull, isNull);
    });

    test('an unreadable serve stays Unresolved, distinct from undeclared', () {
      final FieldState unresolved = UnresolvedField(
        reason: UnresolvedReason.ambiguousMatch,
        provenance: Provenance.extracted(
          producedByStage: PipelineStage.servingResolution,
          parseRuleId: RuleId('rule.serving.marker'),
          parseStrength: ParseStrength.heuristic,
          sourceRegion: RegionRef(left: 0, top: 0, right: 100, bottom: 10),
          rulePackVersion: pack,
        ),
      );
      final ServingReconciliationResult r = result(serve: unresolved);
      expect(r.declaredServe, isA<UnresolvedField>());
      expect(r.declaredServe, isNot(isA<NotDeclaredField>()));
    });

    test('missing inputs and refused arithmetic are different statements', () {
      // Absence lives in the FieldState; refusal lives in the discrepancy.
      // Collapsing them would lose which of the two actually happened.
      final ServingReconciliationResult missing = result(
        serve: const NotDeclaredField(),
        discrepancy: ServingDiscrepancy.notComputable,
      );
      final ServingReconciliationResult refused = result(
        discrepancy: ServingDiscrepancy.notComputable,
      );
      expect(missing.declaredServe, isA<NotDeclaredField>());
      expect(refused.declaredServe, isA<ExtractedField>());
      expect(missing, isNot(refused));
    });

    test('an empty whole-pack list is legitimate', () {
      // A label with a net quantity but no per-100 figures reconciles its
      // serving arithmetic and has no nutrient totals to show.
      expect(
          result(wholePack: const <NutrientField>[]).wholePackValues, isEmpty);
    });
  });

  group('ServingReconciliationResult — value semantics', () {
    test('two results with the same content compare equal', () {
      expect(result(), result());
      expect(result().hashCode, result().hashCode);
    });

    test('a different declared serve differs', () {
      expect(result(), isNot(result(serve: declared(4000))));
      expect(result(), isNot(result(serve: const NotDeclaredField())));
    });

    test('a different servings-per-pack differs', () {
      expect(result(), isNot(result(serves: declared(800, unit: Unit.count))));
    });

    test('different whole-pack values differ', () {
      expect(
        result(),
        isNot(result(wholePack: <NutrientField>[
          nutrient(NutrientId.sodium, 15000),
        ])),
      );
      expect(result(), isNot(result(wholePack: const <NutrientField>[])));
    });

    test('a different discrepancy differs', () {
      expect(result(),
          isNot(result(discrepancy: ServingDiscrepancy.servesInconsistent)));
    });

    test('whole-pack order is part of the value', () {
      // Deterministic ordering (FR-PAR-02): the same label must present its
      // totals in the same order every time.
      final NutrientField a = nutrient(NutrientId.sodium, 12000);
      final NutrientField b = nutrient(NutrientId.protein, 1800);
      expect(
        result(wholePack: <NutrientField>[a, b]),
        isNot(result(wholePack: <NutrientField>[b, a])),
      );
      expect(result(wholePack: <NutrientField>[a, b]).wholePackValues,
          <NutrientField>[a, b]);
    });
  });

  group('ServingReconciliationResult — immutability', () {
    test('mutating the caller\'s list does not change the result', () {
      final List<NutrientField> supplied = <NutrientField>[
        nutrient(NutrientId.sodium, 12000),
      ];
      final ServingReconciliationResult r = result(wholePack: supplied);
      supplied.add(nutrient(NutrientId.protein, 1800));
      expect(r.wholePackValues, hasLength(1));
    });

    test('the stored list cannot be mutated through the object', () {
      expect(
        () => result().wholePackValues.add(nutrient(NutrientId.protein, 1800)),
        throwsUnsupportedError,
      );
    });
  });

  group('ServingReconciliationResult — it stores, it does not compute', () {
    test('the discrepancy is supplied, never inferred by the constructor', () {
      // This step is the model only. A result whose figures do not multiply out
      // still reports whatever discrepancy it was given — the engine decides,
      // and the engine arrives in a later step.
      final ServingReconciliationResult r = ServingReconciliationResult(
        declaredServe: declared(40000),
        servesPerPack: declared(1000, unit: Unit.count),
        wholePackValues: const <NutrientField>[],
        discrepancy: ServingDiscrepancy.none,
      );
      expect(r.discrepancy, ServingDiscrepancy.none,
          reason: 'the type performs no arithmetic of its own');
    });

    test('toString summarises without dumping every total', () {
      expect(result().toString(), contains('none'));
    });
  });
}
