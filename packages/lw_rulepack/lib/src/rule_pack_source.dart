import 'dart:convert';
import 'dart:typed_data';

/// Where the loader gets pack bytes from.
///
/// **The I/O seam, and the reason this package performs none.** `lw_rulepack`
/// decodes and verifies; `lw_infrastructure` reads assets, files or anything
/// else. FR-KB-09 asks for out-of-band replacement without an application
/// update, and this is what makes that a new implementation of one interface
/// rather than a new architecture.
///
/// Asynchronous because real asset access is. The in-memory implementation
/// below satisfies it synchronously, which is what lets the whole loader be
/// tested without a device or a file system.
abstract interface class RulePackSource {
  /// Every pack-relative path this source can supply.
  ///
  /// Needed for integrity: the digest covers every content file, and only the
  /// source knows how many locale catalogues shipped. A loader that assumed the
  /// file list would silently stop hashing a catalogue somebody added.
  ///
  /// Paths are slash-separated and relative to the pack root — `sources.json`,
  /// `nutrients/rda.json`.
  Future<List<String>> listFiles();

  /// The bytes of [path].
  ///
  /// **Bytes, not a string.** The digest is over the file exactly as it ships;
  /// decoding to text first and re-encoding would let an encoding difference
  /// change the hash of a file nobody edited.
  ///
  /// Throws [RulePackSourceException] when [path] is not available. This is the
  /// one boundary where a throw is right: the loader catches it and converts it
  /// to a `packMissing` failure, so nothing propagates past the public API.
  Future<Uint8List> read(String path);
}

/// Thrown by a [RulePackSource] when a path cannot be supplied.
///
/// Confined to the source boundary. The loader catches it and returns a
/// `RulePackFailure`; it never reaches a caller.
final class RulePackSourceException implements Exception {
  /// Records an unavailable path.
  const RulePackSourceException(this.path, [this.cause]);

  /// The path that could not be read.
  final String path;

  /// The underlying reason, when the implementation has one.
  final Object? cause;

  @override
  String toString() => 'RulePackSourceException($path)';
}

/// A pack held entirely in memory.
///
/// The test double, and the reason the loader needs no device: a corpus of
/// deliberately malformed packs is a `Map` literal rather than a directory
/// tree, so every failure path in the loader is reachable from a unit test.
final class InMemoryRulePackSource implements RulePackSource {
  /// Records a pack from path to bytes.
  InMemoryRulePackSource(Map<String, Uint8List> files)
      : _files = Map<String, Uint8List>.unmodifiable(files);

  /// Records a pack from path to UTF-8 text.
  ///
  /// A convenience for tests, which write JSON rather than bytes.
  factory InMemoryRulePackSource.fromText(Map<String, String> files) {
    final Map<String, Uint8List> encoded = <String, Uint8List>{};
    files.forEach((String path, String text) {
      encoded[path] = Uint8List.fromList(utf8.encode(text));
    });
    return InMemoryRulePackSource(encoded);
  }

  final Map<String, Uint8List> _files;

  @override
  Future<List<String>> listFiles() async => _files.keys.toList();

  @override
  Future<Uint8List> read(String path) async {
    final Uint8List? bytes = _files[path];
    if (bytes == null) {
      throw RulePackSourceException(path);
    }
    return bytes;
  }
}
