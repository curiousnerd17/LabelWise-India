/// A citation registry key — `src.fssai.labelling.2020`.
///
/// Built like `RuleId` and `CategoryId`: an immutable, validated value object.
/// The type is the point. Every advisory claim terminates in the registry
/// (FR-KB-04), and a bare `String` makes a typo a runtime dangling reference
/// instead of a construction-time refusal.
final class SourceId {
  /// Creates a source identifier, validating it against the pack pattern.
  ///
  /// Throws [FormatException] when [value] does not match [pattern]. Rejecting
  /// at construction is what makes MI-05 checkable at all — an identifier that
  /// cannot exist cannot dangle.
  SourceId(this.value) {
    if (!pattern.hasMatch(value)) {
      throw FormatException('Not a source identifier: "$value".', value);
    }
  }

  /// The pattern every source identifier must match.
  static final RegExp pattern = RegExp(r'^src\.[a-z0-9_.-]+$');

  /// Whether [candidate] would be accepted.
  static bool isValid(String candidate) => pattern.hasMatch(candidate);

  /// The identifier text.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SourceId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A message catalogue key — `msg.additive.ins-322`.
///
/// **This is the whole of B8.** The domain holds message identity; only
/// presentation resolves it to text. A typed key rather than a `String` is what
/// stops a display literal drifting into a domain type by accident, because the
/// type cannot hold one.
final class MessageId {
  /// Creates a message identifier, validating it against the pack pattern.
  ///
  /// Throws [FormatException] when [value] does not match [pattern].
  MessageId(this.value) {
    if (!pattern.hasMatch(value)) {
      throw FormatException('Not a message identifier: "$value".', value);
    }
  }

  /// The pattern every message identifier must match.
  static final RegExp pattern = RegExp(r'^msg\.[a-z0-9_.-]+$');

  /// Whether [candidate] would be accepted.
  static bool isValid(String candidate) => pattern.hasMatch(candidate);

  /// The identifier text.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MessageId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A gazetted constant's key — `const.rda.sodium`.
///
/// Distinct from [SourceId] and `RuleId` so that the three cannot be
/// interchanged. They name different kinds of thing, and a function taking all
/// three as `String` accepts them in any order.
final class ConstantId {
  /// Creates a constant identifier, validating it against the pack pattern.
  ///
  /// Throws [FormatException] when [value] does not match [pattern].
  ConstantId(this.value) {
    if (!pattern.hasMatch(value)) {
      throw FormatException('Not a constant identifier: "$value".', value);
    }
  }

  /// The pattern every constant identifier must match.
  static final RegExp pattern = RegExp(r'^const\.[a-z0-9_.-]+$');

  /// Whether [candidate] would be accepted.
  static bool isValid(String candidate) => pattern.hasMatch(candidate);

  /// The identifier text.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ConstantId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
