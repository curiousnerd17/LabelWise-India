import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// The guards exist because **Dart integers wrap silently on 64-bit overflow**.
/// A wrapped product does not throw and does not look wrong — it produces a
/// confident, incorrect verdict, which is the one failure mode this product
/// exists to prevent (P1).
///
/// M11a tests the primitives. Applying them to S7's interval arithmetic is
/// M11b.
void main() {
  group('maxSafeBaseUnits — chosen against the problem, not the machine', () {
    test('the bound is far above any real pack and far below 2^63', () {
      // Mass is tracked in micrograms, so a one-tonne pack is 10^12 base
      // units. The bound must clear that by orders of magnitude while leaving
      // room for a product to be computed without wrapping.
      expect(maxSafeBaseUnits, 1 << 52);
      expect(maxSafeBaseUnits, greaterThan(1000000000000));
      expect(maxSafeBaseUnits, lessThan(1 << 62));
    });
  });

  group('checkedMultiply', () {
    test('an ordinary product is returned unchanged', () {
      // 8.00 g per 100 g scaled by a 30 g serve, in micrograms.
      expect(checkedMultiply(8000000, 30000000), 240000000000000);
      expect(checkedMultiply(6, 7), 42);
    });

    test('zero short-circuits on either side', () {
      // Zero is a legitimate declared value, so this is a real path and not a
      // defensive one: a pack declaring 0 g of trans fat multiplies by zero.
      expect(checkedMultiply(0, 999999999999999), 0);
      expect(checkedMultiply(999999999999999, 0), 0);
      expect(checkedMultiply(0, 0), 0);
    });

    test('negative operands multiply normally within the bound', () {
      // Negative values reach here from a misread label before INV-01 rejects
      // them, so the guard must handle them rather than assume positivity.
      expect(checkedMultiply(-4, 5), -20);
      expect(checkedMultiply(-4, -5), 20);
    });

    test('exactly the bound is permitted', () {
      expect(checkedMultiply(maxSafeBaseUnits, 1), maxSafeBaseUnits);
      expect(checkedMultiply(1, maxSafeBaseUnits), maxSafeBaseUnits);
    });

    test('one step past the bound is refused', () {
      // The boundary that matters: the first product that must not be trusted.
      expect(checkedMultiply(maxSafeBaseUnits + 1, 1), isNull);
      expect(checkedMultiply(1, maxSafeBaseUnits + 1), isNull);
      expect(checkedMultiply(2, maxSafeBaseUnits), isNull);
    });

    test('an operand already past the bound is refused before multiplying', () {
      // Guards the divisor check itself: a value this large cannot produce a
      // usable product whatever it is multiplied by.
      expect(checkedMultiply(maxSafeBaseUnits * 4, 3), isNull);
      expect(checkedMultiply(3, maxSafeBaseUnits * 4), isNull);
    });

    test('a product that would wrap is refused, never returned negative', () {
      // Without the guard this returns a plausible-looking negative number.
      final int? product = checkedMultiply(1 << 40, 1 << 40);
      expect(product, isNull);
    });

    test('the refusal is symmetric in the operands', () {
      expect(
          checkedMultiply(1 << 40, 1 << 30), checkedMultiply(1 << 30, 1 << 40));
    });
  });

  group('maxSafeProduct — wrap safety, never plausibility (BL-1)', () {
    test('it is a distinct, larger bound than the storage bound', () {
      // Two unrelated questions: "is this a plausible stored value?" and "did
      // this multiplication wrap?". One constant answering both is what made
      // M11a's guard unusable on the S7 helpers.
      expect(maxSafeProduct, greaterThan(maxSafeBaseUnits));
      expect(maxSafeProduct, 1 << 62);
      expect(maxSafeProduct, lessThan(0x7FFFFFFFFFFFFFFF));
    });

    test('a legitimate large label is NOT rejected', () {
      // The acceptance criterion. 80 g per 100 g scaled by a 250 g serve —
      // mithai, thali, family packs. In micrograms the intermediate is 2e16,
      // which exceeds the STORAGE bound while being nowhere near a wrap.
      const int per100g = 80 * 1000000; // 80 g in ug
      const int serve = 250 * 1000000; // 250 g in ug
      expect(checkedMultiply(per100g, serve, limit: maxSafeProduct),
          20000000000000000);
      expect(
        checkedMultiply(per100g, serve),
        isNull,
        reason: 'the storage bound rightly refuses it; the product bound must '
            'not — which is exactly why they are separate',
      );
    });

    test('a 100 g per 100 g nutrient on a 500 g serve is accepted', () {
      expect(
        checkedMultiply(100 * 1000000, 500 * 1000000, limit: maxSafeProduct),
        isNotNull,
      );
    });

    test('the Atwater per-term product is accepted at realistic magnitude', () {
      // 100 g of fat in micrograms times 37656 microjoules per microgram.
      expect(checkedMultiply(100 * 1000000, 37656, limit: maxSafeProduct),
          isNotNull);
    });

    test('exactly the product bound is permitted', () {
      expect(checkedMultiply(maxSafeProduct, 1, limit: maxSafeProduct),
          maxSafeProduct);
    });

    test('one step past the product bound is refused', () {
      expect(checkedMultiply(maxSafeProduct + 1, 1, limit: maxSafeProduct),
          isNull);
      expect(checkedMultiply(2, maxSafeProduct, limit: maxSafeProduct), isNull);
    });

    test('a genuine wrap is still refused under the product bound', () {
      // 2^80 cannot be represented at all.
      expect(checkedMultiply(1 << 40, 1 << 40, limit: maxSafeProduct), isNull);
    });

    test('a pathological magnitude times an Atwater factor is refused', () {
      expect(checkedMultiply(maxSafeBaseUnits, 37656, limit: maxSafeProduct),
          isNull);
    });

    test('the default limit is unchanged, so M11a behaviour is preserved', () {
      // Every committed M11a assertion depends on this.
      expect(checkedMultiply(2, maxSafeBaseUnits), isNull);
      expect(checkedMultiply(maxSafeBaseUnits, 1), maxSafeBaseUnits);
    });

    test('zero and negatives behave identically under either limit', () {
      expect(checkedMultiply(0, 1 << 40, limit: maxSafeProduct), 0);
      expect(checkedMultiply(-4, 5, limit: maxSafeProduct), -20);
      expect(
          checkedMultiply(-(1 << 40), 1 << 40, limit: maxSafeProduct), isNull);
    });
  });

  group('checkedAdd', () {
    test('an ordinary sum is returned unchanged', () {
      // The Atwater estimate accumulates three scaled terms this way.
      expect(checkedAdd(1000000, 2000000), 3000000);
      expect(checkedAdd(-5, 3), -2);
    });

    test('exactly the bound is permitted', () {
      expect(checkedAdd(maxSafeBaseUnits - 1, 1), maxSafeBaseUnits);
      expect(checkedAdd(-maxSafeBaseUnits + 1, -1), -maxSafeBaseUnits);
    });

    test('one step past the bound is refused, either sign', () {
      expect(checkedAdd(maxSafeBaseUnits, 1), isNull);
      expect(checkedAdd(-maxSafeBaseUnits, -1), isNull);
    });

    test('a sum that would wrap is refused', () {
      // Sign inversion is the signature of a wrap: two positives cannot sum to
      // a negative unless the result left the representable range.
      const int huge = 0x7FFFFFFFFFFFFFFF;
      expect(checkedAdd(huge, 1), isNull);
      expect(checkedAdd(-huge, -2), isNull);
    });
  });

  group('isSafeBaseUnitMagnitude', () {
    test('accepts a value at or inside the bound, either sign', () {
      expect(isSafeBaseUnitMagnitude(0), isTrue);
      expect(isSafeBaseUnitMagnitude(30000000), isTrue);
      expect(isSafeBaseUnitMagnitude(maxSafeBaseUnits), isTrue);
      expect(isSafeBaseUnitMagnitude(-maxSafeBaseUnits), isTrue);
    });

    test('refuses a value past the bound, either sign', () {
      // Used where a value *enters* the pipeline, so an absurd reading is
      // refused where it is read rather than several stages later.
      expect(isSafeBaseUnitMagnitude(maxSafeBaseUnits + 1), isFalse);
      expect(isSafeBaseUnitMagnitude(-maxSafeBaseUnits - 1), isFalse);
    });
  });
}
