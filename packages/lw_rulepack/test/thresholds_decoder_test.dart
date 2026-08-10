import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/lw_rulepack.dart';
import 'package:test/test.dart';

import 'pack_fixture.dart';

/// `rules/thresholds.json` ships empty because Layer 2 is v0.2 scope
/// (ADR-0025), so every other test in this package loads a pack with no
/// advisory rules in it — and the entire rule decode path went unexercised.
///
/// The schema for these rules is fully specified and P-PACK names thresholds as
/// a load operation, so this is a real contract with no test behind it rather
/// than dead code. A pack author adding the first threshold in v0.2 should not
/// be the one who discovers whether the decoder works.
///
/// **Nothing here evaluates a threshold.** These tests assert decoding and
/// reference resolution only; comparing a declared value against a threshold is
/// Layer 2 work and is not part of this milestone.
void main() {
  const String ruleMessage = 'msg.finding.sodium-high';

  /// A catalogue with a finding message, so a rule's `messageId` resolves.
  ///
  /// Supplied as an override rather than added to the fixture defaults: other
  /// tests assert the default catalogue's size, and widening it there would
  /// change assertions this milestone has no business touching.
  const String messagesWithFinding = '''
{"locale":"en","reviewed":true,"messages":{
  "msg.category.biscuits":"Biscuits",
  "msg.category.beverages":"Packaged beverages",
  "msg.additive.ins-100":"A yellow colour taken from turmeric.",
  "msg.additive.ins-322":"An emulsifier that keeps oil and water mixed.",
  "$ruleMessage":"High in sodium."
}}''';

  Future<RulePackResult<RulePack>> loadWithRules(
    String rules, {
    String messages = messagesWithFinding,
  }) =>
      RulePackLoader(
        source: PackFixture.pack(
          overrides: <String, String>{
            'rules/thresholds.json': '{"rules":[$rules]}',
            'messages/en.json': messages,
          },
        ),
        implementedSchemaMajor: 1,
        applicationVersion: Version(0, 1, 0),
      ).load();

  String rule({
    String id = 'rule.sodium.high',
    String extra = '',
    String threshold = '{"scaledValue":6000,"unit":"MILLIGRAM"}',
    String sourceRefs = '["src.fssai.labelling.2020"]',
    String messageId = ruleMessage,
  }) =>
      '''
{"ruleId":"$id","ruleVersion":{"major":1,"minor":0,"patch":0},
 "nutrient":"SODIUM","basis":"PER_100G","comparator":"GTE",
 "threshold":$threshold,"classification":"HIGH_IN",
 "sourceRefs":$sourceRefs,"messageId":"$messageId"$extra}''';

  group('thresholds — a rule decodes into a typed record', () {
    test('P-PACK every declared field survives decoding', () async {
      final RulePackResult<RulePack> r = await loadWithRules(rule());
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      final AdvisoryRule decoded = r.valueOrNull!.advisoryRules.rules.single;
      expect(decoded.ruleId, RuleId('rule.sodium.high'));
      expect(decoded.ruleVersion, Version(1, 0, 0));
      expect(decoded.nutrient, NutrientId.sodium);
      expect(decoded.basis, Basis.per100g);
      expect(decoded.comparator, ThresholdComparator.gte);
      expect(decoded.threshold, const Quantity.exact(6000, Unit.milligram));
      expect(decoded.classification, AdvisoryClassification.highIn);
      expect(decoded.messageId, MessageId(ruleMessage));
      expect(
          decoded.sourceRefs, <SourceId>[SourceId('src.fssai.labelling.2020')]);
    });

    test('FR-CAT-04 an omitted selector admits every category', () async {
      // A rule with no stated scoping applies everywhere, including to a
      // product whose category is unknown (FR-CAT-05). Defaulting to an empty
      // include list would silently disable every unscoped rule.
      final RulePackResult<RulePack> r = await loadWithRules(rule());
      final CategorySelector s =
          r.valueOrNull!.advisoryRules.rules.single.categorySelector;
      expect(s.admits(CategoryId('cat.biscuits')), isTrue);
      expect(s.admits(null), isTrue);
    });

    test('FR-KB-11 a declarative selector scopes a rule to categories',
        () async {
      // The mechanism that keeps category logic out of Dart entirely.
      const String selector = ',"categorySelector":{"appliesToAll":false,'
          '"includeCategories":["cat.chips","cat.namkeen"],'
          '"excludeCategories":["cat.namkeen"]}';
      final RulePackResult<RulePack> r =
          await loadWithRules(rule(extra: selector));
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      final CategorySelector s =
          r.valueOrNull!.advisoryRules.rules.single.categorySelector;
      expect(s.appliesToAll, isFalse);
      expect(s.admits(CategoryId('cat.chips')), isTrue);
      expect(s.admits(CategoryId('cat.namkeen')), isFalse,
          reason: 'exclusion outranks inclusion');
      expect(s.admits(CategoryId('cat.biscuits')), isFalse);
      expect(s.admits(null), isFalse,
          reason: 'a rule scoped to named categories cannot fire for a '
              'product we cannot place');
    });

    test('FR-L2-08 severity weight is carried when stated', () async {
      final RulePackResult<RulePack> r =
          await loadWithRules(rule(extra: ',"severityWeight":2.5'));
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(r.valueOrNull!.advisoryRules.rules.single.severityWeight, 2.5);
    });

    test('ADR-0027 a threshold may be a bound, not only a point', () async {
      // MI-17's reading half: an absent qualifier means EXACT, and a present
      // one is honoured. A threshold stated as a bound must not be silently
      // flattened to a point — that is the coercion MI-16 forbids.
      final RulePackResult<RulePack> r = await loadWithRules(rule(
        threshold: '{"scaledValue":50,"unit":"GRAM","qualifier":"LESS_THAN"}',
      ));
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      final Quantity t = r.valueOrNull!.advisoryRules.rules.single.threshold;
      expect(t.qualifier, Qualifier.lessThan);
      expect(t, const Quantity.lessThan(50, Unit.gram));
      expect(t, isNot(const Quantity.exact(50, Unit.gram)),
          reason: 'equality includes the qualifier');
    });

    test('FR-PAR-02 rules keep pack order', () async {
      final RulePackResult<RulePack> r = await loadWithRules(
        '${rule(id: 'rule.z')},${rule(id: 'rule.a')}',
      );
      expect(
        r.valueOrNull!.advisoryRules.rules
            .map((AdvisoryRule x) => x.ruleId.value),
        <String>['rule.z', 'rule.a'],
      );
    });
  });

  group('thresholds — refusals', () {
    test('FR-KB-04 a rule with no citation is refused', () async {
      // An opinion presented without an authority is the failure this product
      // exists to avoid. The schema says minItems 1 and so does the type.
      final RulePackResult<RulePack> r =
          await loadWithRules(rule(sourceRefs: '[]'));
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
      expect(r.failureOrNull!.file, 'rules/thresholds.json');
    });

    test('two rules under one identifier are refused', () async {
      final RulePackResult<RulePack> r =
          await loadWithRules('${rule()},${rule()}');
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.duplicateKey);
      expect(r.failureOrNull!.file, 'rules/thresholds.json');
    });

    test('an unknown comparator is refused, never defaulted', () async {
      final RulePackResult<RulePack> r = await loadWithRules(
        rule().replaceAll('"comparator":"GTE"', '"comparator":"ROUGHLY"'),
      );
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
      expect(r.failureOrNull!.detail, contains('ROUGHLY'));
    });
  });

  group('thresholds — MI-05, a rule resolves inside the pack', () {
    test('a rule citing an unknown source is refused', () async {
      // CI-08 makes this a build failure. This is the pack that was edited
      // after CI saw it — the same reason the integrity check exists.
      final RulePackResult<RulePack> r =
          await loadWithRules(rule(sourceRefs: '["src.nowhere"]'));
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.danglingReference);
      expect(r.failureOrNull!.file, 'rules/thresholds.json');
      expect(r.failureOrNull!.pointer, 'rule.sodium.high');
      expect(r.failureOrNull!.detail, contains('src.nowhere'));
    });

    test('a rule naming an unknown message is refused', () async {
      // A finding whose text cannot be resolved would render as its own
      // identifier — a defect visible to a user rather than to CI.
      final RulePackResult<RulePack> r =
          await loadWithRules(rule(messageId: 'msg.nowhere'));
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.danglingReference);
      expect(r.failureOrNull!.file, 'rules/thresholds.json');
      expect(r.failureOrNull!.pointer, 'rule.sodium.high');
      expect(r.failureOrNull!.detail, contains('msg.nowhere'));
    });

    test('the citation is checked before the message', () async {
      // Both dangle; the source is reported. Stable ordering keeps the
      // diagnostic reproducible for whoever is fixing the pack.
      final RulePackResult<RulePack> r = await loadWithRules(
        rule(sourceRefs: '["src.nowhere"]', messageId: 'msg.nowhere'),
      );
      expect(r.failureOrNull!.detail, contains('src.nowhere'));
    });
  });
}
