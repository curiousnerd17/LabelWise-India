/// The project's single rounding policy.
///
/// **Half away from zero**, applied at exactly one place per operation and
/// nowhere in intermediate arithmetic (`DATA_MODEL.md` §2.4).
///
/// Banker's rounding is deliberately rejected: it is less surprising to
/// statisticians and more surprising to everyone else, and this product's
/// audience reads a number off a screen and compares it to a packet.
library;

/// Divides [numerator] by [denominator], rounding half away from zero.
///
/// Throws [ArgumentError] when [denominator] is zero, which is a programming
/// error rather than an expected condition.
int divideRounded(int numerator, int denominator) {
  if (denominator == 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must not be zero');
  }
  final int sign = (numerator < 0) == (denominator < 0) ? 1 : -1;
  final int absNumerator = numerator.abs();
  final int absDenominator = denominator.abs();
  final int quotient =
      (2 * absNumerator + absDenominator) ~/ (2 * absDenominator);
  return sign * quotient;
}
