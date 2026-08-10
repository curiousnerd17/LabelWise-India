import 'dart:convert';
import 'dart:typed_data';

import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/src/decode/additives.dart';
import 'package:lw_rulepack/src/decode/confidence.dart';
import 'package:lw_rulepack/src/decode/knowledge.dart';
import 'package:lw_rulepack/src/integrity.dart';
import 'package:lw_rulepack/src/json_view.dart';
import 'package:lw_rulepack/src/pack_paths.dart';
import 'package:lw_rulepack/src/rule_pack_source.dart';

/// Loads, verifies and decodes a rule pack.
///
/// **The only entry point.** Nothing it returns can throw for an expected
/// condition, and nothing it returns is partially built: a pack that fails any
/// check produces a `RulePackRejected` and no `RulePack` at all, because
/// FR-ERR-06 forbids falling back to unvalidated data.
///
/// The order of operations is deliberate and worth stating:
///
/// 1. **Manifest** — read first; nothing else may be trusted before it.
/// 2. **Schema compatibility** — can this build interpret the shape?
/// 3. **Application compatibility** — is this build new enough for the content?
/// 4. **Integrity** — do the bytes match what the manifest claims?
/// 5. **Decode** — only now is any knowledge built.
///
/// Compatibility precedes integrity because a pack we cannot interpret should
/// say so plainly, rather than first reporting a digest mismatch that tells the
/// user nothing useful about a version problem.
final class RulePackLoader {
  /// Creates a loader over [source].
  ///
  /// [implementedSchemaMajor] is the schema major this build understands, and
  /// [applicationVersion] is the running build's version. Both are injected
  /// rather than read from ambient state — a loader that consulted a global
  /// would be untestable at exactly the boundary that most needs testing.
  const RulePackLoader({
    required this.source,
    required this.implementedSchemaMajor,
    required this.applicationVersion,
    this.locale = 'en',
  });

  /// Where pack bytes come from.
  final RulePackSource source;

  /// The rule pack schema major version this build implements.
  final int implementedSchemaMajor;

  /// The running application's version.
  final Version applicationVersion;

  /// Which message catalogue to load eagerly (§9.2).
  final String locale;

  /// Loads the manifest, verifies the pack, and decodes the eager segments.
  ///
  /// The additive table is **not** included; call [loadAdditives] when an
  /// ingredient list first needs it.
  Future<RulePackResult<RulePack>> load() async {
    try {
      final JsonView manifestJson = await _read(PackPaths.manifest);
      final RulePackManifest manifest = KnowledgeDecoder.manifest(manifestJson);

      if (!manifest.supportsSchema(implementedSchemaMajor)) {
        return RulePackRejected<RulePack>(
          RulePackFailure(
            kind: RulePackFailureKind.schemaVersionUnsupported,
            file: PackPaths.manifest,
            pointer: 'schemaVersion',
            detail: 'This build implements schema major '
                '$implementedSchemaMajor; the pack declares '
                '${manifest.schemaVersion}.',
          ),
        );
      }

      if (!manifest.acceptsApplication(applicationVersion)) {
        return RulePackRejected<RulePack>(
          RulePackFailure(
            kind: RulePackFailureKind.appVersionTooOld,
            file: PackPaths.manifest,
            pointer: 'minAppVersion',
            detail: 'The pack requires at least ${manifest.minAppVersion}; '
                'this build is $applicationVersion.',
          ),
        );
      }

      final String computed = await RulePackIntegrity.compute(source);
      if (!RulePackIntegrity.matches(
        computed: computed,
        recorded: manifest.integrityHash,
      )) {
        return RulePackRejected<RulePack>(
          RulePackFailure(
            kind: RulePackFailureKind.integrityMismatch,
            file: PackPaths.manifest,
            pointer: 'integrityHash',
            detail: 'Recorded ${manifest.integrityHash}, computed $computed.',
          ),
        );
      }

      final SourceRegistry sources =
          KnowledgeDecoder.sources(await _read(PackPaths.sources));
      final MessageCatalogue messages = KnowledgeDecoder.messages(
        await _read(PackPaths.messagesFor(locale)),
      );
      final ConfidenceBundle confidence =
          ConfidenceDecoder.decode(await _read(PackPaths.confidence));
      final AdvisoryRuleTable advisoryRules =
          KnowledgeDecoder.thresholds(await _read(PackPaths.thresholds));
      final RdaTable rda = KnowledgeDecoder.rda(await _read(PackPaths.rda));
      final CategoryTable categories =
          KnowledgeDecoder.categories(await _read(PackPaths.categories));

      final RulePack pack = RulePack(
        manifest: manifest,
        sources: sources,
        synonyms: KnowledgeDecoder.synonyms(await _read(PackPaths.synonyms)),
        rda: rda,
        categories: categories,
        advisoryRules: advisoryRules,
        confidencePolicy: confidence.policy,
        tolerances: confidence.tolerances,
        approximationDeltas: confidence.approximationDeltas,
        messages: messages,
      );

      final RulePackFailure? dangling = _checkReferences(
        sources: sources,
        messages: messages,
        rda: rda,
        categories: categories,
        advisoryRules: advisoryRules,
      );
      if (dangling != null) {
        return RulePackRejected<RulePack>(dangling);
      }

      return RulePackLoaded<RulePack>(pack);
    } on RulePackSourceException catch (e) {
      return RulePackRejected<RulePack>(_missing(e));
    } on DecodeException catch (e) {
      return RulePackRejected<RulePack>(_fromDecode(e, _fileOf(e.pointer)));
    }
  }

