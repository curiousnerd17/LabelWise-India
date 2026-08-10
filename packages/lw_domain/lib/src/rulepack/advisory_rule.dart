import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/category_id.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';
import 'package:lw_domain/src/rulepack/pack_ids.dart';
import 'package:lw_domain/src/version.dart';

/// How a declared value is compared against a threshold.
enum ThresholdComparator {
  /// At or above.
  gte,

  /// Strictly above.
  gt,

  /// At or below.
  lte,

  /// Strictly below.
  lt,
}

/// What a rule concludes when it fires.
///
/// **Three bands, and deliberately no number.** ADR-0006 rejects a composite
/// health score: a single figure invites ranking foods against each other on an
/// authority no Indian regulator has established.
enum AdvisoryClassification {
  /// Low in this nutrient.
  low,

  /// Neither low nor high.
  moderate,

  /// High in this nutrient.
  highIn,
}

/// Declarative category scoping.
///
/// **The mechanism FR-KB-11 and FR-CAT-04 require**: where a rule applies only
/// to some categories, that scoping is data. Category logic never appears as
/// code branching (FR-CAT-01), and this type is why it does not have to.
final class CategorySelector {
  /// Records a selector.
  CategorySelector({
    this.appliesToAll = true,
    List<CategoryId> includeCategories = const <CategoryId>[],
    List<CategoryId> excludeCategories = const <CategoryId>[],
  })  : includeCategories = List<CategoryId>.unmodifiable(includeCategories),
        excludeCategories = List<CategoryId>.unmodifiable(excludeCategories);

  /// The selector that admits everything, including an unknown category.
  static final CategorySelector all = CategorySelector();

  /// Whether the rule applies by default.
  final bool appliesToAll;

  /// Categories the rule applies to when [appliesToAll] is false.
  final List<CategoryId> includeCategories;

  /// Categories the rule never applies to.
  final List<CategoryId> excludeCategories;

  /// Whether this selector admits [category].
  ///
  /// [category] is null for a product whose category is unknown. **An unknown
  /// category is admitted by a universal selector**, because FR-CAT-05 requires
  /// a complete result without one; only an explicit include list excludes it.
  bool admits(CategoryId? category) {
    if (category != null && excludeCategories.contains(category)) {
      return false;
    }
    if (appliesToAll) {
      return true;
    }
    return category != null && includeCategories.contains(category);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategorySelector &&
          appliesToAll == other.appliesToAll &&
          _same(includeCategories, other.includeCategories) &&
          _same(excludeCategories, other.excludeCategories);

  static bool _same(List<CategoryId> a, List<CategoryId> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        appliesToAll,
        Object.hashAll(includeCategories),
        Object.hashAll(excludeCategories),
      );

  @override
  String toString() => appliesToAll
      ? 'CategorySelector(all, ${excludeCategories.length} excluded)'
      : 'CategorySelector(${includeCategories.length} included)';
}

/// One Layer 2 advisory threshold rule.
///
/// `DATA_MODEL.md` §7.6. **A record only — this milestone evaluates nothing.**
/// Layer 2 is v0.2 scope (ADR-0025) and `rules/thresholds.json` ships empty by
/// design; the type exists because P-PACK's contract names thresholds as a
/// load operation, and a pack file the loader ignored would be a file the
/// integrity hash covers and nothing reads.
final class AdvisoryRule {
  /// Records a rule.
  ///
  /// Throws [ArgumentError] when [sourceRefs] is empty. **A rule without a
  /// citation must fail validation** (FR-KB-04) — an opinion presented without
  /// an authority is the failure this product exists to avoid.
  AdvisoryRule({
    required this.ruleId,
    required this.ruleVersion,
    required this.nutrient,
    required this.basis,
    required this.comparator,
    required this.threshold,
    required this.classification,
    required List<SourceId> sourceRefs,
    required this.messageId,
    CategorySelector? categorySelector,
    this.severityWeight,
  })  : sourceRefs = List<SourceId>.unmodifiable(sourceRefs),
        categorySelector = categorySelector ?? CategorySelector.all {
    if (sourceRefs.isEmpty) {
      throw ArgumentError.value(
        ruleId.value,
        'sourceRefs',
        'An advisory rule with no citation cannot be shown to a user.',
      );
    }
  }

  /// Stable key, cited in every Explanation.
  final RuleId ruleId;

  /// The rule's own version, recorded alongside the pack version.
  final Version ruleVersion;

  /// The nutrient compared.
  final NutrientId nutrient;

  /// The basis the comparison is defined on.
  final Basis basis;

  /// How the declared value is compared.
  final ThresholdComparator comparator;

  /// The value compared against.
  final Quantity threshold;

  /// What the rule concludes when it fires.
  final AdvisoryClassification classification;

  /// Input to severity ranking (FR-L2-08).
  ///
  /// Nullable and unused here. Severity derives from the *recorded margin*, not
  /// from this weight alone — §8.1 makes the margin the evidence.
  final num? severityWeight;

  /// Which categories the rule applies to.
  final CategorySelector categorySelector;

  /// Where the threshold comes from. Never empty.
  final List<SourceId> sourceRefs;

  /// The catalogue key for the finding's text.
  final MessageId messageId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdvisoryRule &&
          ruleId == other.ruleId &&
          ruleVersion == other.ruleVersion &&
          nutrient == other.nutrient &&
          basis == other.basis &&
          comparator == other.comparator &&
          threshold == other.threshold &&
          classification == other.classification &&
          severityWeight == other.severityWeight &&
          categorySelector == other.categorySelector &&
          messageId == other.messageId &&
          _sameRefs(other.sourceRefs);

  bool _sameRefs(List<SourceId> other) {
    if (sourceRefs.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (sourceRefs[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        ruleId,
        ruleVersion,
        nutrient,
        basis,
        comparator,
        threshold,
        classification,
        severityWeight,
        categorySelector,
        messageId,
        Object.hashAll(sourceRefs),
      );

  @override
  String toString() => 'AdvisoryRule($ruleId, ${nutrient.name})';
}

/// Every advisory rule the pack declares.
///
/// Empty in v0.1 and that is correct, not a gap: ADR-0025 defers Layer 2 to
/// v0.2 rather than fabricating thresholds no Indian model has established.
final class AdvisoryRuleTable {
  /// Records the table.
  ///
  /// Throws [ArgumentError] on a duplicate `ruleId`.
  AdvisoryRuleTable(List<AdvisoryRule> rules)
      : rules = List<AdvisoryRule>.unmodifiable(rules) {
    final Set<RuleId> seen = <RuleId>{};
    for (final AdvisoryRule r in rules) {
      if (!seen.add(r.ruleId)) {
        throw ArgumentError.value(
          r.ruleId.value,
          'rules',
          'Duplicate rule identifier.',
        );
      }
    }
  }

  /// Every rule, in pack order.
  ///
  /// Order is preserved and meaningful: it is the order the curator wrote and
  /// the order findings are produced in, which keeps FR-PAR-02 determinism a
  /// property of the data rather than of a sort somebody chose.
  final List<AdvisoryRule> rules;

  /// How many rules the pack declares.
  int get length => rules.length;

  /// Whether the pack declares no advisory rules at all.
  bool get isEmpty => rules.isEmpty;

  @override
  String toString() => 'AdvisoryRuleTable(${rules.length} rules)';
}
