import 'package:lw_domain/src/invariants/invariant_id.dart';

/// How an allowance is derived from the magnitude being checked.
enum ToleranceKind {
  /// No allowance at all. The comparison is exact.
  exact,

  /// A fixed allowance, independent of magnitude.
  absolute,

  /// A percentage of the reference magnitude, never below a floor.
  relative,
}

/// The allowance an invariant grants before it reports a failure.
///
/// Invariants compare values that manufacturers have **independently rounded**
/// (`DATA_MODEL.md` §4.4). Without an allowance, a panel rounding saturated fat
/// up and total fat down would fail INV-02 on arithmetic that is entirely
/// legitimate. The allowance must absorb that rounding without absorbing a
/// genuine misread.
///
/// **A tolerance widens the comparison; it does not replace the interval**
/// (§4.3a). The qualifier describes what the manufacturer declared, the
/// tolerance describes how precisely they declared it, and the two compose.
///
/// Every magnitude here is in the **base units of the dimension being
/// compared** — micrograms for mass, millijoules for energy, hundredths for a
/// count — so that an allowance is exact for any pair of units in that
/// dimension.
final class Tolerance {
  const Tolerance._(
    this.kind,
    this.graceBaseUnits,
    this.percentTenths,
    this.floorBaseUnits,
  );

  /// No allowance. INV-01 and INV-09 are exact checks.
  const Tolerance.exact() : this._(ToleranceKind.exact, 0, 0, 0);

  /// A fixed allowance of [graceBaseUnits], whatever the magnitude.
  ///
  /// Throws [ArgumentError] when negative: an allowance that tightened the
  /// comparison would make a correct declaration fail.
  factory Tolerance.grace(int graceBaseUnits) {
    if (graceBaseUnits < 0) {
      throw ArgumentError.value(
        graceBaseUnits,
        'graceBaseUnits',
        'A grace cannot be negative; it would tighten the comparison.',
      );
    }
    return Tolerance._(ToleranceKind.absolute, graceBaseUnits, 0, 0);
  }

  /// [percentTenths] of the reference magnitude, never below [floorBaseUnits].
  ///
  /// Tenths of a percent, so 15% is `150`. The floor exists because a small
  /// declared magnitude would otherwise be checked to an absurdly tight band —
  /// `DATA_MODEL.md` §4.4 pairs every relative band with one.
  ///
  /// Throws [ArgumentError] when either is negative.
  factory Tolerance.relative({
    required int percentTenths,
    required int floorBaseUnits,
  }) {
    if (percentTenths < 0) {
      throw ArgumentError.value(
        percentTenths,
        'percentTenths',
        'A relative band cannot be negative.',
      );
    }
    if (floorBaseUnits < 0) {
      throw ArgumentError.value(
        floorBaseUnits,
        'floorBaseUnits',
        'A floor cannot be negative.',
      );
    }
    return Tolerance._(
      ToleranceKind.relative,
      0,
      percentTenths,
      floorBaseUnits,
    );
  }

  /// How the allowance is derived.
  final ToleranceKind kind;

  /// The fixed allowance, for [ToleranceKind.absolute]. Zero otherwise.
  final int graceBaseUnits;

  /// The band in tenths of a percent, for [ToleranceKind.relative].
  final int percentTenths;

  /// The minimum allowance, for [ToleranceKind.relative].
  final int floorBaseUnits;

  /// The allowance for a comparison against [referenceBaseUnits].
  ///
  /// The reference magnitude is taken as an absolute value: a band is a width,
  /// and a negative reference must not produce a negative allowance that would
  /// tighten the comparison instead of widening it.
  int allowanceFor(int referenceBaseUnits) => switch (kind) {
        // A switch expression, so a fourth kind cannot be added without
        // deciding how it derives its allowance.
        ToleranceKind.exact => 0,
        ToleranceKind.absolute => graceBaseUnits,
        ToleranceKind.relative => _relativeAllowance(referenceBaseUnits.abs()),
      };

  int _relativeAllowance(int reference) {
    final int band = reference * percentTenths ~/ 1000;
    return band > floorBaseUnits ? band : floorBaseUnits;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tolerance &&
          kind == other.kind &&
          graceBaseUnits == other.graceBaseUnits &&
          percentTenths == other.percentTenths &&
          floorBaseUnits == other.floorBaseUnits;

  @override
  int get hashCode =>
      Object.hash(kind, graceBaseUnits, percentTenths, floorBaseUnits);

  @override
  String toString() => switch (kind) {
        ToleranceKind.exact => 'Tolerance(exact)',
        ToleranceKind.absolute => 'Tolerance(+$graceBaseUnits)',
        ToleranceKind.relative =>
          'Tolerance(${percentTenths / 10}%, floor $floorBaseUnits)',
      };
}

/// The allowance each invariant is granted.
///
/// **Injected, not hard-coded**, matching the pattern approved at S3, S5 and
/// S6. `DATA_MODEL.md` §4.4 marks every band below as **provisional** and Q14
/// requires them to be calibrated against the golden corpus before the MVP
/// gate and recorded in the rule pack. Making the table replaceable is what
/// lets that calibration land without a code change.
///
/// > The architect's note in §4.4 is worth repeating: too loose and INV-07
/// > never fires, silently removing the primary confidence signal for energy;
/// > too tight and every label reports LOW. Neither failure announces itself.
final class ToleranceTable {
  /// Creates a table.
  ToleranceTable(Map<InvariantId, Tolerance> bands)
      : _bands = Map<InvariantId, Tolerance>.unmodifiable(bands);

  /// The provisional bands of `DATA_MODEL.md` §4.4.
  ///
  /// Mass graces are in micrograms (1 g = 1 000 000), energy in millijoules
  /// (1 kcal = 4 184 000), counts in hundredths (1 serving = 100).
  static final ToleranceTable defaults =
      ToleranceTable(<InvariantId, Tolerance>{
    InvariantId.inv01: const Tolerance.exact(),
    InvariantId.inv02: Tolerance.grace(100000),
    InvariantId.inv03: Tolerance.grace(100000),
    InvariantId.inv04: Tolerance.grace(100000),
    InvariantId.inv05: Tolerance.grace(500000),
    InvariantId.inv06: Tolerance.grace(2000000),
    InvariantId.inv07:
        Tolerance.relative(percentTenths: 150, floorBaseUnits: 83680000),
    InvariantId.inv08: Tolerance.relative(percentTenths: 50, floorBaseUnits: 0),
    InvariantId.inv09: const Tolerance.exact(),
    InvariantId.inv10:
        Tolerance.relative(percentTenths: 100, floorBaseUnits: 50),
  });

  final Map<InvariantId, Tolerance> _bands;

  /// The band for [id], or null when the table states none.
  ///
  /// Null rather than a silent default: a missing band would disable a check,
  /// and a disabled check that looks enabled is the failure mode §4.4 warns
  /// about.
  Tolerance? forInvariant(InvariantId id) => _bands[id];

  @override
  String toString() => 'ToleranceTable(${_bands.length} bands)';
}
