/// The pack-relative paths the loader knows, and the integrity scope rule.
///
/// **One place, because §7.2 of `DATA_MODEL.md` is normative and the loader,
/// the CI tool and this file must agree exactly.** The defect this milestone
/// opened with was a hash whose scope was described in one place and computed
/// in another; keeping the rule in a single named constant is the cheapest
/// insurance against a repeat.
final class PackPaths {
  const PackPaths._();

  /// The manifest — read first, excluded from the digest.
  ///
  /// It cannot be hashed: it carries the digest, so including it would require
  /// the file to contain its own checksum.
  static const String manifest = 'manifest.json';

  /// The citation registry.
  static const String sources = 'sources.json';

  /// The nutrient synonym table (S5).
  static const String synonyms = 'nutrients/synonyms.json';

  /// The gazetted daily-value denominators (Layer 1).
  static const String rda = 'nutrients/rda.json';

  /// The Layer 2 advisory thresholds.
  static const String thresholds = 'rules/thresholds.json';

  /// The confidence assignment table, tolerances and approximation deltas.
  static const String confidence = 'rules/confidence.json';

  /// The INS-keyed additive records — the lazily decoded segment.
  static const String additives = 'additives/ins.json';

  /// The category records.
  static const String categories = 'categories/categories.json';

  /// The directory holding one catalogue per locale.
  static const String messagesDirectory = 'messages/';

  /// The catalogue path for [locale].
  static String messagesFor(String locale) => '$messagesDirectory$locale.json';

  /// Directories excluded from the integrity digest.
  ///
  /// `schema/` is validation scaffolding the runtime never reads — CI is the
  /// authority on schema validity (§9.3 of `ARCHITECTURE.md`). Hashing it would
  /// let a schema typo-fix break the shipped pack for no runtime benefit.
  static const List<String> excludedDirectories = <String>['schema/'];

  /// Individual files excluded from the integrity digest.
  ///
  /// `LICENSE` is legal text, not knowledge; the manifest cannot contain its
  /// own digest.
  static const List<String> excludedFiles = <String>[manifest, 'LICENSE'];

  /// Whether [path] contributes to the integrity digest.
  ///
  /// The normative scope rule of §7.2, expressed once.
  static bool isContentFile(String path) {
    if (excludedFiles.contains(path)) {
      return false;
    }
    for (final String dir in excludedDirectories) {
      if (path.startsWith(dir)) {
        return false;
      }
    }
    return true;
  }

  /// [paths] reduced to the digest scope and ordered as §7.2 requires.
  ///
  /// Ascending byte-wise comparison of the UTF-8 relative path. Dart's
  /// `String.compareTo` compares UTF-16 code units, which orders identically to
  /// UTF-8 bytes for the ASCII the pack's paths are restricted to. **Not
  /// locale-aware collation** — that would make the digest depend on the
  /// machine that computed it, which is the one thing a checksum must never do.
  static List<String> contentFilesIn(Iterable<String> paths) {
    final List<String> content = paths.where(isContentFile).toList()
      ..sort((String a, String b) => a.compareTo(b));
    return content;
  }
}
