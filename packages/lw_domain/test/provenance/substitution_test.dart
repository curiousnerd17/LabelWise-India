import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  group('SubstitutionKind — the six recorded transformations (DATA_MODEL 3.4)',
      () {
    test('FR-PAR-06 exactly the six kinds the data model names', () {
      expect(SubstitutionKind.values, hasLength(6));
      expect(
        SubstitutionKind.values.map((SubstitutionKind k) => k.name),
        <String>[
          'characterConfusion',
          'unitNormalisation',
          'energyConversion',
          'saltToSodium',
          'rounding',
          'whitespace',
        ],
      );
    });
  });

  group('Substitution — the chain from pixel to value (FR-EXP-07)', () {
    test('FR-PAR-06 records what changed, to what, and by which rule', () {
      final Substitution s = Substitution(
        kind: SubstitutionKind.characterConfusion,
        before: 'S',
        after: '5',
        appliedByRuleId: RuleId('rule.normalise.digit-s'),
      );
      expect(s.kind, SubstitutionKind.characterConfusion);
      expect(s.before, 'S');
      expect(s.after, '5');
      expect(s.appliedByRuleId, RuleId('rule.normalise.digit-s'));
    });

    test('FR-PAR-07 an energy conversion is recorded, not silently applied',
        () {
      // Converting kJ to kcal loses the original unless the substitution keeps
      // it. FR-PAR-07 requires the declared value to be retained.
      final Substitution s = Substitution(
        kind: SubstitutionKind.energyConversion,
        before: '418.4 kJ',
        after: '100.0 kcal',
        appliedByRuleId: RuleId('rule.unit.kj-to-kcal'),
      );
      expect(s.before, '418.4 kJ');
      expect(s.kind, SubstitutionKind.energyConversion);
    });

    test('FR-PAR-06 a substitution that changes nothing is rejected', () {
      // Recording a no-op transformation pads the audit trail without adding
      // information, which makes a real substitution harder to find.
      expect(
        () => Substitution(
          kind: SubstitutionKind.whitespace,
          before: 'Energy',
          after: 'Energy',
          appliedByRuleId: RuleId('rule.normalise.whitespace'),
        ),
        throwsArgumentError,
      );
    });

    test('P4 substitution compares by value', () {
      final Substitution a = Substitution(
        kind: SubstitutionKind.rounding,
        before: '2.505',
        after: '2.51',
        appliedByRuleId: RuleId('rule.round.half-away'),
      );
      final Substitution b = Substitution(
        kind: SubstitutionKind.rounding,
        before: '2.505',
        after: '2.51',
        appliedByRuleId: RuleId('rule.round.half-away'),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(Substitution(
          kind: SubstitutionKind.rounding,
          before: '2.505',
          after: '2.50',
          appliedByRuleId: RuleId('rule.round.half-away'),
        )),
      );
    });
  });
}
