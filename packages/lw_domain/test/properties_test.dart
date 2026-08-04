import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

// always_use_package_imports is scoped to files under lib/. Test helpers live
// under test/ and have no package: URI, so a relative import is correct here
// and is not flagged.
import 'support/generators.dart';

/// Property tests PT-01…PT-04, PT-08, PT-15, PT-17, PT-18, PT-19
/// (`TEST_STRATEGY.md` §3.1).
///
/// Examples catch the cases you thought of. Properties catch the ones you did
/// not — which, for a lattice and an interval algebra, is most of them.
void main() {
  group('PT-01…04 the confidence lattice obeys its laws', () {
    test('PT-01 meet never exceeds either operand (MI-04, FR-CNF-06)', () {
      forAll('meet is a lower bound', (Gen gen) {
        final Confidence a = gen.confidence();
        final Confidence b = gen.confidence();
        final Confidence met = a.meet(b);
        expect(met.index, lessThanOrEqualTo(a.index));
        expect(met.index, lessThanOrEqualTo(b.index));
      });
    });

    test('PT-02 meet is commutative', () {
      forAll('meet is commutative', (Gen gen) {
        final Confidence a = gen.confidence();
        final Confidence b = gen.confidence();
        expect(a.meet(b), b.meet(a));
      });
    });

    test('PT-03 meet is associative', () {
      // Associativity plus commutativity is what makes propagation order
      // irrelevant, which is what makes FR-CNF-06 determinism provable rather
      // than merely intended.
      forAll('meet is associative', (Gen gen) {
        final Confidence a = gen.confidence();
        final Confidence b = gen.confidence();
        final Confidence c = gen.confidence();
        expect(a.meet(b).meet(c), a.meet(b.meet(c)));
      });
    });

    test('PT-04 meet is idempotent', () {
      forAll('meet is idempotent', (Gen gen) {
        final Confidence a = gen.confidence();
        expect(a.meet(a), a);
      });
    });

    test('PT-01 meetAll never exceeds its least member', () {
      forAll('meetAll is a lower bound', (Gen gen) {
        final List<Confidence> levels = <Confidence>[
          for (int i = 0; i < gen.intInRange(1, 6); i++) gen.confidence(),
        ];
        final Confidence met = Confidence.meetAll(levels);
        for (final Confidence level in levels) {
          expect(met.index, lessThanOrEqualTo(level.index));
        }
      });
    });
  });

  group('PT-08 unit conversion', () {
    test('PT-08 coarse to fine and back is lossless', () {
      // Converting to a finer unit loses nothing, so the round trip is exact.
      // Converting to a coarser one rounds — that is what scale means, and the
      // property deliberately does not claim otherwise.
      forAll('coarse-fine round trip', (Gen gen) {
        final Dimension dimension = <Dimension>[
          Dimension.mass,
          Dimension.volume,
        ][gen.intInRange(0, 1)];
        final Quantity original = gen.quantityOfDimension(dimension);
        final Unit finer = Unit.values
            .where((Unit u) => u.dimension == dimension)
            .reduce((Unit a, Unit b) =>
                a.baseUnitsPerIncrement <= b.baseUnitsPerIncrement ? a : b);
        final Quantity roundTripped =
            original.convertTo(finer).convertTo(original.unit);
        expect(roundTripped, original);
      });
    });

    test('PT-08 conversion within a dimension is total', () {
      forAll('conversion is total', (Gen gen) {
        final Quantity q = gen.quantity();
        for (final Unit target in Unit.values) {
          if (q.unit.isConvertibleTo(target)) {
            expect(q.convertTo(target).unit, target);
          } else {
            expect(() => q.convertTo(target), throwsA(isA<ArgumentError>()));
          }
        }
      });
    });

    test('PT-08 conversion preserves the qualifier', () {
      forAll('conversion preserves qualifier', (Gen gen) {
        final Quantity q = gen.quantity();
        final Unit target = gen.unitOfDimension(q.unit.dimension);
        expect(q.convertTo(target).qualifier, q.qualifier);
      });
    });
  });

  group('PT-15 Version ordering is a total order', () {
    test('PT-15 ordering is antisymmetric and transitive', () {
      forAll('version total order', (Gen gen) {
        final Version a = gen.version();
        final Version b = gen.version();
        final Version c = gen.version();

        expect(a.compareTo(b).sign, -b.compareTo(a).sign);
        if (a <= b && b <= c) {
          expect(a <= c, isTrue);
        }
        if (a == b) {
          expect(a.compareTo(b), 0);
          expect(a.hashCode, b.hashCode);
        }
      });
    });
  });

  group('PT-17 equality distinguishes qualifiers (MI-14, ADR-0027)', () {
    test('PT-17 LESS_THAN v is never equal to EXACT v', () {
      forAll('qualifier participates in equality', (Gen gen) {
        final int value = gen.scaledValue();
        final Unit unit = gen.unit();
        expect(
          Quantity.lessThan(value, unit),
          isNot(Quantity.exact(value, unit)),
        );
        expect(
          Quantity.greaterThan(value, unit),
          isNot(Quantity.exact(value, unit)),
        );
      });
    });

    test('PT-17 equal quantities agree on hashCode', () {
      forAll('hashCode agrees with equality', (Gen gen) {
        final Quantity a = gen.quantity();
        final Quantity b =
            Quantity.qualified(a.scaledValue, a.unit, a.qualifier);
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });
    });
  });

  group('PT-18 interval comparison is sound (MI-16)', () {
    const ApproximationDeltas none = ApproximationDeltas.none;

    test('PT-18 a definite verdict is never returned for overlapping bounds',
        () {
      // Soundness: whenever comparison claims a definite outcome, that outcome
      // must hold for every pair of values the two intervals admit. Sampling
      // representative members is enough to catch a boundary error.
      forAll('comparison soundness', (Gen gen) {
        final Dimension dimension = Dimension.mass;
        final Quantity a = gen.boundableQuantity(dimension);
        final Quantity b = gen.boundableQuantity(dimension);
        final Trilean verdict = a.isAtMost(b, none);
        final Interval ia = a.boundsIn(none);
        final Interval ib = b.boundsIn(none);

        if (verdict == Trilean.definitelyTrue) {
          // Every member of a is at most every member of b, so in particular
          // the largest of a is at most the smallest of b.
          expect(ia.supremum, isNotNull);
          expect(ia.supremum!, lessThanOrEqualTo(ib.infimum));
        } else if (verdict == Trilean.definitelyFalse) {
          // Every member of a exceeds every member of b.
          expect(ib.supremum, isNotNull);
          expect(ia.infimum, greaterThanOrEqualTo(ib.supremum!));
        }
        // Indeterminate asserts nothing: an unresolvable comparison is the
        // correct outcome, not a weaker one.
      });
    });

    test('PT-18 comparing a value with itself is definitely true', () {
      forAll('reflexivity of isAtMost', (Gen gen) {
        final Quantity q = gen.boundableQuantity(Dimension.mass);
        if (q.qualifier == Qualifier.exact) {
          expect(q.isAtMost(q, none), Trilean.definitelyTrue);
        }
      });
    });

    test('PT-18 isAtLeast is the mirror of isAtMost', () {
      forAll('isAtLeast mirrors isAtMost', (Gen gen) {
        final Quantity a = gen.boundableQuantity(Dimension.mass);
        final Quantity b = gen.boundableQuantity(Dimension.mass);
        expect(a.isAtLeast(b, none), b.isAtMost(a, none));
      });
    });

    test('PT-18 Trilean negation leaves indeterminate untouched', () {
      // An unresolvable comparison stays unresolvable. Negating it into a
      // definite answer would be exactly the coercion ADR-0027 forbids.
      expect(Trilean.indeterminate.negated, Trilean.indeterminate);
      expect(Trilean.definitelyTrue.negated, Trilean.definitelyFalse);
      expect(Trilean.definitelyFalse.negated, Trilean.definitelyTrue);
    });
  });

  group('PT-19 scaling preserves the bound direction', () {
    test('PT-19 a positive scale never changes the qualifier', () {
      forAll('scaling preserves qualifier', (Gen gen) {
        final Quantity q = gen.quantity();
        final Quantity scaled = q.scaledBy(
          numerator: gen.intInRange(1, 500),
          denominator: gen.intInRange(1, 500),
        );
        expect(scaled.qualifier, q.qualifier);
        expect(scaled.unit, q.unit);
      });
    });

    test('PT-19 scaling by one is the identity', () {
      forAll('scaling identity', (Gen gen) {
        final Quantity q = gen.quantity();
        expect(q.scaledBy(numerator: 1, denominator: 1), q);
      });
    });

    test('PT-19 scaling is monotonic in the declared value', () {
      forAll('scaling monotonicity', (Gen gen) {
        final Quantity q = gen.quantity();
        final int factor = gen.intInRange(2, 50);
        final Quantity larger = q.scaledBy(numerator: factor, denominator: 1);
        expect(larger.scaledValue, greaterThanOrEqualTo(q.scaledValue));
      });
    });
  });
}
