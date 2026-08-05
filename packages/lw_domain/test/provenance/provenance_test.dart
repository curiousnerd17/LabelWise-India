import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  final Version pack = Version(0, 1, 0);
  final RuleId rule = RuleId('rule.synonym.energy');
  final RegionRef region = RegionRef(
    left: 1000,
    top: 2000,
    right: 4000,
    bottom: 2500,
  );

  group('RuleId — identity, not an arbitrary string (FR-PAR-13)', () {
    test('FR-PAR-13 accepts the rule pack identifier pattern', () {
      expect(RuleId('rule.synonym.energy').value, 'rule.synonym.energy');
      expect(RuleId('rule.unit.kj-to-kcal').value, 'rule.unit.kj-to-kcal');
    });

    test('FR-PAR-13 rejects an identifier the rule pack could not contain', () {
      // The pattern is fixed by rulepack/schema/common.schema.json. A rule
      // reference that cannot exist in the pack is a defect at construction,
      // not a dangling reference discovered later.
      expect(() => RuleId('synonym.energy'), throwsFormatException);
      expect(() => RuleId('rule.Energy'), throwsFormatException);
      expect(() => RuleId('rule.'), throwsFormatException);
      expect(() => RuleId(''), throwsFormatException);
    });

    test('FR-PAR-13 compares by value', () {
      expect(RuleId('rule.a'), RuleId('rule.a'));
      expect(RuleId('rule.a').hashCode, RuleId('rule.a').hashCode);
      expect(RuleId('rule.a'), isNot(RuleId('rule.b')));
    });
  });

  group('PipelineStage — forward-only ordering (ARCHITECTURE 6.2)', () {
    test('FR-PAR-01 stages carry S1..S8 and exclude the port boundary S0', () {
      expect(PipelineStage.values, hasLength(8));
      expect(PipelineStage.values.first, PipelineStage.normalisation);
      expect(PipelineStage.values.last, PipelineStage.confidenceAssignment);
    });

    test('FR-PAR-01 ordinals ascend so a later stage is detectable', () {
      // "No stage may consult a later stage" is checkable only if the order is
      // part of the type rather than a convention.
      for (int i = 1; i < PipelineStage.values.length; i++) {
        expect(
          PipelineStage.values[i].ordinal,
          greaterThan(PipelineStage.values[i - 1].ordinal),
        );
      }
      expect(
        PipelineStage.fieldResolution
            .precedes(PipelineStage.confidenceAssignment),
        isTrue,
      );
      expect(
        PipelineStage.confidenceAssignment
            .precedes(PipelineStage.fieldResolution),
        isFalse,
      );
    });
  });

  group('ParseStrength — signal S2 (ADR-0010)', () {
    test('FR-PAR-13 exactly the three strengths the rule pack emits', () {
      // rulepack/schema/synonyms.schema.json grades every pattern as one of
      // these. A fourth value here would be unrepresentable in the pack.
      expect(ParseStrength.values, hasLength(3));
      expect(
        ParseStrength.values.map((ParseStrength s) => s.name),
        <String>['exact', 'normalised', 'heuristic'],
      );
    });
  });

  group('Provenance — named constructors enforce the optionals (M2)', () {
    test('FR-PAR-13 an extracted value records its rule, strength and region',
        () {
      final Provenance p = Provenance.extracted(
        producedByStage: PipelineStage.fieldResolution,
        parseRuleId: rule,
        parseStrength: ParseStrength.exact,
        sourceRegion: region,
        rulePackVersion: pack,
      );
      expect(p.origin, FieldOrigin.extracted);
      expect(p.parseRuleId, rule);
      expect(p.sourceRegion, region);
      expect(p.parseStrength, ParseStrength.exact);
      expect(p.substitutions, isEmpty);
    });

    test('FR-KB-02 every provenance records the rule pack version', () {
      final Provenance p = Provenance.derived(
        producedByStage: PipelineStage.unitNormalisation,
        parseRuleId: rule,
        rulePackVersion: pack,
      );
      expect(p.rulePackVersion, pack);
    });

    test('FR-CNF-12 a user-supplied value has no rule and no region', () {
      // Nothing produced it and it has no position on the label. Both optionals
      // are absent by construction rather than by convention.
      final Provenance p = Provenance.userSupplied(rulePackVersion: pack);
      expect(p.origin, FieldOrigin.userSupplied);
      expect(p.parseRuleId, isNull);
      expect(p.sourceRegion, isNull);
      expect(p.producedByStage, isNull);
    });

    test('FR-EXP-09 a derived value has no source region', () {
      // A computed value was never on the label, so it cannot point at it.
      final Provenance p = Provenance.derived(
        producedByStage: PipelineStage.unitNormalisation,
        parseRuleId: rule,
        rulePackVersion: pack,
      );
      expect(p.origin, FieldOrigin.derived);
      expect(p.sourceRegion, isNull);
    });

    test('FR-PAR-13 substitutions default to empty, never null', () {
      final Provenance p = Provenance.extracted(
        producedByStage: PipelineStage.normalisation,
        parseRuleId: rule,
        parseStrength: ParseStrength.normalised,
        sourceRegion: region,
        rulePackVersion: pack,
      );
      expect(p.substitutions, isEmpty);
    });

    test('FR-PAR-13 recorded substitutions are exposed in order', () {
      final Substitution first = Substitution(
        kind: SubstitutionKind.characterConfusion,
        before: 'O',
        after: '0',
        appliedByRuleId: RuleId('rule.normalise.digit-o'),
      );
      final Substitution second = Substitution(
        kind: SubstitutionKind.unitNormalisation,
        before: 'gm',
        after: 'g',
        appliedByRuleId: RuleId('rule.unit.gram'),
      );
      final Provenance p = Provenance.extracted(
        producedByStage: PipelineStage.unitNormalisation,
        parseRuleId: rule,
        parseStrength: ParseStrength.normalised,
        sourceRegion: region,
        rulePackVersion: pack,
        substitutions: <Substitution>[first, second],
      );
      expect(p.substitutions, <Substitution>[first, second]);
    });

    test('FR-PAR-13 the substitution list is unmodifiable', () {
      final Provenance p = Provenance.userSupplied(rulePackVersion: pack);
      expect(
        () => p.substitutions.add(
          Substitution(
            kind: SubstitutionKind.rounding,
            before: '1',
            after: '2',
            appliedByRuleId: RuleId('rule.x'),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('P4 provenance compares by value', () {
      final Provenance a = Provenance.userSupplied(rulePackVersion: pack);
      final Provenance b = Provenance.userSupplied(rulePackVersion: pack);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('RegionRef — normalised bounding box (Q2)', () {
    test('FR-OCR-03 coordinates are normalised, carrying no pixel dimensions',
        () {
      // The domain never holds image dimensions (ADR-0007). Coordinates are
      // scaled integers in 0..10000, matching ADR-0021's discipline.
      expect(region.left, 1000);
      expect(region.right, 4000);
      expect(RegionRef.coordinateScale, 10000);
    });

    test('FR-OCR-03 rejects an inverted or out-of-range box', () {
      expect(
        () => RegionRef(left: 4000, top: 0, right: 1000, bottom: 100),
        throwsArgumentError,
      );
      expect(
        () => RegionRef(left: 0, top: 200, right: 100, bottom: 100),
        throwsArgumentError,
      );
      expect(
        () => RegionRef(left: -1, top: 0, right: 100, bottom: 100),
        throwsArgumentError,
      );
      expect(
        () => RegionRef(left: 0, top: 0, right: 10001, bottom: 100),
        throwsArgumentError,
      );
    });

    test('FR-OCR-03 a degenerate box is permitted', () {
      // OCR can legitimately return a zero-width element. Rejecting it would
      // discard a real recognition result.
      expect(
        () => RegionRef(left: 100, top: 100, right: 100, bottom: 100),
        returnsNormally,
      );
    });

    test('P4 region compares by value', () {
      expect(
        RegionRef(left: 1, top: 2, right: 3, bottom: 4),
        RegionRef(left: 1, top: 2, right: 3, bottom: 4),
      );
    });
  });
}
