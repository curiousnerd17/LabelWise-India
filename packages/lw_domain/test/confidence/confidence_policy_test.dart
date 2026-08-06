import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  InvariantResult invariant(InvariantOutcome outcome) => InvariantResult(
        invariantId: InvariantId.inv02,
        outcome: outcome,
        basis: Basis.per100g,
        participatingFields: const <InvariantSubject>[
          NutrientSubject(NutrientId.saturatedFat),
        ],
      );

  ConfidenceSignals signals({
    ParseStrength strength = ParseStrength.exact,
    OcrConfidence? ocr,
    List<InvariantOutcome> outcomes = const <InvariantOutcome>[],
  }) =>
      ConfidenceSignals(
        s2ParseStrength: strength,
        s1OcrConfidence: ocr,
        s3InvariantResults: <InvariantResult>[
          for (final InvariantOutcome o in outcomes) invariant(o),
        ],
      );

  group('ConfidenceSignals — the three inputs ADR-0010 names', () {
    test('FR-CNF-02 records all three signals', () {
      final ConfidenceSignals s = signals(
        strength: ParseStrength.normalised,
        ocr: OcrConfidence(8500),
        outcomes: <InvariantOutcome>[InvariantOutcome.passed],
      );
      expect(s.s2ParseStrength, ParseStrength.normalised);
      expect(s.s1OcrConfidence, OcrConfidence(8500));
      expect(s.s3InvariantResults, hasLength(1));
    });

    test('FR-CNF-03 an absent S1 is recorded, never defaulted', () {
      // FR-OCR-04: the adapter must report absence rather than substituting a
      // value. Defaulting to a number here would invent a signal the engine
      // never gave us.
      final ConfidenceSignals s = signals();
      expect(s.s1OcrConfidence, isNull);
      expect(s.s1WasAvailable, isFalse);
      expect(signals(ocr: OcrConfidence(9000)).s1WasAvailable, isTrue);
    });

    test('FR-CNF-04 no applicable invariant is an empty list, not an error',
        () {
      expect(signals().s3InvariantResults, isEmpty);
      expect(signals().anyInvariantFailed, isFalse);
      expect(signals().anyInvariantPassed, isFalse);
    });

    test('FR-CNF-05 a failed invariant is visible to the policy', () {
      final ConfidenceSignals s = signals(
        outcomes: <InvariantOutcome>[
          InvariantOutcome.passed,
          InvariantOutcome.failed,
        ],
      );
      expect(s.anyInvariantFailed, isTrue);
      expect(s.anyInvariantPassed, isTrue);
    });

    test('FR-CNF-14 indeterminate and inapplicable are neither pass nor fail',
        () {
      // ADR-0027: a label that declared a bound has not been caught out, and
      // it has not been vindicated either. No signal in either direction.
      final ConfidenceSignals s = signals(
        outcomes: <InvariantOutcome>[
          InvariantOutcome.indeterminate,
          InvariantOutcome.inapplicable,
        ],
      );
      expect(s.anyInvariantFailed, isFalse);
      expect(s.anyInvariantPassed, isFalse);
    });

    test('FR-KB-01 the results list is unmodifiable once built', () {
      final ConfidenceSignals s = signals();
      expect(
        () => s.s3InvariantResults.add(invariant(InvariantOutcome.passed)),
        throwsUnsupportedError,
      );
    });

    test('P4 compares by value, not identity', () {
      final ConfidenceSignals a = signals(ocr: OcrConfidence(8500));
      final ConfidenceSignals b = signals(ocr: OcrConfidence(8500));
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(signals()), reason: 'S1 presence is part of the value');
      expect(
        a,
        isNot(signals(
          strength: ParseStrength.heuristic,
          ocr: OcrConfidence(8500),
        )),
      );
    });

    test('FR-CNF-10 toString names the signals, never a percentage', () {
      expect(
        signals().toString(),
        'ConfidenceSignals(S1 absent, exact, 0 checks)',
      );
      expect(
        signals(ocr: OcrConfidence(8500), outcomes: <InvariantOutcome>[
          InvariantOutcome.passed,
        ]).toString(),
        'ConfidenceSignals(S1 present, exact, 1 checks)',
      );
    });
  });

  group('ConfidenceRule — one row of the rule pack assignment table', () {
    test('ADR-0012 a rule matching on a failed invariant fires on one', () {
      final ConfidenceRule r = ConfidenceRule(
        anyInvariantFailed: true,
        result: Confidence.low,
      );
      expect(
        r.matches(signals(outcomes: <InvariantOutcome>[
          InvariantOutcome.failed,
        ])),
        isTrue,
      );
      expect(r.matches(signals()), isFalse);
    });

    test('ADR-0012 a rule matching on parse strength fires on that strength',
        () {
      final ConfidenceRule r = ConfidenceRule(
        parseStrength: ParseStrength.heuristic,
        result: Confidence.low,
      );
      expect(r.matches(signals(strength: ParseStrength.heuristic)), isTrue);
      expect(r.matches(signals(strength: ParseStrength.exact)), isFalse);
    });

    test('ADR-0012 a rule with two conditions requires both', () {
      final ConfidenceRule r = ConfidenceRule(
        anyInvariantFailed: false,
        parseStrength: ParseStrength.exact,
        result: Confidence.high,
      );
      expect(r.matches(signals()), isTrue);
      expect(
        r.matches(signals(outcomes: <InvariantOutcome>[
          InvariantOutcome.failed,
        ])),
        isFalse,
      );
    });

    test('FR-PAR-17 a rule with no condition at all is rejected', () {
      // A rule that matches everything would silently shadow every rule after
      // it, which is the failure mode an ordered table is most prone to.
      expect(
        () => ConfidenceRule(result: Confidence.high),
        throwsArgumentError,
      );
    });

    test('P4 compares by value', () {
      final ConfidenceRule a = ConfidenceRule(
          parseStrength: ParseStrength.exact, result: Confidence.high);
      final ConfidenceRule b = ConfidenceRule(
          parseStrength: ParseStrength.exact, result: Confidence.high);
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
          a,
          isNot(ConfidenceRule(
              parseStrength: ParseStrength.exact, result: Confidence.medium)));
      expect(a.toString(), 'ConfidenceRule(-> high)');
    });
  });

  group('ConfidencePolicy — the assignment table, held as data (ADR-0010)', () {
    test('ADR-0010 the defaults mirror rulepack/rules/confidence.json', () {
      // Four rules, in the order the pack states them. Order is the whole
      // semantics of a first-match table.
      expect(ConfidencePolicy.defaults.rules, hasLength(4));
      expect(
        ConfidencePolicy.defaults.rules.map((ConfidenceRule r) => r.result),
        <Confidence>[
          Confidence.low,
          Confidence.high,
          Confidence.medium,
          Confidence.low,
        ],
      );
    });

    test('FR-CNF-05 a failed invariant caps below HIGH whatever S2 says', () {
      // Absolute. The first rule in the pack exists precisely so that an
      // EXACT parse cannot outvote arithmetic that does not reconcile.
      expect(
        ConfidencePolicy.defaults.classify(signals(
          strength: ParseStrength.exact,
          outcomes: <InvariantOutcome>[InvariantOutcome.failed],
        )),
        Confidence.low,
      );
    });

    test('ADR-0010 parse strength decides when no invariant failed', () {
      expect(
        ConfidencePolicy.defaults
            .classify(signals(strength: ParseStrength.exact)),
        Confidence.high,
      );
      expect(
        ConfidencePolicy.defaults
            .classify(signals(strength: ParseStrength.normalised)),
        Confidence.medium,
      );
      expect(
        ConfidencePolicy.defaults
            .classify(signals(strength: ParseStrength.heuristic)),
        Confidence.low,
      );
    });

    test('FR-CNF-14 an indeterminate invariant does not cap', () {
      // The distinction FR-CNF-14 exists for: a bound that cannot settle the
      // comparison must not be treated as a failure.
      expect(
        ConfidencePolicy.defaults.classify(signals(
          strength: ParseStrength.exact,
          outcomes: <InvariantOutcome>[InvariantOutcome.indeterminate],
        )),
        Confidence.high,
      );
    });

    test('FR-CNF-03 classification works with S1 absent', () {
      // ADR-0010 ships S2 and S3 without waiting on the Q2 spike.
      expect(
        ConfidencePolicy.defaults.classify(signals(ocr: null)),
        Confidence.high,
      );
    });

    test('FR-CNF-06 the first matching rule wins, deterministically', () {
      final ConfidencePolicy p = ConfidencePolicy(<ConfidenceRule>[
        ConfidenceRule(
            parseStrength: ParseStrength.exact, result: Confidence.medium),
        ConfidenceRule(
            parseStrength: ParseStrength.exact, result: Confidence.high),
      ]);
      expect(p.classify(signals()), Confidence.medium);
    });

    test('P1 an unclassifiable field falls to LOW, never to HIGH', () {
      // Fail-safe. A value the policy cannot speak to is a value the user
      // should check by hand; silently trusting it would be the one failure
      // this product exists to avoid.
      final ConfidencePolicy empty = ConfidencePolicy(const <ConfidenceRule>[]);
      expect(empty.classify(signals()), Confidence.low);
    });

    test('ADR-0013 a caller-supplied policy replaces the default wholesale',
        () {
      final ConfidencePolicy strict = ConfidencePolicy(<ConfidenceRule>[
        ConfidenceRule(
            parseStrength: ParseStrength.exact, result: Confidence.medium),
      ]);
      expect(strict.classify(signals()), Confidence.medium);
    });

    test('FR-KB-01 the rule list is unmodifiable once built', () {
      expect(
        () => ConfidencePolicy.defaults.rules.add(
          ConfidenceRule(
              parseStrength: ParseStrength.exact, result: Confidence.high),
        ),
        throwsUnsupportedError,
      );
      expect(ConfidencePolicy.defaults.toString(), 'ConfidencePolicy(4 rules)');
    });
  });
}
