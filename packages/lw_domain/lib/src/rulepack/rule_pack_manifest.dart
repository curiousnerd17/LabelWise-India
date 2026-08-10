import 'package:lw_domain/src/version.dart';

/// A rule pack's identity, version and integrity.
///
/// `DATA_MODEL.md` §7.2. Tiny, and loaded first: nothing else in the pack may
/// be trusted until this has been read and both compatibility checks have
/// passed.
final class RulePackManifest {
  /// Records a manifest.
  ///
  /// Throws [ArgumentError] when [integrityHash] is not a lower-case
  /// `sha256:` digest. The shape is checked here so that a malformed digest is
  /// a refusal at construction rather than a comparison that quietly never
  /// matches.
  RulePackManifest({
    required this.schemaVersion,
    required this.packVersion,
    required this.minAppVersion,
    required this.integrityHash,
    required this.contentLicence,
    required this.generatedAt,
    this.notes,
  }) {
    if (!_digest.hasMatch(integrityHash)) {
      throw ArgumentError.value(
        integrityHash,
        'integrityHash',
        'Expected sha256: followed by 64 lower-case hex digits.',
      );
    }
  }

  static final RegExp _digest = RegExp(r'^sha256:[0-9a-f]{64}$');

  /// Which schema shape the pack conforms to.
  final Version schemaVersion;

  /// The content's semantic version, recorded on every finding (FR-KB-02).
  final Version packVersion;

  /// The oldest application version permitted to load this pack.
  final Version minAppVersion;

  /// The integrity digest, `sha256:` followed by 64 lower-case hex digits.
  ///
  /// Computed by the normative algorithm in §7.2 of `DATA_MODEL.md` over the
  /// pack's **content files only**. It detects corruption and tampering; it is
  /// **not a signature** and proves nothing about origin.
  final String integrityHash;

  /// The content licence — `CC-BY-4.0`, separate from the code's (ADR-0017).
  final String contentLicence;

  /// The ISO date the pack was generated, as recorded.
  ///
  /// A `String`, not a `DateTime`: MI-07 forbids a wall-clock value in a domain
  /// type, and this is a recorded fact about the pack rather than a time the
  /// application needs to reason with.
  final String generatedAt;

  /// Curator's notes. Descriptive only — §7.2 is normative.
  final String? notes;

  /// Whether this build can **interpret** the pack's shape.
  ///
  /// Major only. Within a major version, added fields are optional by
  /// construction, so a newer minor is readable by an older reader; across a
  /// major, it is not. A mismatch is an explicit reported refusal, never a
  /// best-effort load (ADR-0022, FR-ERR-06).
  bool supportsSchema(int implementedSchemaMajor) =>
      schemaVersion.major == implementedSchemaMajor;

  /// Whether [applicationVersion] is new enough to be trusted with this pack.
  ///
  /// A **separate question** from [supportsSchema], deliberately checked apart
  /// from it: one asks whether we can read the pack, the other whether we
  /// should. Collapsing them is how a pack silently loads that should not.
  ///
  /// Compared as a [Version], never lexicographically — `1.10.0` precedes
  /// `1.9.0` as a string, and that failure mode is a pack refusing to load for
  /// no visible reason.
  bool acceptsApplication(Version applicationVersion) =>
      applicationVersion >= minAppVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulePackManifest &&
          schemaVersion == other.schemaVersion &&
          packVersion == other.packVersion &&
          minAppVersion == other.minAppVersion &&
          integrityHash == other.integrityHash &&
          contentLicence == other.contentLicence &&
          generatedAt == other.generatedAt &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        packVersion,
        minAppVersion,
        integrityHash,
        contentLicence,
        generatedAt,
        notes,
      );

  @override
  String toString() =>
      'RulePackManifest(pack $packVersion, schema $schemaVersion)';
}
