import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Quantity — qualifiers are part of the value (ADR-0027)', () {
    test('FR-PAR-18 a LESS_THAN value is not equal to an EXACT value', () {
      // The two declarations mean different things. A parser that reads
      // "< 0.5 g" as "0.5 g" records an Error, not a near-miss
      // (TEST_STRATEGY.md 4.2).
      expect(
        const Quantity.lessThan(50, Unit.gram),
        isNot(const Quantity.exact(50, Unit.gram)),
      );
    });

    test('FR-PAR-18 EXACT is the default qualifier', () {
      expect(const Quantity.exact(250, Unit.gram).qualifier, Qualifier.exact);
    });

    test('MI-14 equality distinguishes units of equal magnitude', () {
      // 2.5 g and 2500 mg denote the same mass but are different declarations.
      // Normalising them is a measured parser behaviour (FR-PAR-06), not an
      // equality concern.
      expect(
        const Quantity.exact(250, Unit.gram),
        isNot(const Quantity.exact(25000, Unit.milligram)),
      );
    });

    test('MI-16 comparison is three-valued, never boolean', () {
      // Quantity declares no <, >, <=, >= or compareTo: their absence is the
      // enforcement, and it is a compile-time property rather than a runtime
      // one. What is testable is that the comparison that DOES exist cannot
      // collapse a straddling interval into a definite answer.
      final Trilean verdict = const Quantity.lessThan(6000, Unit.milligram)
          .isAtMost(const Quantity.exact(5000, Unit.milligram),
              ApproximationDeltas.none);
      expect(verdict, isA<Trilean>());
      expect(verdict, Trilean.indeterminate);
    });
  });

  group('Quantity — interval semantics', () {
    test('ADR-0027 EXACT denotes a point', () {
      final Interval bounds = const Quantity.exact(250, Unit.gram)
          .boundsIn(ApproximationDeltas.none);
      expect(bounds.isPoint, isTrue);
      expect(bounds.infimum, 250 * 10000);
    });

    test('ADR-0027 LESS_THAN denotes [0, v) with zero lower bound', () {
      final Interval bounds = const Quantity.lessThan(50, Unit.gram)
          .boundsIn(ApproximationDeltas.none);
      expect(bounds.infimum, 0, reason: 'lower bound zero by INV-01');
      expect(bounds.infimumInclusive, isTrue);
      expect(bounds.supremum, 50 * 10000);
      expect(bounds.supremumInclusive, isFalse);
    });

    test('ADR-0027 GREATER_THAN is unbounded above', () {
      final Interval bounds = const Quantity.greaterThan(50, Unit.gram)
          .boundsIn(ApproximationDeltas.none);
      expect(bounds.supremum, isNull);
      expect(bounds.infimumInclusive, isFalse);
    });

    test('ADR-0027 APPROXIMATELY uses the rule pack delta', () {
      const ApproximationDeltas deltas =
          ApproximationDeltas(<Unit, int>{Unit.count: 50});
      final Interval bounds =
          const Quantity.approximately(400, Unit.count).boundsIn(deltas);
      // "About 4 servings" with a half-width of 0.5 servings.
      expect(bounds.infimum, 350);
      expect(bounds.supremum, 450);
    });

    test('ADR-0027 an approximate value without a delta cannot be bounded', () {
      // Guessing a delta would invent precision the rule pack did not
      // authorise, so this is a programming error rather than a default.
      expect(
        () => const Quantity.approximately(400, Unit.count)
            .boundsIn(ApproximationDeltas.none),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Quantity — three-valued comparison (FR-L2-14, FR-CNF-14)', () {
    const ApproximationDeltas none = ApproximationDeltas.none;

    test('FR-L2-14 a bound below the threshold settles definitely', () {
      // "< 400 mg" sodium against a 500 mg threshold: sup 400 < 500.
      expect(
        const Quantity.lessThan(4000, Unit.milligram)
            .isAtMost(const Quantity.exact(5000, Unit.milligram), none),
        Trilean.definitelyTrue,
      );
    });

    test('FR-L2-14 a bound straddling the threshold is indeterminate', () {
      // "< 600 mg" against 500 mg: the declaration does not settle it. This is
      // the case the whole qualifier model exists to represent.
      expect(
        const Quantity.lessThan(6000, Unit.milligram)
            .isAtMost(const Quantity.exact(5000, Unit.milligram), none),
        Trilean.indeterminate,
      );
    });

    test('FR-L2-14 a GREATER_THAN above the threshold settles definitely', () {
      expect(
        const Quantity.greaterThan(6000, Unit.milligram)
            .isAtMost(const Quantity.exact(5000, Unit.milligram), none),
        Trilean.definitelyFalse,
      );
    });

    test('FR-CNF-14 exact values compare definitely in both directions', () {
      const Quantity smaller = Quantity.exact(100, Unit.gram);
      const Quantity larger = Quantity.exact(200, Unit.gram);
      expect(smaller.isAtMost(larger, none), Trilean.definitelyTrue);
      expect(larger.isAtMost(smaller, none), Trilean.definitelyFalse);
      expect(smaller.isAtMost(smaller, none), Trilean.definitelyTrue);
    });

    test('FR-CNF-14 comparison is exact across kcal and kJ', () {
      // 100 kcal == 418.4 kJ. Compared in millijoules, so no rounding occurs.
      const Quantity hundredKcal = Quantity.exact(1000, Unit.kilocalorie);
      const Quantity equivalentKj = Quantity.exact(4184, Unit.kilojoule);
      expect(hundredKcal.isAtMost(equivalentKj, none), Trilean.definitelyTrue);
      expect(equivalentKj.isAtMost(hundredKcal, none), Trilean.definitelyTrue);
    });

    test('FR-PAR-05 comparing different dimensions is a programming error', () {
      expect(
        () => const Quantity.exact(1, Unit.gram)
            .isAtMost(const Quantity.exact(1, Unit.millilitre), none),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Quantity — conversion and scaling', () {
    test('FR-PAR-06 converting to a finer unit is lossless', () {
      expect(
        const Quantity.exact(250, Unit.gram).convertTo(Unit.milligram),
        const Quantity.exact(25000, Unit.milligram),
      );
    });

    test('FR-PAR-06 conversion preserves the qualifier', () {
      expect(
        const Quantity.lessThan(50, Unit.gram)
            .convertTo(Unit.milligram)
            .qualifier,
        Qualifier.lessThan,
      );
    });

    test('FR-PAR-07 kJ converts to kcal under the single rounding policy', () {
      // 418.4 kJ == 100.0 kcal exactly.
      expect(
        const Quantity.exact(4184, Unit.kilojoule).convertTo(Unit.kilocalorie),
        const Quantity.exact(1000, Unit.kilocalorie),
      );
    });

    test('FR-PAR-06 converting to a coarser unit rounds to its scale', () {
      // 5 ug is below the 0.01 g increment and rounds away. Scale defines
      // tracked precision; this is its meaning, not a defect.
      expect(
        const Quantity.exact(5, Unit.microgram).convertTo(Unit.gram),
        const Quantity.exact(0, Unit.gram),
      );
    });

    test('FR-L1-02 scaling preserves the bound direction', () {
      // "< 0.5 g" per 100 g becomes "< 1.0 g" for a 200 g pack.
      final Quantity perPack = const Quantity.lessThan(50, Unit.gram)
          .scaledBy(numerator: 200, denominator: 100);
      expect(perPack, const Quantity.lessThan(100, Unit.gram));
    });

    test('FR-L1-02 a non-positive scale ratio is rejected', () {
      // A negative ratio would invert a declared bound; no basis change does.
      expect(
        () => const Quantity.exact(100, Unit.gram)
            .scaledBy(numerator: -1, denominator: 100),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Quantity — debugging representation', () {
    test('FR-LOC-01 toString is a debug form, never a display format', () {
      // Wrapped in the type name so that a leak into the UI looks obviously
      // wrong on screen. User-facing text resolves through message IDs; the
      // domain holds identity, never content.
      expect(
        const Quantity.exact(250, Unit.gram).toString(),
        'Quantity(2.50 g)',
      );
      expect(
        const Quantity.lessThan(50, Unit.gram).toString(),
        'Quantity(< 0.50 g)',
      );
      expect(
        const Quantity.approximately(400, Unit.count).toString(),
        'Quantity(~ 4.00)',
      );
    });
  });
}
