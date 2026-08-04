import 'dart:math';

import 'package:lw_domain/lw_domain.dart';

/// Deterministic generators for property-based tests.
///
/// Hand-rolled rather than taken from a package. `TEST_STRATEGY.md` §12 (Q17)
/// leaves the library choice open and states that hand-rolled generators are
/// preferable to a poorly maintained dependency — and every dependency needs a
/// register entry and a licence check (CON-11, NFR-MNT-02) that a test-only
/// convenience does not justify.
///
/// Every generator is **seeded**. A property test that cannot be reproduced
/// from its failure output is not a test, it is a rumour; the seed is reported
/// on
/// failure so any run can be replayed exactly.
class Gen {
  /// Creates a generator with an explicit [seed].
  Gen(this.seed) : _random = Random(seed);

  /// The seed this generator was constructed with. Report it on failure.
  final int seed;

  final Random _random;

  /// An integer in `[min, max]`.
  int intInRange(int min, int max) => min + _random.nextInt(max - min + 1);

  /// A non-negative scaled value within the range real labels produce.
  ///
  /// Bounded well below the 64-bit limit so that base-unit arithmetic in
  /// [Quantity] cannot overflow during a property run — an overflow would be a
  /// generator artefact rather than a defect in the code under test.
  int scaledValue() => intInRange(0, 1000000);

  /// Any unit.
  Unit unit() => Unit.values[_random.nextInt(Unit.values.length)];

  /// A unit measuring [dimension].
  Unit unitOfDimension(Dimension dimension) {
    final List<Unit> candidates =
        Unit.values.where((Unit u) => u.dimension == dimension).toList();
    return candidates[_random.nextInt(candidates.length)];
  }

  /// Any qualifier.
  Qualifier qualifier() =>
      Qualifier.values[_random.nextInt(Qualifier.values.length)];

  /// Any confidence level.
  Confidence confidence() =>
      Confidence.values[_random.nextInt(Confidence.values.length)];

  /// A quantity with an arbitrary unit and qualifier.
  Quantity quantity() => Quantity.qualified(scaledValue(), unit(), qualifier());

  /// A quantity measuring [dimension].
  Quantity quantityOfDimension(Dimension dimension) => Quantity.qualified(
        scaledValue(),
        unitOfDimension(dimension),
        qualifier(),
      );

  /// A quantity that is never approximate, so it can be bounded without a
  /// delta table.
  Quantity boundableQuantity(Dimension dimension) {
    final List<Qualifier> withoutApproximate = Qualifier.values
        .where((Qualifier q) => q != Qualifier.approximately)
        .toList();
    return Quantity.qualified(
      scaledValue(),
      unitOfDimension(dimension),
      withoutApproximate[_random.nextInt(withoutApproximate.length)],
    );
  }

  /// A version with small components, so collisions are frequent enough to
  /// exercise equality as well as ordering.
  Version version() =>
      Version(intInRange(0, 5), intInRange(0, 20), intInRange(0, 20));
}

/// The number of cases each property test runs.
///
/// Large enough to find boundary defects, small enough that the whole suite
/// stays fast — the domain suite must remain seconds, not minutes, or corpus
/// iteration slows down (NFR-TST-02).
const int propertyRuns = 500;

/// Runs [body] over [propertyRuns] seeded cases, reporting the seed on failure.
void forAll(String description, void Function(Gen gen) body,
    {int seed = 20260804}) {
  for (int run = 0; run < propertyRuns; run++) {
    final Gen gen = Gen(seed + run);
    try {
      body(gen);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        StateError(
          'Property "$description" failed on run $run '
          '(seed ${gen.seed}): $error',
        ),
        stack,
      );
    }
  }
}
