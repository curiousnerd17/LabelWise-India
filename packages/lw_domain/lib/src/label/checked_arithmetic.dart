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

/// The largest magnitude an **intermediate product** may reach before it is
/// treated as not computable.
///
/// `2^62`, roughly 4.6 × 10¹⁸ — inside the 2^63 range of a Dart `int`, and
/// three orders of magnitude above [maxSafeBaseUnits].
///
/// > **A different question from [maxSafeBaseUnits].** That bound asks *is this
/// > a plausible stored value?*; this one asks *did this multiplication wrap?*
/// > Using one constant for both rejects arithmetic that is perfectly safe: a
/// > legitimate 80 g per 100 g nutrient scaled to a 250 g serve — mithai, a
/// > family pack — has an intermediate of 2 × 10¹⁶, which is above the storage
/// > bound and nowhere near a wrap. Conflating them would report an honest
/// > label as unreadable.
///
/// Both operands of an interval multiplication are themselves bounded by
/// [maxSafeBaseUnits], so a product of two valid quantities can legitimately
/// reach 10³¹ — far past this bound. That is why the product bound *refuses*
/// rather than *permits*: it is a wrap guard, and a refusal becomes
/// `INDETERMINATE`, never a verdict.
///
/// **Never use this as a plausibility limit.** A value this large is not a
/// declared quantity; it is only ever an intermediate.
const int maxSafeProduct = 1 << 62;

/// `a × b`, or null when the product would exceed [limit].
///
/// [limit] defaults to [maxSafeBaseUnits], the bound for a value that will be
/// **stored**. Pass [maxSafeProduct] where the result is an *intermediate* that
/// is immediately divided back down — interval scaling, the Atwater terms —
/// because the storage bound would refuse legitimate labels there.
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
int? checkedMultiply(int a, int b, {int limit = maxSafeBaseUnits}) {
  if (a == 0 || b == 0) {
    return 0;
  }
  final int magnitudeA = a.abs();
  final int magnitudeB = b.abs();
  // Guard the divisor check itself: an operand already past the limit cannot
  // produce a usable product whatever it is multiplied by.
  if (magnitudeA > limit || magnitudeB > limit) {
    return null;
  }
  if (magnitudeA > limit ~/ magnitudeB) {
    return null;
  }
  return a * b;
}

/// `a + b`, or null when the sum would exceed [limit].
///
/// Addition overflows far less readily than multiplication, but the Atwater
/// estimate accumulates three scaled terms and a pathological declaration
/// reaches the bound through repeated addition alone.
///
/// [limit] defaults to [maxSafeBaseUnits], as for [checkedMultiply]. The
/// Atwater accumulator passes [maxSafeProduct] because its addends are
/// *products* rather than stored values — summing three intermediates each
/// bounded by `2^62` is the one place where the sum itself can wrap, and the
/// sign-inversion check below is what catches that.
int? checkedAdd(int a, int b, {int limit = maxSafeBaseUnits}) {
  final int sum = a + b;
  // Sign inversion is the signature of a wrap: two positives cannot sum to a
  // negative unless the result left the representable range.
  if (a > 0 && b > 0 && sum < 0) {
    return null;
  }
  if (a < 0 && b < 0 && sum > 0) {
    return null;
  }
  if (sum.abs() > limit) {
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
