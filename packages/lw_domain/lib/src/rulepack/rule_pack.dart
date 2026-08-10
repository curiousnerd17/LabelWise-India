import 'package:lw_domain/src/confidence/confidence_policy.dart';
import 'package:lw_domain/src/invariants/tolerance.dart';
import 'package:lw_domain/src/label/approximation_deltas.dart';
import 'package:lw_domain/src/rules/synonym_table.dart';
import 'package:lw_domain/src/rulepack/advisory_rule.dart';
import 'package:lw_domain/src/rulepack/category.dart';
import 'package:lw_domain/src/rulepack/message_catalogue.dart';
import 'package:lw_domain/src/rulepack/rda_table.dart';
import 'package:lw_domain/src/rulepack/rule_pack_manifest.dart';
import 'package:lw_domain/src/rulepack/source.dart';
import 'package:lw_domain/src/version.dart';

/// **The knowledge base, as the domain sees it.**
///
/// Everything the parser and the analysis layers evaluate against, assembled
/// once and immutable thereafter (§9.4 of `ARCHITECTURE.md`). There is no
/// mutation path: the fields are final, every collection inside is
/// unmodifiable, and nothing here holds a reference to its source.
///
/// **This is the eager segment only.** The additive table is loaded on first
/// ingredient parse (§9.2) — it is the largest part of the pack and a
/// nutrition-only scan never needs it, so eager loading would spend the 300 ms
/// rule pack budget on data most scans discard.
///
/// > **The domain never learns what JSON is.** This type is built by
/// > `lw_rulepack` from already-decoded values (ADR-0007, ADR-0012). Nothing
/// > here knows a file format, and adding a `fromJson` would end that.
final class RulePack {
  /// Assembles a rule pack.
  const RulePack({
    required this.manifest,
    required this.sources,
    required this.synonyms,
    required this.rda,
    required this.categories,
    required this.advisoryRules,
    required this.confidencePolicy,
    required this.tolerances,
    required this.approximationDeltas,
    required this.messages,
  });

  /// Identity, version and integrity.
  final RulePackManifest manifest;

  /// The citation registry — where every claim terminates.
  final SourceRegistry sources;

  /// Label text to canonical nutrient, for S5.
  ///
  /// The project's highest-frequency contribution path (§6.3 of
  /// `ARCHITECTURE.md`): a contributor adds a variant without touching Dart.
  final SynonymTable synonyms;

  /// The gazetted daily-value denominators, for Layer 1.
  final RdaTable rda;

  /// Every category the pack declares.
  final CategoryTable categories;

  /// Layer 2 thresholds. Empty in v0.1 by design (ADR-0025).
  final AdvisoryRuleTable advisoryRules;

  /// The S1/S2/S3 assignment table, for S8.
  final ConfidencePolicy confidencePolicy;

  /// The invariant tolerance bands, for S7.
  final ToleranceTable tolerances;

  /// The `APPROXIMATELY` widths, for S7 (ADR-0027).
  final ApproximationDeltas approximationDeltas;

  /// The active locale's message catalogue.
  final MessageCatalogue messages;

  /// The content version, recorded on every finding and stored scan.
  ///
  /// FR-KB-02 and FR-HIS-04. Exposed here so a caller recording provenance
  /// need not reach through the manifest for the one field it always wants.
  Version get version => manifest.packVersion;

  @override
  String toString() => 'RulePack(${manifest.packVersion}, '
      '${sources.length} sources, ${categories.length} categories, '
      '${advisoryRules.length} rules)';
}
