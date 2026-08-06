import 'package:lw_domain/src/confidence/confidence.dart';
import 'package:lw_domain/src/confidence/confidence_signals.dart';
import 'package:lw_domain/src/provenance/parse_strength.dart';

/// One row of the assignment table.
///
/// Mirrors an entry of `rulepack/rules/confidence.json`'s `assignment` array:
/// a set of conditions and the level to assign when they all hold. Every
/// condition is optional; an absent condition is simply not tested.
final class ConfidenceRule {
  /// Records a rule.
  ///
  /// Throws [ArgumentError] when no condition is given. A rule that matched
  /// everything would silently shadow every rule after it, which is the
  /// failure an ordered first-match table is most prone to and the hardest to
  /// notice once the pack grows.
  ConfidenceRule({
    required this.result,
    this.anyInvariantFailed,
    this.parseStrength,
  }) {
    if (anyInvariantFailed == null && parseStrength == null) {
      throw ArgumentError.value(
        result,
        'result',
        'A rule with no condition matches everything and would shadow every '
            'rule after it.',
      );
    }
  }

  /// Required value of `ConfidenceSignals.anyInvariantFailed`, or null to
  /// leave it untested.
  final bool? anyInvariantFailed;

  /// Required parse strength — signal S2 — or null to leave it untested.
  final ParseStrength? parseStrength;

  /// The level assigned when every stated condition holds.
  final Confidence result;

  /// Whether every stated condition holds for [signals].
  bool matches(ConfidenceSignals signals) {
    if (anyInvariantFailed != null &&
        signals.anyInvariantFailed != anyInvariantFailed) {
      return false;
    }
    if (parseStrength != null && signals.s2ParseStrength != parseStrength) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfidenceRule &&
          anyInvariantFailed == other.anyInvariantFailed &&
          parseStrength == other.parseStrength &&
          result == other.result;

  @override
  int get hashCode => Object.hash(anyInvariantFailed, parseStrength, result);

  @override
  String toString() => 'ConfidenceRule(-> ${result.name})';
}

/// The function that turns signals into a confidence level.
///
/// **Held as data, not as code** (ADR-0010, ADR-0012). `ARCHITECTURE.md` §7.2:
/// *"Assignment is a deterministic function of the three, defined as data in
/// the rule pack so it is tunable without a code change."* The defaults below
/// mirror `rulepack/rules/confidence.json`; `lw_rulepack` will build this from
/// the pack, and the domain never sees JSON (`ARCHITECTURE.md` §2.2).
///
/// **First match wins**, so order is the whole semantics. The pack states the
/// failed-invariant rule first, which is how FR-CNF-05 becomes absolute: an
/// `EXACT` parse cannot outvote arithmetic that does not reconcile.
final class ConfidencePolicy {
  /// Creates a policy from an ordered rule list.
  ConfidencePolicy(List<ConfidenceRule> rules)
      : rules = List<ConfidenceRule>.unmodifiable(rules);

  /// The four rules of `rulepack/rules/confidence.json`, in pack order.
  static final ConfidencePolicy defaults = ConfidencePolicy(<ConfidenceRule>[
    // FR-CNF-05, absolute and therefore first.
    ConfidenceRule(anyInvariantFailed: true, result: Confidence.low),
    ConfidenceRule(parseStrength: ParseStrength.exact, result: Confidence.high),
    ConfidenceRule(
        parseStrength: ParseStrength.normalised, result: Confidence.medium),
    ConfidenceRule(
        parseStrength: ParseStrength.heuristic, result: Confidence.low),
  ]);

  /// The rules, in evaluation order.
  final List<ConfidenceRule> rules;

  /// The level [signals] earn under this policy.
  ///
  /// Returns [Confidence.low] when no rule matches. That is a **fail-safe, not
  /// a default**: a value the policy cannot speak to is a value the user should
  /// check by hand, and quietly trusting it would be exactly the confidently
  /// wrong output this product exists to prevent (P1). [Confidence.absent]
  /// would be worse still — it means "nothing was declared", and something was.
  Confidence classify(ConfidenceSignals signals) {
    for (final ConfidenceRule rule in rules) {
      if (rule.matches(signals)) {
        return rule.result;
      }
    }
    return Confidence.low;
  }

  @override
  String toString() => 'ConfidencePolicy(${rules.length} rules)';
}
