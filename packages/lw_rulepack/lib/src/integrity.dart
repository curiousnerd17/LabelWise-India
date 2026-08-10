import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lw_rulepack/src/pack_paths.dart';
import 'package:lw_rulepack/src/rule_pack_source.dart';

/// Computes and checks the rule pack integrity digest.
///
/// **The algorithm is normative in §7.2 of `DATA_MODEL.md`, and this is its one
/// implementation in Dart.** `tool/compute_rulepack_hash.py` implements the
/// same recipe independently and CI-17 compares the two against the shipped
/// manifest — which is the arrangement that would have caught the drift this
/// milestone opened by finding.
///
/// > **This is a checksum, not a signature.** It detects corruption and
/// > tampering by anyone who cannot also rewrite the manifest. It proves
/// > nothing about origin, and FR-KB-09's out-of-band replacement would need
/// > signing that the MVP does not have. Saying so here matters more than it
/// > looks: a future reader could easily mistake a verified digest for a
/// > verified publisher.
final class RulePackIntegrity {
  const RulePackIntegrity._();

  /// The prefix every digest carries.
  static const String prefix = 'sha256:';

  /// Computes the digest of the content files supplied by [source].
  ///
  /// Follows §7.2 exactly: content files only, ascending byte-wise path order,
  /// path bytes then file bytes with no separator, lower-case hex behind
  /// [prefix].
  ///
  /// Throws [RulePackSourceException] when a listed file cannot be read. The
  /// loader catches it; nothing propagates to a caller.
  static Future<String> compute(RulePackSource source) async {
    final List<String> files =
        PackPaths.contentFilesIn(await source.listFiles());
    final BytesBuilder buffer = BytesBuilder(copy: false);
    for (final String path in files) {
      // The path is hashed as well as the contents. Without it, two files'
      // bodies could be swapped and the digest would not move.
      buffer
        ..add(utf8.encode(path))
        ..add(await source.read(path));
    }
    return '$prefix${sha256.convert(buffer.takeBytes()).toString()}';
  }

  /// Whether [computed] and [recorded] are the same digest.
  ///
  /// A plain string comparison, deliberately: both sides are already canonical
  /// lower-case hex — `RulePackManifest` refuses to hold anything else — so a
  /// case-insensitive compare here would only mask a manifest that had escaped
  /// that check.
  static bool matches({required String computed, required String recorded}) =>
      computed == recorded;
}
