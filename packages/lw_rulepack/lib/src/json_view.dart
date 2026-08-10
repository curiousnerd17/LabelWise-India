import 'package:lw_domain/lw_domain.dart';

/// Thrown inside the decoders when a value is missing or the wrong shape.
///
/// **Private to this package by convention and never escapes it.** Every
/// decoder entry point catches it and returns a `RulePackRejected`, so the
/// public API stays total: no throw signals an expected condition (§5 of
/// `ARCHITECTURE.md`, port rule 2).
///
/// A `Result` threaded through every field read would be more honest in the
/// small and unreadable in the large — roughly forty binds to decode one
/// additive record. The exception is confined, the boundary is total, and the
/// confinement is verified by test.
final class DecodeException implements Exception {
  /// Records a decoding problem.
  const DecodeException(this.kind, this.pointer, this.detail);

  /// Which failure this becomes at the boundary.
  final RulePackFailureKind kind;

  /// Where in the file, as a slash-separated path.
  final String pointer;

  /// What was expected and what was found.
  final String detail;

  @override
  String toString() => 'DecodeException($pointer: $detail)';
}

/// A typed, position-tracking reader over decoded JSON.
///
/// **This is the decoding boundary.** `Object?` and `Map<String, dynamic>` stop
/// here; everything downstream is a domain type. The type system does not
/// enforce that, so the rule is worth stating plainly: *no method on this class
/// returns dynamic, and nothing outside this file destructures raw JSON.*
///
/// Every accessor names its position, so a malformed pack produces
/// `additives/3/insNumber` rather than "expected an integer" — the difference
/// between a contributor finding their typo and hunting for it.
final class JsonView {
  /// Wraps [value] at [pointer].
  const JsonView(this.value, this.pointer);

  /// The raw decoded value at this position.
  final Object? value;

  /// This position's slash-separated path within the file.
  final String pointer;

  Never _fail(String detail) => throw DecodeException(
      RulePackFailureKind.schemaViolation, pointer, detail);

  /// This value as an object, or a failure.
  Map<String, Object?> get asObject {
    final Object? v = value;
    if (v is! Map<String, Object?>) {
      _fail('Expected an object, found ${_describe(v)}.');
    }
    return v;
  }

  /// This value as an array, or a failure.
  List<Object?> get asArray {
    final Object? v = value;
    if (v is! List<Object?>) {
      _fail('Expected an array, found ${_describe(v)}.');
    }
    return v;
  }

  /// The child at [key], present or not.
  JsonView child(String key) =>
      JsonView(asObject[key], pointer.isEmpty ? key : '$pointer/$key');

  /// The child at [key], which must be present.
  JsonView required(String key) {
    final Map<String, Object?> object = asObject;
    if (!object.containsKey(key)) {
      _fail('Missing required property "$key".');
    }
    return child(key);
  }

  /// Whether [key] is present and not null.
  bool has(String key) => asObject[key] != null;

  /// The elements of this array, each positioned by index.
  Iterable<JsonView> get elements sync* {
    final List<Object?> items = asArray;
    for (int i = 0; i < items.length; i++) {
      yield JsonView(items[i], '$pointer/$i');
    }
  }

  /// This value as a non-empty string.
  String get asString {
    final Object? v = value;
    if (v is! String) {
      _fail('Expected a string, found ${_describe(v)}.');
    }
    return v;
  }

  /// This value as an integer.
  ///
  /// A JSON number that carries a fraction is refused rather than truncated.
  /// Truncation here would silently change a scaled quantity by up to a whole
  /// increment, which is precisely the class of error MI-11 exists to exclude.
  int get asInt {
    final Object? v = value;
    if (v is int) {
      return v;
    }
    if (v is double && v == v.roundToDouble() && v.isFinite) {
      return v.toInt();
    }
    _fail('Expected an integer, found ${_describe(v)}.');
  }

  /// This value as a boolean.
  bool get asBool {
    final Object? v = value;
    if (v is! bool) {
      _fail('Expected a boolean, found ${_describe(v)}.');
    }
    return v;
  }

  /// This value as a number, integral or fractional.
  ///
  /// The only accessor that admits a fraction, and it exists for exactly two
  /// fields: `relativeFraction` and `severityWeight`. Both are converted or
  /// rejected by their decoders — nothing keeps a `double`.
  num get asNum {
    final Object? v = value;
    if (v is! num) {
      _fail('Expected a number, found ${_describe(v)}.');
    }
    return v;
  }

  /// This value as one of [permitted], mapped to `T`.
  ///
  /// The closed sets in the schema become closed sets in the domain here. An
  /// unrecognised member is refused, never mapped to a default: a silent
  /// default would turn a new pack value into an old behaviour, which is the
  /// hardest kind of version skew to notice.
  T asEnum<T>(Map<String, T> permitted) {
    final String raw = asString;
    final T? mapped = permitted[raw];
    if (mapped == null) {
      final List<String> names = permitted.keys.toList()..sort();
      _fail('Expected one of ${names.join(', ')}, found "$raw".');
    }
    return mapped;
  }

  /// Builds a validated identifier, converting a [FormatException] to a
  /// positioned failure.
  ///
  /// The value objects throw on a malformed identifier, which is right for a
  /// programming error and wrong for a malformed pack. This is where the one
  /// becomes the other.
  T asId<T>(T Function(String) build) {
    final String raw = asString;
    try {
      return build(raw);
    } on FormatException {
      _fail('Not a well-formed identifier: "$raw".');
    }
  }

  /// Raises a positioned failure of [kind] with [detail].
  ///
  /// For a decoder that has read a value successfully and rejected it on a rule
  /// the schema cannot express — an inexact tolerance fraction, a duplicate
  /// key.
  Never reject(RulePackFailureKind kind, String detail) =>
      throw DecodeException(kind, pointer, detail);

  static String _describe(Object? v) => switch (v) {
        null => 'null',
        final String _ => 'a string',
        final int _ => 'an integer',
        final double _ => 'a fractional number',
        final bool _ => 'a boolean',
        final List<Object?> _ => 'an array',
        final Map<Object?, Object?> _ => 'an object',
        _ => 'an unexpected value',
      };

  @override
  String toString() => 'JsonView($pointer)';
}
