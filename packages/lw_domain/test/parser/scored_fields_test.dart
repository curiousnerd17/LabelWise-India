import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  Provenance provenance() => Provenance.extracted(
        producedByStage: PipelineStage.confidenceAssignment,
        parseRuleId: RuleId('rule.resolve.synonym'),
        parseStrength: ParseStrength.exact,
        sourceRegion: box(0, 0, 100, 60),
        rulePackVersion: Version(1, 0, 0),
      );

  FieldState extracted(Confidence confidence) => ExtractedField(
        quantity: const Quantity.exact(800, Unit.gram),
        basis: Basis.per100g,
        provenance: provenance(),
        confidence: confidence,
      );

  ConfidenceSignals signals({
    ParseStrength strength = ParseStrength.exact,
  }) =>
      ConfidenceSignals(s2ParseStrength: strength);

  ScoredField scored({
    NutrientId nutrient = NutrientId.protein,
    Basis basis = Basis.per100g,
    Confidence confidence = Confidence.high,
    List<int> at = const <int>[3, 4],
  }) =>
      ScoredField(
        nutrient: nutrient,
        basis: basis,
        state: extracted(confidence),
        signals: signals(),
        region: box(0, 0, 100, 60),
        sourceIndices: at,
      );

  group('ScoredField — a value, its level, and what decided it', () {
    test('FR-CNF-01 records the field, its state and the signals used', () {
      final ScoredField f = scored();
      expect(f.nutrient, NutrientId.protein);
      expect(f.basis, Basis.per100g);
      expect(f.state.confidenceOrNull, Confidence.high);
      expect(f.signals.s2ParseStrength, ParseStrength.exact);
      expect(f.sourceIndices, <int>[3, 4]);
    });

    test('FR-CNF-01 the assigned level is reachable without a cast', () {
      // Callers ask "how much should I trust this" constantly; making them
      // pattern-match a FieldState union for it would guarantee that some
      // call site skips the question.
      expect(scored().confidence, Confidence.high);
      expect(scored(confidence: Confidence.low).confidence, Confidence.low);
    });

    test('FR-CNF-12 a user-supplied field reports no inferred confidence', () {
      // MI-02: UserSuppliedField has no confidence member at all. Propagation
      // still treats it as maximally trustworthy (ARCHITECTURE 7.4), but the
      // assigned level is genuinely absent.
      final ScoredField f = ScoredField(
        nutrient: NutrientId.protein,
        basis: Basis.per100g,
        state: UserSuppliedField(
          quantity: const Quantity.exact(800, Unit.gram),
          basis: Basis.per100g,
          provenance:
              Provenance.userSupplied(rulePackVersion: Version(1, 0, 0)),
        ),
        signals: signals(),
        region: box(0, 0, 100, 60),
        sourceIndices: const <int>[0],
      );
      expect(f.confidence, isNull);
      expect(f.state.propagatedConfidence, Confidence.high);
    });

    test('FR-PAR-13 a field tracing to no element is rejected', () {
      expect(
        () => scored(at: const <int>[]),
        throwsArgumentError,
      );
    });

    test('P4 compares by value, not identity', () {
      final ScoredField a = scored();
      final ScoredField b = scored();
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(scored(confidence: Confidence.medium)));
      expect(a, isNot(scored(basis: Basis.perServe)),
          reason: 'the same nutrient on another basis is another field');
    });

    test('FR-CNF-10 toString names the level, never a percentage', () {
      expect(scored().toString(), 'ScoredField(protein, per100g, high)');
    });
  });

  group('ScoredFields — the S8 output', () {
    ScoredFields output({
      List<ScoredField> fields = const <ScoredField>[],
      ScanConfidence scan = ScanConfidence.high,
    }) =>
        ScoredFields(
          fields: fields,
          scanConfidence: scan,
          nutritionPanelPresent: true,
        );

    test('FR-PAR-13 the output records the stage that produced it', () {
      expect(output().producedByStage, PipelineStage.confidenceAssignment);
    });

    test('FR-CNF-07 the scan level is carried alongside the field levels', () {
      expect(output(scan: ScanConfidence.partial).scanConfidence,
          ScanConfidence.partial);
    });

    test('FR-CNF-01 a field level is reachable by nutrient and basis', () {
      final ScoredFields o = output(fields: <ScoredField>[
        scored(),
        scored(basis: Basis.perServe, confidence: Confidence.medium),
      ]);
      expect(
          o.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.high);
      expect(o.confidenceFor(NutrientId.protein, Basis.perServe),
          Confidence.medium);
      expect(o.confidenceFor(NutrientId.sodium, Basis.per100g), isNull,
          reason: 'an absent field has no level, rather than a default one');
    });

    test('FR-ERR-03 unresolved candidates and invariants pass through', () {
      final UnresolvedCandidate u = UnresolvedCandidate(
        reason: UnresolvedReason.noMatchingRule,
        labelText: 'Riboflavin',
        region: box(0, 0, 10, 10),
        sourceIndices: const <int>[9],
      );
      final InvariantResult r = InvariantResult(
        invariantId: InvariantId.inv02,
        outcome: InvariantOutcome.failed,
        basis: Basis.per100g,
        participatingFields: const <InvariantSubject>[
          NutrientSubject(NutrientId.saturatedFat),
        ],
      );
      final ScoredFields o = ScoredFields(
        unresolved: <UnresolvedCandidate>[u],
        invariantResults: <InvariantResult>[r],
        scanConfidence: ScanConfidence.low,
        nutritionPanelPresent: true,
      );
      expect(o.unresolved, <UnresolvedCandidate>[u]);
      expect(o.invariantResults, <InvariantResult>[r]);
    });

    test('FR-PAR-10 ingredient tokens pass through untouched', () {
      final IngredientToken t = IngredientToken(
        position: 1,
        rawText: 'Wheat flour',
        region: box(0, 0, 10, 10),
        sourceIndices: const <int>[5],
        parseStrength: ParseStrength.exact,
      );
      final ScoredFields o = ScoredFields(
        ingredientTokens: <IngredientToken>[t],
        scanConfidence: ScanConfidence.partial,
        ingredientListPresent: true,
      );
      expect(o.ingredientTokens, <IngredientToken>[t]);
    });

    test('FR-PAR-13 source indices span every carried part, ascending', () {
      final ScoredFields o = ScoredFields(
        fields: <ScoredField>[
          scored(at: const <int>[4])
        ],
        unresolved: <UnresolvedCandidate>[
          UnresolvedCandidate(
            reason: UnresolvedReason.noMatchingRule,
            labelText: 'x',
            region: box(0, 0, 10, 10),
            sourceIndices: const <int>[1],
          ),
        ],
        scanConfidence: ScanConfidence.partial,
        nutritionPanelPresent: true,
      );
      expect(o.sourceIndices, <int>[1, 4]);
    });

    test('FR-KB-01 every carried list is unmodifiable once built', () {
      final ScoredFields o = output();
      expect(() => o.fields.add(scored()), throwsUnsupportedError);
      expect(
          () => o.invariantResults.add(InvariantResult(
                invariantId: InvariantId.inv01,
                outcome: InvariantOutcome.passed,
                participatingFields: const <InvariantSubject>[
                  NutrientSubject(NutrientId.protein),
                ],
              )),
          throwsUnsupportedError);
    });

    test('FR-CNF-10 toString summarises without a percentage', () {
      expect(
        output(fields: <ScoredField>[scored()]).toString(),
        'ScoredFields(1 scored, scan high)',
      );
    });
  });
}
