/// Why a rule pack could not be loaded.
///
/// An enum, not a string: the domain holds identity, never display text
/// (M5, FR-LOC-01). Each kind is specific enough that presentation can say
/// something actionable (FR-ERR-01) — "the pack is corrupt" and "this build is
/// too old for the pack" need different words and different remedies.
///
/// **Every one of these is an expected condition, not a defect.** No load path
/// throws for anything in this list (§5 of `ARCHITECTURE.md`, port rule 2).
enum RulePackFailureKind {
  /// A file the pack requires was not present at the supplied source.
  packMissing,

  /// A file was present but is not well-formed JSON.
  ///
  /// Distinct from [schemaViolation]: this is "unreadable", that is "readable
  /// and wrong". Conflating them tells a contributor to look in the wrong
  /// place.
  malformedJson,

  /// The JSON parsed, but a value was the wrong type, missing, or outside its
  /// permitted set.
  ///
  /// CI validates the full schema and is the authority (§9.3 of
  /// `ARCHITECTURE.md`). Reaching this at runtime means the pack was altered
  /// after CI saw it, so it is reported rather than absorbed.
  schemaViolation,

  /// The recomputed integrity digest does not match the manifest.
  ///
  /// Corruption or tampering. **There is no fallback to unvalidated data**
  /// (FR-ERR-06) — a pack that fails this check is not loaded at all.
  integrityMismatch,

  /// The pack's schema major version is not the one this build implements.
  ///
  /// An explicit, reported refusal, never a best-effort load (ADR-0022).
  schemaVersionUnsupported,

  /// The application is older than the pack's `minAppVersion`.
  appVersionTooOld,

  /// A `sourceRef`, `messageId` or `categoryId` names something the pack does
  /// not contain.
  ///
  /// CI-08 makes this a build failure (MI-05). At runtime it means the pack
  /// was edited after validation.
  danglingReference,

  /// Two records claim the same key — two INS numbers, two category ids, two
  /// denominators for one nutrient.
  ///
  /// A duplicate would make every lookup mean "whichever came first", which is
  /// a silent choice no consumer could see or question.
  duplicateKey,

  /// A value is well-typed and in range but cannot be represented exactly in
  /// the domain.
  ///
  /// The motivating case is a relative tolerance fraction that does not convert
  /// exactly to tenths of a percent. **Rounding a calibration constant is
  /// forbidden** — a band silently widened by rounding accepts the error it
  /// exists to catch.
  unrepresentableValue,
}

/// A structured account of why a rule pack could not be loaded.
///
/// Names the kind, the file, and — where the failure is local to one record —
/// a pointer to it. A contributor who broke the pack should be able to find
/// what they broke without reading the loader.
final class RulePackFailure {
  /// Records a load failure.
  const RulePackFailure({
    required this.kind,
    required this.file,
    this.pointer,
    this.detail,
  });

  /// What went wrong.
  final RulePackFailureKind kind;

  /// The pack-relative path of the file concerned, such as
  /// `additives/ins.json`.
  final String file;

  /// Where inside the file, when the failure is local to one record.
  ///
  /// A JSON-pointer-like path such as `additives/3/insNumber`. Null when the
  /// failure concerns the file or the pack as a whole.
  final String? pointer;

  /// A short diagnostic for developers and contributors.
  ///
  /// **Not display text and never shown to a user** (M5, FR-LOC-01). It names
  /// what was expected and what was found, in the vocabulary of the schema —
  /// which is the vocabulary of whoever must fix the pack.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulePackFailure &&
          kind == other.kind &&
          file == other.file &&
          pointer == other.pointer &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(kind, file, pointer, detail);

  @override
  String toString() => pointer == null
      ? 'RulePackFailure(${kind.name} in $file)'
      : 'RulePackFailure(${kind.name} in $file at $pointer)';
}
