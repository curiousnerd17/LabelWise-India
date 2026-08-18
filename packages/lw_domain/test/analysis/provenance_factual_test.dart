import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **Implementation M13 — the one approved addition to an existing API.**
///
/// Layer 1 computes values from a finished `ParsedLabel`. It is analysis, not a
/// parser stage, so no `PipelineStage` produced its output — and `PipelineStage`
/// must not grow a tenth member to pretend otherwise. Its nine values are the
/// parser stages, and `precedes()` is meaningful only while every member sits in
/// one pipeline; a `factualAnalysis` member would make that comparison span two
/// layers of the architecture.
///
/// `Provenance.producedByStage` is already documented as null "for a value that
/// no stage produced". This factory is the first caller for which that is
/// literally true.
void main() {
  final Version pack = Version(0, 1, 0);
  final RuleId rule = RuleId('rule.l1.rda-percent');

  Provenance factual({
    RuleId? id,
    Version? version,
    List<Substitution> substitutions = const <Substitution>[],
  }) =>
      Provenance.factual(
        parseRuleId: id ?? rule,
        rulePackVersion: version ?? pack,
        substitutions: substitutions,
      );

  group('Provenance.factual — what it records', () {
    test('the origin is derived, because the value was computed', () {
      // Not a fourth FieldOrigin. A Layer 1 value *is* computed from other
      // fields, so ADR-0010's rule that a derived confidence never exceeds the
      // meet of its inputs applies to it unchanged.
      expect(factual().origin, FieldOrigin.derived);
    });

    test('no pipeline stage produced it', () {
      // The point of the factory. Naming a stage here would be a lie that
      // survives into the explanation the user is eventually shown.
      expect(factual().producedByStage, isNull);
    });

    test('no parse strength, because no rule matched any text', () {
      // Signal S2 is a property of a *match*. Layer 1 matched nothing; it did
      // arithmetic. Supplying a strength would feed a confidence signal from an
      // event that never happened (ADR-0010, P1).
      expect(factual().parseStrength, isNull);
    });

    test('no source region, because the value was never on the label', () {
      expect(factual().sourceRegion, isNull);
    });

    test('the supplied rule id is preserved', () {
      expect(factual().parseRuleId, rule);
      expect(factual(id: RuleId('rule.l1.scale-to-pack')).parseRuleId,
          RuleId('rule.l1.scale-to-pack'));
    });

    test('the supplied rule pack version is preserved (FR-KB-02)', () {
      expect(factual().rulePackVersion, pack);
      expect(
          factual(version: Version(1, 2, 3)).rulePackVersion, Version(1, 2, 3));
    });

    test('substitutions default to empty and are never null', () {
      expect(factual().substitutions, isEmpty);
    });

    test('supplied substitutions are preserved in order', () {
      // Rounding is the substitution Layer 1 actually records: a per-100 figure
      // scaled to a pack is truncated to the unit's tracked precision.
      final List<Substitution> applied = <Substitution>[
        Substitution(
          kind: SubstitutionKind.rounding,
          before: '1200.4',
          after: '1200',
          appliedByRuleId: RuleId('rule.l1.scale-to-pack'),
        ),
        Substitution(
          kind: SubstitutionKind.saltToSodium,
          before: '1.0',
          after: '400',
          appliedByRuleId: RuleId('rule.l1.salt-to-sodium'),
        ),
      ];
      expect(factual(substitutions: applied).substitutions, applied);
    });

    test('the substitution list cannot be mutated after construction', () {
      // An audit trail a caller can append to after the fact is not an audit
      // trail.
      final Provenance p = factual(substitutions: <Substitution>[
        Substitution(
          kind: SubstitutionKind.rounding,
          before: '1200.4',
          after: '1200',
          appliedByRuleId: RuleId('rule.l1.scale-to-pack'),
        ),
      ]);
      expect(
        () => p.substitutions.add(
          Substitution(
            kind: SubstitutionKind.rounding,
            before: '2.5',
            after: '2',
            appliedByRuleId: RuleId('rule.l1.rda-percent'),
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('Provenance.factual — equality against the existing factories', () {
    test('two factual provenances with the same inputs compare equal', () {
      expect(factual(), factual());
      expect(factual().hashCode, factual().hashCode);
    });

    test('a different rule id compares unequal', () {
      expect(factual(), isNot(factual(id: RuleId('rule.l1.normalise-to-100'))));
    });

    test('a different pack version compares unequal', () {
      expect(factual(), isNot(factual(version: Version(0, 2, 0))));
    });

    test('factual is NOT equal to derived with the same rule and version', () {
      // The distinction that makes the new factory worth having: `derived`
      // names a stage and this does not, so the two cannot be confused by a
      // consumer comparing provenances.
      final Provenance derived = Provenance.derived(
        producedByStage: PipelineStage.confidenceAssignment,
        parseRuleId: rule,
        rulePackVersion: pack,
      );
      expect(factual(), isNot(derived));
      expect(derived.producedByStage, isNotNull);
      expect(factual().producedByStage, isNull);
    });

    test('factual is NOT equal to userSupplied, despite both lacking a stage',
        () {
      // Both leave producedByStage null; the origin is what separates them.
      // FR-CNF-12 turns on a user-supplied value never being mistaken for a
      // computed one.
      final Provenance user = Provenance.userSupplied(rulePackVersion: pack);
      expect(factual(), isNot(user));
      expect(user.origin, FieldOrigin.userSupplied);
      expect(factual().origin, FieldOrigin.derived);
    });
  });

  group('Provenance — the existing factories are unchanged (M1-M12)', () {
    // Not decoration. The factory added in M13 shares a private constructor
    // with these three, and the whole approval rested on them not moving.
    test('extracted still records stage, rule, strength and region', () {
      final Provenance p = Provenance.extracted(
        producedByStage: PipelineStage.fieldResolution,
        parseRuleId: RuleId('rule.resolve.synonym'),
        parseStrength: ParseStrength.exact,
        sourceRegion: RegionRef(left: 0, top: 0, right: 10, bottom: 10),
        rulePackVersion: pack,
      );
      expect(p.origin, FieldOrigin.extracted);
      expect(p.producedByStage, PipelineStage.fieldResolution);
      expect(p.parseStrength, ParseStrength.exact);
      expect(p.sourceRegion, isNotNull);
    });

    test('derived still requires and records a pipeline stage', () {
      final Provenance p = Provenance.derived(
        producedByStage: PipelineStage.unitNormalisation,
        parseRuleId: RuleId('rule.normalise.energy'),
        rulePackVersion: pack,
      );
      expect(p.origin, FieldOrigin.derived);
      expect(p.producedByStage, PipelineStage.unitNormalisation);
      expect(p.sourceRegion, isNull);
    });

    test('userSupplied still carries no rule, strength, stage or region', () {
      final Provenance p = Provenance.userSupplied(rulePackVersion: pack);
      expect(p.parseRuleId, isNull);
      expect(p.parseStrength, isNull);
      expect(p.producedByStage, isNull);
      expect(p.sourceRegion, isNull);
    });

    test('PipelineStage still has exactly the nine parser stages', () {
      // The ruling in one assertion: M13 added no member.
      expect(PipelineStage.values, hasLength(9));
      expect(PipelineStage.values.last, PipelineStage.confidenceAssignment);
      expect(PipelineStage.confidenceAssignment.ordinal, 9);
    });
  });

  group('Provenance.factual — the rule ids Layer 1 uses', () {
    test('each Layer 1 rule id matches the pack pattern', () {
      // `rule.<phase>.<slug>`, the convention every existing literal follows.
      for (final String id in <String>[
        'rule.l1.normalise-to-100',
        'rule.l1.scale-to-pack',
        'rule.l1.rda-percent',
        'rule.l1.serving-reconciliation',
      ]) {
        expect(RuleId.isValid(id), isTrue, reason: '$id is not a rule id');
        expect(factual(id: RuleId(id)).parseRuleId, RuleId(id));
      }
    });
  });
}
