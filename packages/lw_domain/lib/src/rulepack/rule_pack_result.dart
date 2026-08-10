import 'package:lw_domain/src/rulepack/rule_pack_failure.dart';

/// What a rule pack load operation returns.
///
/// Deliberately the same shape as the parser's `StageResult`: **no null and no
/// throw signals an expected failure** (§5 of `ARCHITECTURE.md`, port rules 1
/// and 2). Two result types rather than one shared generic because their
/// failure payloads are unrelated — a `ParseFailure` names a pipeline stage and
/// a region, neither of which means anything to a loader.
///
/// `sealed`, so a switch that omits an outcome does not compile. Handling both
/// is a language guarantee rather than a convention.
sealed class RulePackResult<T> {
  /// Base constructor for the two outcomes.
  const RulePackResult();

  /// The loaded value, or null when loading failed.
  T? get valueOrNull;

  /// The failure, or null when loading succeeded.
  RulePackFailure? get failureOrNull;

  /// Whether a value was produced.
  bool get isSuccess;
}

/// A load that produced its value.
final class RulePackLoaded<T> extends RulePackResult<T> {
  /// Records a successful load.
  const RulePackLoaded(this.value);

  /// The loaded value.
  final T value;

  @override
  T? get valueOrNull => value;

  @override
  RulePackFailure? get failureOrNull => null;

  @override
  bool get isSuccess => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulePackLoaded<T> && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RulePackLoaded($value)';
}

/// A load that could not proceed, and why.
///
/// **There is no partial load.** A pack that fails any check is not used at
/// all: FR-ERR-06 forbids falling back to unvalidated data, and a half-loaded
/// pack is exactly that.
final class RulePackRejected<T> extends RulePackResult<T> {
  /// Records a rejected load.
  const RulePackRejected(this.failure);

  /// Why the pack was rejected.
  final RulePackFailure failure;

  @override
  T? get valueOrNull => null;

  @override
  RulePackFailure? get failureOrNull => failure;

  @override
  bool get isSuccess => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulePackRejected<T> && failure == other.failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'RulePackRejected($failure)';
}
