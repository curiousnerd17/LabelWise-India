/// The largest magnitude any base-unit quantity or intermediate product may
/// reach before it is treated as not computable.
///
/// `2^52`, roughly 4.5 × 10¹⁵. Chosen against the physical scale of the
/// problem rather than the machine: the base unit for mass is the microgram, so
/// a **one-tonne** pack is 10¹² base units — three orders of magnitude below
/// this bound. Anything above it did not come from a food label.
///
/// The bound sits well inside the 2^63 range of a Dart `int`, which is what
/// makes [checkedMultiply] able to detect an overflow *before* it happens by
/// checking the operands, rather than after by inspecting a wrapped result.
const int maxSafeBaseUnits = 1 << 52;

/// `a × b`, or null when the product would exceed [maxSafeBaseUnits].
///
/// **Dart integers wrap silently on 64-bit overflow**, turning an absurd
/// declared value into a plausible-looking negative one. A wrapped product
/// feeding an interval comparison would not throw and would not look wrong —
/// it would simply produce a confident, incorrect verdict, which is the single
/// failure mode this product exists to avoid (P1).
///
/// Null rather than a throw, because every call site already has a
/// not-computable channel: `_scaleByServe` and `_divideOut` return `Interval?`
/// and their callers map null to `INDETERMINATE`. Overflow therefore reuses an
/// existing, tested path instead of introducing a second failure vocabulary.
///
/// Operands are compared before multiplying, so nothing ever wraps.
int? checkedMultiply(int a, int b) {
  if (a == 0 || b == 0) {
    return 0;
  }
  final int magnitudeA = a.abs();
  final int magnitudeB = b.abs();
  // Guard the divisor check itself: an operand already past the bound cannot
  // produce a usable product whatever it is multiplied by.
  if (magnitudeA > maxSafeBaseUnits || magnitudeB > maxSafeBaseUnits) {
    return null;
  }
  if (magnitudeA > maxSafeBaseUnits ~/ magnitudeB) {
    return null;
  }
  return a * b;
}

/// `a + b`, or null when the sum would exceed [maxSafeBaseUnits].
///
/// Addition overflows far less readily than multiplication, but the Atwater
/// estimate accumulates three scaled terms and a pathological declaration
/// reaches the bound through repeated addition alone.
int? checkedAdd(int a, int b) {
  final int sum = a + b;
  // Sign inversion is the signature of a wrap: two positives cannot sum to a
  // negative unless the result left the representable range.
  if (a > 0 && b > 0 && sum < 0) {
    return null;
  }
  if (a < 0 && b < 0 && sum > 0) {
    return null;
  }
  if (sum.abs() > maxSafeBaseUnits) {
    return null;
  }
  return sum;
}

/// Whether [value] is within the representable range for a base-unit quantity.
///
/// Used at the point a value **enters** the pipeline, so an absurd reading is
/// refused where it is read rather than several stages later where the
/// diagnostic would name the wrong thing.
bool isSafeBaseUnitMagnitude(int value) => value.abs() <= maxSafeBaseUnits;
