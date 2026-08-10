import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/src/decode/primitives.dart';
import 'package:lw_rulepack/src/json_view.dart';

/// Everything `rules/confidence.json` carries.
///
/// Three tables in one file because they are calibrated together: the
/// assignment rules, the invariant tolerance bands, and the `APPROXIMATELY`
/// widths.
final class ConfidenceBundle {
  /// Records the three decoded tables.
  const ConfidenceBundle({
    required this.policy,
    required this.tolerances,
    required this.approximationDeltas,
  });

  /// The S1/S2/S3 assignment table (S8).
  final ConfidencePolicy policy;

  /// The invariant tolerance bands (S7).
  final ToleranceTable tolerances;

  /// The `APPROXIMATELY` widths (S7, ADR-0027).
  final ApproximationDeltas approximationDeltas;
}

/// Decodes `rules/confidence.json`.
final class ConfidenceDecoder {
  const ConfidenceDecoder._();

  /// Tenths of a percent per whole fraction — `0.15` becomes `150`.
  static const int _tenthsPerUnitFraction = 1000;

  /// Decodes the whole file.
  static ConfidenceBundle decode(JsonView root) => ConfidenceBundle(
        policy: _policy(root.required('assignment')),
        tolerances: _tolerances(root.required('tolerances')),
        approximationDeltas: _deltas(root.required('approximationDeltas')),
      );

  /// Decodes the ordered assignment table.
  ///
  /// **Order is the whole semantics** and is preserved exactly: first match
  /// wins, and the pack states the failed-invariant rule first so that
  /// FR-CNF-05 holds absolutely. Sorting or de-duplicating here would silently
  /// let an `EXACT` parse outvote arithmetic that does not reconcile.
  static ConfidencePolicy _policy(JsonView assignment) {
    final List<ConfidenceRule> rules = <ConfidenceRule>[];
    for (final JsonView v in assignment.elements) {
      final JsonView when = v.required('when');
      try {
        rules.add(
          ConfidenceRule(
            result: v.required('result').asEnum(Primitives.confidences),
            anyInvariantFailed: when.has('anyInvariantFailed')
                ? when.required('anyInvariantFailed').asBool
                : null,
            parseStrength: when.has('parseStrength')
                ? when.required('parseStrength').asEnum(
                      Primitives.parseStrengths,
                    )
                : null,
          ),
        );
      } on ArgumentError catch (e) {
        // A rule with no condition matches everything and would shadow every
        // rule after it — the failure an ordered first-match table is most
        // prone to and the hardest to notice once the pack grows.
        v.reject(RulePackFailureKind.schemaViolation, '${e.message}');
      }
    }
    return ConfidencePolicy(rules);
  }

  /// Decodes the invariant tolerance bands.
  static ToleranceTable _tolerances(JsonView tolerances) {
    final Map<String, InvariantId> invariants = Primitives.invariants;
    final Map<InvariantId, Tolerance> bands = <InvariantId, Tolerance>{};
    for (final JsonView v in tolerances.elements) {
      final InvariantId id = v.required('invariantId').asEnum(invariants);
      if (bands.containsKey(id)) {
        v.reject(
          RulePackFailureKind.duplicateKey,
          'Two tolerance bands for ${id.code}.',
        );
      }
      bands[id] = _band(v);
    }
    return ToleranceTable(bands);
  }

  static Tolerance _band(JsonView v) {
    final String mode = v.required('mode').asString;
    try {
      return switch (mode) {
        'EXACT' => const Tolerance.exact(),
        'ABSOLUTE' => Tolerance.grace(_floor(v)),
        'RELATIVE' => Tolerance.relative(
            percentTenths: _percentTenths(v),
            floorBaseUnits: 0,
          ),
        'RELATIVE_WITH_FLOOR' => Tolerance.relative(
            percentTenths: _percentTenths(v),
            floorBaseUnits: _floor(v),
          ),
        _ => v.reject(
            RulePackFailureKind.schemaViolation,
            'Expected one of ABSOLUTE, EXACT, RELATIVE, RELATIVE_WITH_FLOOR, '
            'found "$mode".',
          ),
      };
    } on ArgumentError catch (e) {
      v.reject(RulePackFailureKind.schemaViolation, '${e.message}');
    }
  }

  static int _floor(JsonView v) =>
      Primitives.toBaseUnits(Primitives.quantity(v.required('absoluteFloor')));

  /// Converts `relativeFraction` to tenths of a percent, **exactly or not at
  /// all**.
  ///
  /// The schema types this as a JSON number, so `0.15` arrives as a `double`
  /// and the domain wants the integer `150`. The three shipped values convert
  /// exactly; `0.1234` does not, and is rejected rather than rounded to 12.3%.
  ///
  /// > **Rounding a calibration constant is forbidden.** A tolerance band
  /// > silently widened by rounding accepts the very error it exists to catch,
  /// > and it does so invisibly — the pack would still read `0.1234` while the
  /// > engine used something else.
  static int _percentTenths(JsonView v) {
    final JsonView field = v.required('relativeFraction');
    final num fraction = field.asNum;
    if (fraction < 0) {
      field.reject(
        RulePackFailureKind.schemaViolation,
        'A relative band cannot be negative.',
      );
    }
    final double scaled = fraction.toDouble() * _tenthsPerUnitFraction;
    if (!scaled.isFinite || scaled != scaled.roundToDouble()) {
      field.reject(
        RulePackFailureKind.unrepresentableValue,
        'Expected a fraction expressible in tenths of a percent; $fraction is '
        'not. Use a value such as 0.05, 0.1 or 0.15.',
      );
    }
    return scaled.round();
  }

  /// Decodes the `APPROXIMATELY` widths, keyed by unit.
  ///
  /// Both diagnostics below echo the pack's **own spelling** rather than the
  /// Dart enum name. `RulePackFailure.detail` is specified to speak "the
  /// vocabulary of the schema — which is the vocabulary of whoever must fix the
  /// pack": a message saying `millilitre` where the file says `MILLILITRE`
  /// sends a contributor hunting for a line that is not there.
  static ApproximationDeltas _deltas(JsonView deltas) {
    final Map<Unit, int> byUnit = <Unit, int>{};
    for (final JsonView v in deltas.elements) {
      final JsonView unitField = v.required('unit');
      final String printedUnit = unitField.asString;
      final Unit unit = unitField.asEnum(Primitives.units);
      if (byUnit.containsKey(unit)) {
        v.reject(
          RulePackFailureKind.duplicateKey,
          'Two approximation deltas for $printedUnit.',
        );
      }
      final JsonView deltaField = v.required('delta');
      final Quantity delta = Primitives.quantity(deltaField);
      if (delta.unit != unit) {
        // A delta for grams stated in millilitres is a curation error whose
        // effect would be a band three orders of magnitude wrong.
        deltaField.reject(
          RulePackFailureKind.schemaViolation,
          'Delta for $printedUnit is stated in '
          '${deltaField.required('unit').asString}.',
        );
      }
      byUnit[unit] = Primitives.toBaseUnits(delta);
    }
    return ApproximationDeltas(byUnit);
  }
}
