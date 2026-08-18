import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **What Layer 1 hands back.**
///
/// Two members, because the reconciliation is not a finding. `DATA_MODEL.md`
/// §6.2 gives it its own shape — a declared serve, a servings count, the
/// whole-pack totals and a discrepancy — and flattening it into the findings
/// list would lose the relationship between those four parts.
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

  FieldState computed(int scaled, {Unit unit = Unit.gram}) => DerivedField(
        quantity: Quantity.exact(scaled, unit),
        basis: Basis.per100g,
        provenance: Provenance.factual(
          parseRuleId: RuleId('rule.l1.normalise-to-100'),
          rulePackVersion: pack,
        ),
        confidence: Confidence.high,
      );

  FactualFinding finding({
    FactualFindingKind kind = FactualFindingKind.normalisation,
    NutrientId nutrient = NutrientId.protein,
    int scaled = 600,
    String message = 'msg.l1.normalisation',
  }) =>
      FactualFinding(
        kind: kind,
        subject: FindingNutrient(nutrient),
        value: ComputedFactualValue(computed(scaled)),
        confidence: Confidence.high,
        messageId: MessageId(message),
        derivation: Derivation(
          operation: DerivationOperation.normaliseTo100,
          inputs: <DerivationInput>[
            DerivationInput(
              field: FindingNutrient(nutrient),
              quantity: const Quantity.exact(180, Unit.gram),
              basis: Basis.perServe,
              confidence: Confidence.high,
            ),
          ],
          constantsUsed: const <ConstantUsed>[],
          result: Quantity.exact(scaled, Unit.gram),
        ),
      );

  ServingReconciliationResult reconciliation({
    ServingDiscrepancy discrepancy = ServingDiscrepancy.none,
    FieldState? serve,
  }) =>
      ServingReconciliationResult(
        declaredServe: serve ?? declared(3000),
        servesPerPack: declared(1000, unit: Unit.count),
        wholePackValues: const <NutrientField>[],
        discrepancy: discrepancy,
      );

  Layer1Result result({
    List<FactualFinding>? findings,
    ServingReconciliationResult? serving,
  }) =>
      Layer1Result(
        findings: findings ?? <FactualFinding>[finding()],
        servingReconciliation: serving ?? reconciliation(),
      );

  group('Layer1Result — construction', () {
    test('a minimal result carries no findings and a reconciliation', () {
      // An ingredients-only label computes nothing, and still reconciles —
      // reporting that the serving figures were not declared.
      final Layer1Result r = result(findings: const <FactualFinding>[]);
      expect(r.findings, isEmpty);
      expect(r.servingReconciliation, isNotNull);
    });

    test('findings are retained exactly as supplied', () {
      final FactualFinding f = finding();
      expect(
          result(findings: <FactualFinding>[f]).findings, <FactualFinding>[f]);
    });

    test('the reconciliation is retained by value', () {
      final ServingReconciliationResult s =
          reconciliation(discrepancy: ServingDiscrepancy.serveExceedsPack);
      expect(result(serving: s).servingReconciliation, s);
      expect(result(serving: s).servingReconciliation.discrepancy,
          ServingDiscrepancy.serveExceedsPack);
    });

    test('the reconciliation is not nullable', () {
      // Absence is expressed inside the reconciliation's own field states, not
      // by the aggregate omitting it. A null here would make "no serving
      // information" and "we did not look" the same value.
      final Layer1Result r =
          result(serving: reconciliation(serve: const NotDeclaredField()));
      expect(r.servingReconciliation.declaredServe, isA<NotDeclaredField>());
      expect(r.servingReconciliation, isA<ServingReconciliationResult>());
    });
  });

  group('Layer1Result — composition', () {
    test('all three finding kinds coexist in one result', () {
      final Layer1Result r = result(findings: <FactualFinding>[
        finding(),
        finding(
            kind: FactualFindingKind.rdaContribution,
            message: 'msg.l1.rda-contribution'),
        finding(
            kind: FactualFindingKind.servingReconciliation,
            message: 'msg.l1.serving-reconciliation'),
      ]);
      expect(
        r.findings.map((FactualFinding f) => f.kind).toList(),
        <FactualFindingKind>[
          FactualFindingKind.normalisation,
          FactualFindingKind.rdaContribution,
          FactualFindingKind.servingReconciliation,
        ],
      );
    });

    test('several nutrients may each carry their own finding', () {
      final Layer1Result r = result(findings: <FactualFinding>[
        finding(nutrient: NutrientId.protein),
        finding(nutrient: NutrientId.sodium),
        finding(nutrient: NutrientId.totalFat),
      ]);
      expect(r.findings, hasLength(3));
      expect(
        r.findings.map((FactualFinding f) => f.subject).toSet(),
        hasLength(3),
      );
    });

    test('the reconciliation stays separately accessible', () {
      // A servingReconciliation *finding* and the reconciliation *object* are
      // different things: the finding is one statement, the object holds the
      // four related figures.
      final Layer1Result r = result(findings: <FactualFinding>[
        finding(
            kind: FactualFindingKind.servingReconciliation,
            message: 'msg.l1.serving-reconciliation'),
      ]);
      expect(r.findings.single.kind, FactualFindingKind.servingReconciliation);
      expect(r.servingReconciliation.discrepancy, ServingDiscrepancy.none);
    });
  });

  group('Layer1Result — value semantics', () {
    test('two results with the same content compare equal', () {
      expect(result(), result());
      expect(result().hashCode, result().hashCode);
    });

    test('a different finding differs', () {
      expect(result(),
          isNot(result(findings: <FactualFinding>[finding(scaled: 700)])));
    });

    test('reordered findings differ', () {
      // Order is deterministic and part of the value (FR-PAR-02): the same
      // label must present its findings in the same order every run.
      final FactualFinding a = finding(nutrient: NutrientId.protein);
      final FactualFinding b = finding(nutrient: NutrientId.sodium);
      expect(
        result(findings: <FactualFinding>[a, b]),
        isNot(result(findings: <FactualFinding>[b, a])),
      );
    });

    test('a different number of findings differs', () {
      expect(result(), isNot(result(findings: const <FactualFinding>[])));
    });

    test('a different reconciliation differs', () {
      expect(
        result(),
        isNot(result(serving: reconciliation(serve: declared(4000)))),
      );
    });

    test('a different discrepancy alone differs', () {
      expect(
        result(),
        isNot(result(
            serving: reconciliation(
                discrepancy: ServingDiscrepancy.servesInconsistent))),
      );
    });

    test('equal results are interchangeable as set members', () {
      expect(<Layer1Result>{result(), result()}, hasLength(1));
    });
  });

  group('Layer1Result — immutability', () {
    test('mutating the caller\'s list does not change the result', () {
      final List<FactualFinding> supplied = <FactualFinding>[finding()];
      final Layer1Result r = result(findings: supplied);
      supplied.add(finding(nutrient: NutrientId.sodium));
      expect(r.findings, hasLength(1));
    });

    test('the stored list cannot be mutated through the object', () {
      expect(() => result().findings.add(finding()), throwsUnsupportedError);
    });

    test('finding order is preserved exactly as supplied', () {
      final FactualFinding a = finding(nutrient: NutrientId.energy);
      final FactualFinding b = finding(nutrient: NutrientId.protein);
      final FactualFinding c = finding(nutrient: NutrientId.sodium);
      expect(result(findings: <FactualFinding>[a, b, c]).findings,
          <FactualFinding>[a, b, c]);
    });
  });

  group('Layer1Result — it aggregates, it does not compute', () {
    test('it derives no finding from the reconciliation it holds', () {
      // The aggregate is handed its contents. A result carrying an
      // inconsistent reconciliation and no findings stays exactly that.
      final Layer1Result r = result(
        findings: const <FactualFinding>[],
        serving:
            reconciliation(discrepancy: ServingDiscrepancy.servesInconsistent),
      );
      expect(r.findings, isEmpty);
      expect(r.servingReconciliation.discrepancy,
          ServingDiscrepancy.servesInconsistent);
    });

    test('toString summarises without dumping every finding', () {
      expect(result().toString(), contains('1'));
      expect(result().toString(), contains('none'));
    });
  });
}
