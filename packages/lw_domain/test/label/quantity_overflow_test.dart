import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// M11b — the arithmetic sinks upstream of every invariant.
///
/// `boundsIn` is the **live** path: S7 converts every declared quantity to an
/// interval through it before any comparison happens. A wrap here would reach
/// the invariants as a plausible-looking number, so it is guarded at source.
///
/// `baseUnits` had zero callers when M11b began; `baseUnitsOrNull` exists so a
/// future caller has a safe option without the unguarded one changing meaning.
void main() {
  group('Quantity.baseUnitsOrNull — additive, guarded (S3)', () {
    test('an ordinary quantity converts to base units', () {
      // 30.00 g in micrograms.
      expect(const Quantity.exact(3000, Unit.gram).baseUnitsOrNull, 30000000);
      // 450.0 kcal in millijoules.
      expect(const Quantity.exact(4500, Unit.kilocalorie).baseUnitsOrNull,
          4500 * 418400);
    });

    test('zero converts to zero, not to null', () {
      expect(const Quantity.exact(0, Unit.gram).baseUnitsOrNull, 0);
    });

    test('exactly the safe boundary converts', () {
      // microgram has one base unit per increment, so the scaled value is the
      // base-unit value and the storage bound applies directly.
      expect(
        const Quantity.exact(maxSafeBaseUnits, Unit.microgram).baseUnitsOrNull,
        maxSafeBaseUnits,
      );
    });

    test('one step past the boundary refuses rather than wrapping', () {
      expect(
        const Quantity.exact(maxSafeBaseUnits + 1, Unit.microgram)
            .baseUnitsOrNull,
        isNull,
      );
    });

    test('a kcal magnitude that would wrap is refused', () {
      // 418400 millijoules per increment is the largest multiplier in the unit
      // table, so kilocalorie is where an unguarded multiply wraps first.
      expect(
        const Quantity.exact(maxSafeBaseUnits, Unit.kilocalorie)
            .baseUnitsOrNull,
        isNull,
      );
    });

    test('the unguarded baseUnits is untouched for ordinary values', () {
      // S3: the existing API keeps its exact meaning. Only ordinary values are
      // asserted here — the unguarded path is not being blessed for extremes.
      expect(const Quantity.exact(3000, Unit.gram).baseUnits, 30000000);
    });
  });

  group('Quantity.boundsInOrNull — the live path (S3)', () {
    // 100 increments of `Unit.gram` is 1.00 g, which is 10^6 micrograms. The
    // delta is stated in the unit's own increments, not in base units.
    const ApproximationDeltas deltas =
        ApproximationDeltas(<Unit, int>{Unit.gram: 100});

    test('an exact quantity yields a point interval', () {
      final Interval? i =
          const Quantity.exact(3000, Unit.gram).boundsInOrNull(deltas);
      expect(i, isNotNull);
      expect(i!.infimum, 30000000);
      expect(i.supremum, 30000000);
    });

    test('an approximate quantity widens by the rule pack delta', () {
      final Interval? i =
          const Quantity.approximately(3000, Unit.gram).boundsInOrNull(deltas);
      expect(i, isNotNull);
      expect(i!.infimum, 30000000 - 1000000);
      expect(i.supremum, 30000000 + 1000000);
    });

    test('a LESS_THAN bound keeps its open lower end', () {
      final Interval? i =
          const Quantity.lessThan(3000, Unit.gram).boundsInOrNull(deltas);
      expect(i, isNotNull);
      expect(i!.infimum, 0);
      expect(i.supremum, 30000000);
    });

    test('a magnitude that would wrap the conversion is refused', () {
      expect(
        const Quantity.exact(maxSafeBaseUnits, Unit.kilocalorie)
            .boundsInOrNull(deltas),
        isNull,
      );
    });

    test('a pathological rule pack delta is refused, not wrapped', () {
      // The schema places no maximum on approximationDeltas.delta, so a
      // malformed pack can reach here. It must refuse rather than produce an
      // interval that has silently inverted.
      const ApproximationDeltas absurd =
          ApproximationDeltas(<Unit, int>{Unit.gram: maxSafeBaseUnits});
      expect(
        const Quantity.approximately(3000, Unit.gram).boundsInOrNull(absurd),
        isNull,
      );
    });

    test('a missing delta for an APPROXIMATELY value is refused', () {
      // Already S7's behaviour via hasDeltaFor; asserted here so the guarded
      // sibling cannot regress it into a throw.
      expect(
        const Quantity.approximately(3000, Unit.millilitre)
            .boundsInOrNull(deltas),
        isNull,
      );
    });
  });

  group('Tolerance.allowanceForOrNull — additive, guarded (S2)', () {
    test('an exact band allows nothing, either API', () {
      expect(const Tolerance.exact().allowanceForOrNull(1000000), 0);
      expect(const Tolerance.exact().allowanceFor(1000000), 0);
    });

    test('an absolute grace is the grace, either API', () {
      expect(Tolerance.grace(100000).allowanceForOrNull(1000000), 100000);
      expect(Tolerance.grace(100000).allowanceFor(1000000), 100000);
    });

    test('a relative band agrees with the unguarded API on ordinary values',
        () {
      // S2: existing semantics must not shift. 5% of 2.4 g in micrograms.
      final Tolerance band =
          Tolerance.relative(percentTenths: 50, floorBaseUnits: 100000);
      expect(band.allowanceForOrNull(2400000), band.allowanceFor(2400000));
      expect(band.allowanceForOrNull(2400000), 120000);
    });

    test('the floor still governs below the crossover', () {
      final Tolerance band =
          Tolerance.relative(percentTenths: 50, floorBaseUnits: 100000);
      expect(band.allowanceForOrNull(150000), 100000);
    });

    test('a reference large enough to wrap the percentage is refused', () {
      // reference * percentTenths is the multiplication at risk: the reference
      // arrives from an interval supremum, which is an intermediate rather than
      // a stored value.
      final Tolerance band =
          Tolerance.relative(percentTenths: 1000, floorBaseUnits: 0);
      expect(band.allowanceForOrNull(maxSafeProduct), isNull);
    });

    test('exactly the safe reference is permitted', () {
      final Tolerance band =
          Tolerance.relative(percentTenths: 1, floorBaseUnits: 0);
      expect(band.allowanceForOrNull(maxSafeProduct), isNotNull);
    });

    test('a negative reference is treated as a magnitude, either API', () {
      final Tolerance band =
          Tolerance.relative(percentTenths: 50, floorBaseUnits: 0);
      expect(band.allowanceForOrNull(-2400000), band.allowanceFor(-2400000));
    });
  });
}
