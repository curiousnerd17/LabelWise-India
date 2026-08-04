/// A semantic version, as a value object rather than an opaque string
/// (ADR-0022).
///
/// Recorded on every finding and every stored scan, and compared in two places
/// that matter: rule pack compatibility at load time, and viewing a stored scan
/// under a newer pack (FR-KB-02, FR-HIS-04, FR-HIS-05).
///
/// String comparison gets this wrong — lexicographically `"1.10.0" < "1.9.0"` —
/// and its failure mode is a rule pack silently refusing to load, or silently
/// loading when it should not.
final class Version implements Comparable<Version> {
  /// Creates a version from its three components.
  ///
  /// Throws [ArgumentError] on a negative component.
  Version(this.major, this.minor, this.patch) {
    if (major < 0 || minor < 0 || patch < 0) {
      throw ArgumentError(
        'Version components must be non-negative; got $major.$minor.$patch',
      );
    }
  }

  /// Parses `major.minor.patch`.
  ///
  /// Throws [FormatException] on anything else. Malformed versions fail here,
  /// in CI, rather than at load time on a user's device.
  factory Version.parse(String source) {
    final List<String> parts = source.split('.');
    if (parts.length != 3) {
      // FormatException is Dart's idiomatic parse failure. It implements
      // Exception, so only_throw_errors permits it — no suppression needed.
      throw FormatException(
        'Expected major.minor.patch, got "$source"',
        source,
      );
    }
    final List<int> components = <int>[];
    for (final String part in parts) {
      final int? value = int.tryParse(part);
      if (value == null) {
        throw FormatException(
          'Version component "$part" is not an integer',
          source,
        );
      }
      components.add(value);
    }
    return Version(components[0], components[1], components[2]);
  }

  /// Incompatible changes.
  final int major;

  /// Backwards-compatible additions.
  final int minor;

  /// Backwards-compatible fixes.
  final int patch;

  /// Whether a rule pack at this version may be loaded by an application
  /// supporting [supportedMajor] and requiring at least [minimum].
  ///
  /// A major mismatch is an explicit, reported refusal (FR-ERR-06), never a
  /// best-effort load.
  bool isCompatibleWith({
    required int supportedMajor,
    required Version minimum,
  }) =>
      major == supportedMajor && compareTo(minimum) >= 0;

  @override
  int compareTo(Version other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }

  /// Whether this version precedes [other].
  bool operator <(Version other) => compareTo(other) < 0;

  /// Whether this version precedes or equals [other].
  bool operator <=(Version other) => compareTo(other) <= 0;

  /// Whether this version follows [other].
  bool operator >(Version other) => compareTo(other) > 0;

  /// Whether this version follows or equals [other].
  bool operator >=(Version other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Version &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