  /// Decodes the additive table.
  ///
  /// > **§9.2's laziness is about decoding, not about reading.** The bytes of
  /// > `ins.json` are read during [load] because they are inside the integrity
  /// > digest, and a file cannot be verified without being read. What is
  /// > deferred is the expensive half — parsing the JSON and constructing the
  /// > records — which is what the 300 ms eager budget is actually spent on.
  /// > Hashing twenty kilobytes is not.
  ///
  /// Callers should hold the result; this performs no caching of its own,
  /// deliberately, because a cache inside a loader is ambient state and the
  /// domain's determinism guarantees are easier to keep when there is none.
  Future<RulePackResult<AdditiveTable>> loadAdditives() async {
    try {
      return RulePackLoaded<AdditiveTable>(
        AdditiveDecoder.decode(await _read(PackPaths.additives)),
      );
    } on RulePackSourceException catch (e) {
      return RulePackRejected<AdditiveTable>(_missing(e));
    } on DecodeException catch (e) {
      return RulePackRejected<AdditiveTable>(
        _fromDecode(e, PackPaths.additives),
      );
    }
  }

  Future<JsonView> _read(String path) async {
    final Uint8List bytes = await source.read(path);
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw DecodeException(
        RulePackFailureKind.malformedJson,
        path,
        'Not well-formed JSON: ${e.message}',
      );
    }
    return JsonView(decoded, path);
  }

  /// Verifies that every identifier used inside the pack resolves within it.
  ///
  /// CI-08 already makes a dangling reference a build failure (MI-05). This
  /// exists for the pack that was edited after CI saw it — the same reason the
  /// integrity check exists — and it is why a `RulePack` handed to the domain
  /// can be relied on to have no unresolvable citation in it.
  RulePackFailure? _checkReferences({
    required SourceRegistry sources,
    required MessageCatalogue messages,
    required RdaTable rda,
    required CategoryTable categories,
    required AdvisoryRuleTable advisoryRules,
  }) {
    for (final RdaDenominator d in rda.denominators) {
      for (final SourceId ref in d.sourceRefs) {
        if (!sources.contains(ref)) {
          return RulePackFailure(
            kind: RulePackFailureKind.danglingReference,
            file: PackPaths.rda,
            pointer: d.constantId.value,
            detail: 'Unknown source "$ref".',
          );
        }
      }
    }
    for (final Category c in categories.categories) {
      if (!messages.contains(c.nameMessageId)) {
        return RulePackFailure(
          kind: RulePackFailureKind.danglingReference,
          file: PackPaths.categories,
          pointer: c.categoryId.value,
          detail: 'Unknown message "${c.nameMessageId}".',
        );
      }
    }
    for (final AdvisoryRule r in advisoryRules.rules) {
      for (final SourceId ref in r.sourceRefs) {
        if (!sources.contains(ref)) {
          return RulePackFailure(
            kind: RulePackFailureKind.danglingReference,
            file: PackPaths.thresholds,
            pointer: r.ruleId.value,
            detail: 'Unknown source "$ref".',
          );
        }
      }
      if (!messages.contains(r.messageId)) {
        return RulePackFailure(
          kind: RulePackFailureKind.danglingReference,
          file: PackPaths.thresholds,
          pointer: r.ruleId.value,
          detail: 'Unknown message "${r.messageId}".',
        );
      }
    }
    return null;
  }

  static RulePackFailure _missing(RulePackSourceException e) => RulePackFailure(
        kind: RulePackFailureKind.packMissing,
        file: e.path,
        detail: 'The source could not supply this file.',
      );

  static RulePackFailure _fromDecode(DecodeException e, String file) =>
      RulePackFailure(
        kind: e.kind,
        file: file,
        pointer: e.pointer == file ? null : _relative(e.pointer, file),
        detail: e.detail,
      );

  static String _fileOf(String pointer) {
    final int slash = pointer.indexOf('.json');
    return slash < 0 ? pointer : pointer.substring(0, slash + 5);
  }

  static String? _relative(String pointer, String file) {
    if (!pointer.startsWith('$file/')) {
      return pointer;
    }
    return pointer.substring(file.length + 1);
  }
}
