import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Confidence — lattice ordering (ADR-0010)', () {
    test('FR-CNF-01 there are exactly four levels and no percentage', () {
      // A numeric percentage would imply a precision the signals do not possess
      // (FR-CNF-10). Four coarse honest levels beat a fabricated number.
      expect(Confidence.values, hasLength(4));
      expect(
        Confidence.values,
        <Confidence>[
          Confidence.absent,
          Confidence.low,
          Confidence.medium,
          Confidence.high,
        ],
      );
    });

    test('FR-CNF-06 meet returns the lesser level', () {
      expect(Confidence.high.meet(Confidence.low), Confidence.low);
      expect(Confidence.medium.meet(Confidence.absent), Confidence.absent);
      expect(Confidence.high.meet(Confidence.high), Confidence.high);
    });

    test('FR-CNF-06 meetAll of an empty set is absent', () {
      // A value derived from nothing has nothing to trust. Defaulting to high
      // would manufacture confidence out of an absence of inputs.
      expect(Confidence.meetAll(const <Confidence>[]), Confidence.absent);
    });

    test('FR-CNF-05 downgraded steps one level and floors at absent', () {
      expect(Confidence.high.downgraded, Confidence.medium);
      expect(Confidence.low.downgraded, Confidence.absent);
      expect(Confidence.absent.downgraded, Confidence.absent);
    });

    test('FR-CNF-08 isAtLeast orders the levels for presentation', () {
      expect(Confidence.high.isAtLeast(Confidence.medium), isTrue);
      expect(Confidence.low.isAtLeast(Confidence.medium), isFalse);
    });
  });
}
