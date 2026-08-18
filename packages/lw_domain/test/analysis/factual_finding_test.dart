import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **One factual statement about the label.**
///
/// These tests exercise the model, not the engine: that every field is
/// carried, that findings compare by value, and — structurally — that there is
/// nowhere in the type for a judgement to live.
void main() {
  final Version pack = Version(0, 1, 0);

  FieldState derived(int scaled, {Unit unit = Unit.gram}) => DerivedField(
        quantity: Quantity.exact(scaled, unit),
        basis: Basis.per100g,
        provenance: Provenance.factual(
          parseRuleId: RuleId('rule.l1.normalise-to-100'),
          rulePackVersion: pack,
        ),
        confidence: Confidence.high,
      );

  Derivation derivation({
    DerivationOperation operation = DerivationOperation.normaliseTo100,
  }) =>
      Derivation(
        operation: operation,
        inputs: const <DerivationInput>[
          DerivationInput(
            field: FindingNutrient(NutrientId.protein),
            quantity: Quantity.exact(180, Unit.gram),
            basis: Basis.perServe,
            confidence: Confidence.high,
          ),
        ],
        constantsUsed: const <ConstantUsed>[],
        result: const Quantity.exact(600, Unit.gram),
      );

  FactualFinding finding({
    FactualFindingKind kind = FactualFindingKind.normalisation,
    FindingSubject? subject,
    FactualValue? value,
    Confidence confidence = Confidence.high,
    String message = 'msg.l1.normalisation',
    Derivation? derivationOf,
    bool withDerivation = true,
  }) =>
      FactualFinding(
        kind: kind,
        subject: subject ?? const FindingNutrient(NutrientId.protein),
        value: value ?? ComputedFactualValue(derived(600)),
        confidence: confidence,
        messageId: MessageId(message),
        derivation: withDerivation ? (derivationOf ?? derivation()) : null,
      );

  group('FactualFindingKind — exactly the three M13 can emit', () {
    test('all three exist and nothing else', () {
      expect(FactualFindingKind.values, <FactualFindingKind>[
        FactualFindingKind.normalisation,
        FactualFindingKind.rdaContribution,
        FactualFindingKind.servingReconciliation,
      ]);
    });

    test('declarationGap and additiveIdentification are absent', () {
      // FR-L1-06 and FR-L1-07 are deferred, and a kind nothing can emit would
      // put an unreachable case into every switch that reads a finding.
      expect(FactualFindingKind.values, hasLength(3));
      expect(
        FactualFindingKind.values.map((FactualFindingKind k) => k.name),
        isNot(anyElement(anyOf(
          contains('declaration'),
          contains('additive'),
        ))),
      );
    });
  });

  group('FactualFinding — every field is carried', () {
    test('kind, subject, value, confidence and message id', () {
      final FactualFinding f = finding();
      expect(f.kind, FactualFindingKind.normalisation);
      expect(f.subject, const FindingNutrient(NutrientId.protein));
      expect(f.value, isA<ComputedFactualValue>());
      expect(f.confidence, Confidence.high);
      expect(f.messageId, MessageId('msg.l1.normalisation'));
    });

    test('a derivation is exposed when one was performed (FR-EXP-09)', () {
      final FactualFinding f = finding();
      expect(f.derivation, isNotNull);
      expect(f.derivation!.operation, DerivationOperation.normaliseTo100);
      expect(f.derivation!.result, const Quantity.exact(600, Unit.gram));
    });

    test('a serving figure is as valid a subject as a nutrient', () {
      final FactualFinding f = finding(
        kind: FactualFindingKind.servingReconciliation,
        subject: const FindingServing(ServingField.netQuantity),
        message: 'msg.l1.serving-reconciliation',
      );
      expect(f.subject, const FindingServing(ServingField.netQuantity));
    });

    test('a refused calculation carries no derivation', () {
      // Null is a statement: no arithmetic completed, so there is no result to
      // describe. Fabricating one would record a calculation that never
      // happened.
      final FactualFinding f = finding(
        value: const NotComputableFactualValue(),
        message: 'msg.l1.not-computable',
        withDerivation: false,
      );
      expect(f.derivation, isNull);
      expect(f.value, const NotComputableFactualValue());
    });

    test('a missing denominator carries no derivation either', () {
      final FactualFinding f = finding(
        kind: FactualFindingKind.rdaContribution,
        subject: const FindingNutrient(NutrientId.dietaryFibre),
        value: const NoDenominatorFactualValue(),
        message: 'msg.l1.rda-no-denominator',
        withDerivation: false,
      );
      expect(f.derivation, isNull);
      expect(f.value, const NoDenominatorFactualValue());
      expect(f.kind, FactualFindingKind.rdaContribution,
          reason: 'the finding is still about the RDA question');
    });
  });

  group('FactualFinding — value semantics', () {
    test('two findings with the same content compare equal', () {
      expect(finding(), finding());
      expect(finding().hashCode, finding().hashCode);
    });

    test('a different kind differs', () {
      expect(
          finding(), isNot(finding(kind: FactualFindingKind.rdaContribution)));
    });

    test('a different subject differs', () {
      expect(finding(),
          isNot(finding(subject: const FindingNutrient(NutrientId.sodium))));
      expect(
          finding(),
          isNot(finding(
              subject: const FindingServing(ServingField.servingSize))));
    });

    test('a different value differs', () {
      expect(
          finding(), isNot(finding(value: ComputedFactualValue(derived(700)))));
      expect(
          finding(), isNot(finding(value: const NotComputableFactualValue())));
    });

    test('a different confidence differs', () {
      expect(finding(), isNot(finding(confidence: Confidence.low)));
    });

    test('a different message id differs', () {
      expect(finding(), isNot(finding(message: 'msg.l1.whole-pack')));
    });

    test('a different derivation differs', () {
      expect(
        finding(),
        isNot(finding(
            derivationOf:
                derivation(operation: DerivationOperation.scaleToPack))),
      );
    });

    test('present and absent derivation differ', () {
      expect(finding(), isNot(finding(withDerivation: false)));
    });

    test('findings are usable as set members', () {
      final Set<FactualFinding> seen = <FactualFinding>{
        finding(),
        finding(),
        finding(kind: FactualFindingKind.rdaContribution),
      };
      expect(seen, hasLength(2));
    });
  });

  group('FactualFinding — the M13 catalogue entries it names', () {
    test('every Layer 1 message id is a valid MessageId', () {
      for (final String id in <String>[
        'msg.l1.normalisation',
        'msg.l1.whole-pack',
        'msg.l1.rda-contribution',
        'msg.l1.rda-no-denominator',
        'msg.l1.serving-reconciliation',
        'msg.l1.serves-inconsistent',
        'msg.l1.serve-exceeds-pack',
        'msg.l1.not-computable',
      ]) {
        expect(MessageId.isValid(id), isTrue,
            reason: '$id is not a message id');
        expect(finding(message: id).messageId, MessageId(id));
      }
    });

    test('the domain holds an identifier, never display text (FR-LOC-01)', () {
      // A finding carries `msg.l1.normalisation`, not the English sentence.
      expect(finding().messageId.value, startsWith('msg.'));
      expect(finding().toString(), contains('msg.l1.normalisation'));
    });
  });

  group('FactualFinding — factual by construction (FR-L1-01)', () {
    test('there is no field in which a judgement could be stored', () {
      // The constraint is structural, not editorial. A finding has a kind, a
      // subject, a value, a confidence, a message id and a derivation — no
      // severity, no classification, no recommendation, no comparison. Layer 2
      // adds those to its own type (DATA_MODEL 6.3), which requires an
      // Explanation this milestone does not build.
      final FactualFinding f = finding();
      expect(f.kind, isA<FactualFindingKind>());
      expect(f.value, isA<FactualValue>());
      expect(f.confidence, isA<Confidence>());
      expect(f.derivation, isA<Derivation?>());
    });

    test('the three kinds are all statements of fact or arithmetic', () {
      // Read the names: what was restated, what share of a daily value, how
      // the serving figures reconcile. None asserts anything about health.
      expect(
        FactualFindingKind.values
            .map((FactualFindingKind k) => k.name)
            .toList(),
        <String>['normalisation', 'rdaContribution', 'servingReconciliation'],
      );
    });

    test('toString names a confidence level, never a number (FR-CNF-10)', () {
      expect(finding().toString(), contains('high'));
      expect(finding().toString(), isNot(matches(RegExp(r'\d+%'))));
    });
  });
}
