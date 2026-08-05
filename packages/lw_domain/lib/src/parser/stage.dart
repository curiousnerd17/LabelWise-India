import 'package:lw_domain/src/parser/parse_failure.dart';

/// What a pipeline stage returns.
///
/// **Every stage is total** (`ARCHITECTURE.md` §6.2): every input produces an
/// output, including a failure output. Nothing throws for an expected
/// condition, and there is no "empty success" that a caller might mistake for
/// a result (FR-PAR-17).
///
/// `sealed`, so a switch that omits a variant does not compile. Handling both
/// outcomes is a language guarantee rather than a convention.
///
/// Stages are free functions returning this type rather than a chained
/// builder, which is what makes §6.4's re-entry possible: any stage can be
/// called with a hand-assembled input, including one mixing extracted and
/// user-supplied fields.
sealed class StageResult<T> {
  /// Base constructor for the two outcomes.
  const StageResult();

  /// The produced value, or null when the stage failed.
  T? get valueOrNull;

  /// The failure, or null when the stage succeeded.
  ParseFailure? get failureOrNull;

  /// Whether the stage produced a value.
  bool get isSuccess;
}

/// A stage that produced its output.
final class StageSuccess<T> extends StageResult<T> {
  /// Records a successful stage.
  const StageSuccess(this.value);

  /// The produced value.
  final T value;

  @override
  T? get valueOrNull => value;

  @override
  ParseFailure? get failureOrNull => null;

  @override
  bool get isSuccess => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageSuccess<T> && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'StageSuccess($value)';
}

/// A stage that could not produce its output, and why.
final class StageFailure<T> extends StageResult<T> {
  /// Records a failed stage.
  const StageFailure(this.failure);

  /// Why the stage could not proceed.
  final ParseFailure failure;

  @override
  T? get valueOrNull => null;

  @override
  ParseFailure? get failureOrNull => failure;

  @override
  bool get isSuccess => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageFailure<T> && failure == other.failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'StageFailure($failure)';
}
