import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  AdvisoryRule rule({
    String id = 'rule.sodium.high',
    NutrientId nutrient = NutrientId.sodium,
    CategorySelector? selector,
    List<SourceId>? refs,
    num? weight,
  }) =>
      AdvisoryRule(
        ruleId: RuleId(id),
        ruleVersion: Version(1, 0, 0),
        nutrient: nutrient,
        basis: Basis.per100g,
        comparator: ThresholdComparator.gte,
        threshold: const Quantity.exact(6000, Unit.milligram),
        classification: AdvisoryClassification.highIn,
        severityWeight: weight,
        categorySelector: selector,
        sourceRefs: refs ?? <SourceId>[SourceId('src.who.searo')],
        messageId: MessageId('msg.finding.sodium-high'),
      );

  group('CategorySelector — FR-CAT-04, scoping is data', () {
    test('FR-CAT-01 the universal selector admits every category', () {
      final CategorySelector s = CategorySelector.all;
      expect(s.admits(CategoryId('cat.biscuits')), isTrue);
      expect(s.admits(CategoryId('cat.chips')), isTrue);
    });

    test('FR-CAT-05 an unknown category is admitted by a universal rule', () {
      // The requirement that actually proves category-agnosticism: a product
      // with no category must still get a complete result. A selector that
      // silently dropped it would move the branching into a precondition.
      expect(CategorySelector.all.admits(null), isTrue);
    });

    test('an include list excludes an unknown category', () {
      // A rule scoped to named categories cannot fire for a product we cannot
      // place. That is a refusal to guess, not a gap.
      final CategorySelector s = CategorySelector(
        appliesToAll: false,
        includeCategories: <CategoryId>[CategoryId('cat.chips')],
      );
      expect(s.admits(CategoryId('cat.chips')), isTrue);
      expect(s.admits(CategoryId('cat.biscuits')), isFalse);
      expect(s.admits(null), isFalse);
    });

    test('exclusion outranks inclusion', () {
      final CategorySelector s = CategorySelector(
        excludeCategories: <CategoryId>[CategoryId('cat.beverages')],
      );
      expect(s.admits(CategoryId('cat.beverages')), isFalse);
      expect(s.admits(CategoryId('cat.chips')), isTrue);
      expect(s.admits(null), isTrue);
    });

    test('an explicit include list and an exclusion compose', () {
      final CategorySelector s = CategorySelector(
        appliesToAll: false,
        includeCategories: <CategoryId>[
          CategoryId('cat.chips'),
          CategoryId('cat.namkeen'),
        ],
        excludeCategories: <CategoryId>[CategoryId('cat.namkeen')],
      );
      expect(s.admits(CategoryId('cat.chips')), isTrue);
      expect(s.admits(CategoryId('cat.namkeen')), isFalse);
    });

    test('P4 compares by value', () {
      expect(CategorySelector(), CategorySelector());
      expect(CategorySelector().hashCode, CategorySelector().hashCode);
      expect(
        CategorySelector(),
        isNot(CategorySelector(appliesToAll: false)),
      );
      expect(
        CategorySelector(excludeCategories: <CategoryId>[CategoryId('cat.a')]),
        isNot(CategorySelector(
            excludeCategories: <CategoryId>[CategoryId('cat.b')])),
      );
    });

    test('FR-KB-01 both lists are unmodifiable once built', () {
      final CategorySelector s = CategorySelector();
      expect(() => s.includeCategories.add(CategoryId('cat.a')),
          throwsUnsupportedError);
      expect(() => s.excludeCategories.add(CategoryId('cat.a')),
          throwsUnsupportedError);
    });
  });

  group('AdvisoryRule — a record; this milestone evaluates nothing', () {
    test('FR-KB-04 a rule with no citation is refused', () {
      // An opinion presented without an authority is the failure this product
      // exists to avoid, so the type will not hold one.
      expect(() => rule(refs: const <SourceId>[]), throwsArgumentError);
    });

    test('a rule records its own version alongside the pack version', () {
      expect(rule().ruleVersion, Version(1, 0, 0));
    });

    test('ADR-0006 classification has three bands and no score', () {
      // A single composite figure would rank foods against each other on an
      // authority no Indian regulator has established.
      expect(AdvisoryClassification.values, hasLength(3));
      expect(
        AdvisoryClassification.values.map((AdvisoryClassification c) => c.name),
        <String>['low', 'moderate', 'highIn'],
      );
    });

    test('the comparator set matches the schema', () {
      expect(ThresholdComparator.values, hasLength(4));
      expect(
        ThresholdComparator.values.map((ThresholdComparator c) => c.name),
        <String>['gte', 'gt', 'lte', 'lt'],
      );
    });

    test('an omitted selector defaults to universal, never to nothing', () {
      // A rule with no stated scoping applies everywhere. Defaulting to an
      // empty include list would silently disable every unscoped rule.
      expect(rule().categorySelector.admits(CategoryId('cat.chips')), isTrue);
      expect(rule().categorySelector.admits(null), isTrue);
    });

    test('severity weight is optional and unused here', () {
      expect(rule().severityWeight, isNull);
      expect(rule(weight: 2).severityWeight, 2);
    });

    test('MI-11 the threshold is a scaled integer quantity', () {
      expect(rule().threshold, const Quantity.exact(6000, Unit.milligram));
    });

    test('P4 compares by value across every field', () {
      expect(rule(), rule());
      expect(rule().hashCode, rule().hashCode);
      expect(rule(), isNot(rule(id: 'rule.other')));
      expect(rule(), isNot(rule(nutrient: NutrientId.totalFat)));
      expect(rule(), isNot(rule(weight: 3)));
      expect(
        rule(),
        isNot(rule(selector: CategorySelector(appliesToAll: false))),
      );
    });

    test('FR-KB-01 the citation list is unmodifiable once built', () {
      expect(() => rule().sourceRefs.add(SourceId('src.x')),
          throwsUnsupportedError);
    });
  });

  group('AdvisoryRuleTable — ADR-0025, empty in v0.1 by design', () {
    test('an empty table is correct, not a gap', () {
      // Layer 2 is deferred rather than fabricated. Inventing thresholds no
      // Indian model has established would be worse than shipping none.
      final AdvisoryRuleTable t = AdvisoryRuleTable(const <AdvisoryRule>[]);
      expect(t.isEmpty, isTrue);
      expect(t.length, 0);
    });

    test('rules are held in pack order', () {
      final AdvisoryRuleTable t = AdvisoryRuleTable(<AdvisoryRule>[
        rule(id: 'rule.z'),
        rule(id: 'rule.a'),
      ]);
      expect(
        t.rules.map((AdvisoryRule r) => r.ruleId.value),
        <String>['rule.z', 'rule.a'],
      );
    });

    test('a duplicate rule identifier is refused', () {
      expect(
        () => AdvisoryRuleTable(<AdvisoryRule>[rule(), rule()]),
        throwsArgumentError,
      );
    });

    test('FR-KB-01 the list is unmodifiable once built', () {
      final AdvisoryRuleTable t = AdvisoryRuleTable(<AdvisoryRule>[rule()]);
      expect(() => t.rules.add(rule(id: 'rule.b')), throwsUnsupportedError);
    });
  });
}
