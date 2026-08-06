import 'package:lw_domain/src/invariants/invariant_id.dart';
import 'package:lw_domain/src/invariants/invariant_result.dart';
import 'package:lw_domain/src/invariants/tolerance.dart';
import 'package:lw_domain/src/label/approximation_deltas.dart';
import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/interval.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/qualifier.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/label/rounding.dart';
import 'package:lw_domain/src/label/serving_facts.dart';
import 'package:lw_domain/src/label/trilean.dart';
import 'package:lw_domain/src/label/unit.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/parser/typed_fields.dart';
import 'package:lw_domain/src/parser/validated_fields.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';

/// Micro-joules per microgram of protein or carbohydrate, ×1000.
///
/// 4 kcal/g × 4 184 000 mJ/kcal ÷ 1 000 000 µg/g = 16.736 mJ/µg. Held as
/// micro-joules so the Atwater estimate is **exact integer arithmetic** with
/// no intermediate rounding — the single rounding happens once, when the
/// finished estimate is expressed in millijoules.
const int _microJoulesPerMicrogramProtein = 16736;

/// As [_microJoulesPerMicrogramProtein], for fat at 9 kcal/g.
const int _microJoulesPerMicrogramFat = 37656;

/// **S7 — Invariant evaluation.** The arithmetic that catches a misread digit.
///
/// Evaluates INV-01…10 over the typed values and records, for each, whether it
/// passed, failed, could not be settled, or did not apply (FR-CNF-04). This is
/// confidence signal **S3**, and per ADR-0010 it is the *primary* one: an OCR
/// engine that is confidently wrong about a `3` it read as an `8` reports high
/// character confidence, and only the arithmetic catches it.
///
/// **Values are never modified.** A value that fails an invariant is still the
/// value the label declared. Correcting it would replace the manufacturer's
/// claim with our guess, which P1 forbids.
///
/// **Comparison is over intervals, not points** (ADR-0027, FR-CNF-14).
/// `saturatedFat = LESS_THAN 0.5 g` against `totalFat = EXACT 0.4 g` cannot be
/// settled, and reports `INDETERMINATE` rather than being forced to a verdict.
/// A tolerance widens the comparison; it does not replace the interval
/// (`DATA_MODEL.md` §4.3a). The two compose.
///
/// **Basis-scoped invariants are evaluated once per basis present** among the
/// typed fields (`DATA_MODEL.md` §4.3, v1.5). A panel declaring per-100 g and
/// per-serve columns yields one INV-02 result for each, so that a per-serve
/// failure caps only per-serve fields under FR-CNF-05. Bases with no declared
/// field produce no results — there was no column to check, which is different
/// from a column that could not be checked.
///
/// INV-09 and INV-10 are evaluated once, with no basis, because a serving
/// count reconciling against net quantity is a fact about the pack.
///
/// Pure and total: no I/O, no clock, no randomness (FR-PAR-01), and every
/// input yields a `StageResult` rather than an exception (FR-PAR-17). An
/// approximate quantity whose rule pack delta is missing yields
/// `INDETERMINATE` rather than throwing.
///
/// [serving], [tolerances] and [deltas] are additive optional parameters;
/// omitting all three is a valid call.
StageResult<ValidatedFields> evaluateInvariants(
  TypedFields typed, {
  ServingFacts? serving,
  ToleranceTable? tolerances,
  ApproximationDeltas? deltas,
}) {
  if (!typed.nutritionPanelPresent && !typed.ingredientListPresent) {
    return const StageFailure<ValidatedFields>(
      ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        stage: PipelineStage.invariantEvaluation,
      ),
    );
  }

  final _Context context = _Context(
    typed: typed,
    serving: serving ?? ServingFacts.none,
    tolerances: tolerances ?? ToleranceTable.defaults,
    deltas: deltas ?? ApproximationDeltas.none,
  );

  final List<InvariantResult> results = <InvariantResult>[];
  // Basis.values order, then InvariantId order: the output cannot depend on
  // the order fields happened to arrive in (FR-PAR-02).
  for (final Basis basis in Basis.values) {
    if (!context.hasAnyFieldOn(basis)) {
      continue;
    }
    for (final InvariantId id in InvariantId.values) {
      if (!id.basisScoped) {
        continue;
      }
      // INV-08 asks whether the *per-serve* column reconciles with per-100 g.
      // Scoping that question to the per-100 g column is a category error, and
      // emitting an INAPPLICABLE result there would report "we could not check
      // this" when the serving information was present all along. INV-06 is
      // deliberately different: TEST_STRATEGY 12.3 requires it to *report*
      // INAPPLICABLE on a volume basis, so it is evaluated on every basis.
      if (id == InvariantId.inv08 && basis != Basis.perServe) {
        continue;
      }
      results.add(context.evaluateScoped(id, basis));
    }
  }
  results.add(context.evaluateServingSizeWithinPack());
  results.add(context.evaluateServingCount());

  return StageSuccess<ValidatedFields>(
    ValidatedFields(
      fields: typed.fields,
      results: results,
      unresolved: typed.unresolved,
      ingredientTokens: typed.ingredientTokens,
      serving: context.serving,
      nutritionPanelPresent: typed.nutritionPanelPresent,
      ingredientListPresent: typed.ingredientListPresent,
    ),
  );
}

/// Everything one evaluation needs, gathered once so no stage state leaks.
final class _Context {
  _Context({
    required this.typed,
    required this.serving,
    required this.tolerances,
    required this.deltas,
  });

  final TypedFields typed;
  final ServingFacts serving;
  final ToleranceTable tolerances;
  final ApproximationDeltas deltas;

  bool hasAnyFieldOn(Basis basis) =>
      typed.fields.any((TypedField f) => f.basis == basis);

  TypedField? fieldFor(NutrientId nutrient, Basis basis) {
    for (final TypedField f in typed.fields) {
      if (f.nutrient == nutrient && f.basis == basis) {
        return f;
      }
    }
    return null;
  }

  Tolerance? bandFor(InvariantId id) => tolerances.forInvariant(id);

  InvariantResult evaluateScoped(InvariantId id, Basis basis) => switch (id) {
        InvariantId.inv01 => _nonNegative(basis),
        InvariantId.inv02 =>
          _atMost(id, basis, NutrientId.saturatedFat, NutrientId.totalFat),
        InvariantId.inv03 =>
          _atMost(id, basis, NutrientId.transFat, NutrientId.totalFat),
        InvariantId.inv04 =>
          _atMost(id, basis, NutrientId.addedSugars, NutrientId.totalSugars),
        InvariantId.inv05 =>
          _atMost(id, basis, NutrientId.totalSugars, NutrientId.carbohydrate),
        InvariantId.inv06 => _macronutrientSum(basis),
        InvariantId.inv07 => _atwater(basis),
        InvariantId.inv08 => _perServeReconciles(basis),
        InvariantId.inv09 || InvariantId.inv10 => _inapplicable(
            id,
            null,
            const <InvariantSubject>[
              ServingSubject(ServingField.servingSize),
            ],
          ),
      };

  // ------------------------------------------------------------- INV-01

  /// Every declared value on this basis is at least zero.
  ///
  /// Aggregated into one result per basis rather than one per field: a
  /// negative declaration is a property of the column, and a per-field result
  /// would need a second discriminator the data model does not carry. When it
  /// fails, only the offending fields are named, so FR-CNF-05 caps precisely.
  InvariantResult _nonNegative(Basis basis) {
    final List<TypedField> present = typed.fields
        .where((TypedField f) => f.basis == basis)
        .toList(growable: false);
    if (present.isEmpty) {
      return _inapplicable(InvariantId.inv01, basis,
          const <InvariantSubject>[NutrientSubject(NutrientId.energy)]);
    }

    final List<InvariantSubject> offenders = <InvariantSubject>[];
    bool anyIndeterminate = false;
    int worst = 0;
    for (final TypedField f in present) {
      final Interval? bounds = _boundsOf(f.quantity);
      if (bounds == null) {
        anyIndeterminate = true;
        continue;
      }
      final Trilean verdict = const Interval.point(0).isAtMost(bounds);
      if (verdict == Trilean.definitelyFalse) {
        offenders.add(NutrientSubject(f.nutrient));
        if (bounds.infimum < worst) {
          worst = bounds.infimum;
        }
      } else if (verdict == Trilean.indeterminate) {
        anyIndeterminate = true;
      }
    }

    if (offenders.isNotEmpty) {
      return InvariantResult(
        invariantId: InvariantId.inv01,
        outcome: InvariantOutcome.failed,
        basis: basis,
        participatingFields: offenders,
        observedDeviation: _asQuantity(worst.abs(), Unit.gram),
        toleranceApplied: bandFor(InvariantId.inv01),
      );
    }
    return InvariantResult(
      invariantId: InvariantId.inv01,
      outcome: anyIndeterminate
          ? InvariantOutcome.indeterminate
          : InvariantOutcome.passed,
      basis: basis,
      participatingFields: <InvariantSubject>[
        for (final TypedField f in present) NutrientSubject(f.nutrient),
      ],
      toleranceApplied: bandFor(InvariantId.inv01),
    );
  }

  // ------------------------------------------------- INV-02 to INV-05

  /// `lesser ≤ greater`, within the invariant's grace.
  InvariantResult _atMost(
    InvariantId id,
    Basis basis,
    NutrientId lesser,
    NutrientId greater,
  ) {
    final List<InvariantSubject> subjects = <InvariantSubject>[
      NutrientSubject(lesser),
      NutrientSubject(greater),
    ];
    final TypedField? small = fieldFor(lesser, basis);
    final TypedField? large = fieldFor(greater, basis);
    if (small == null || large == null) {
      return _inapplicable(id, basis, subjects);
    }
    final Interval? smallBounds = _boundsOf(small.quantity);
    final Interval? largeBounds = _boundsOf(large.quantity);
    if (smallBounds == null || largeBounds == null) {
      return _indeterminate(id, basis, subjects);
    }

    final Tolerance? band = bandFor(id);
    final int allowance =
        band?.allowanceFor(largeBounds.supremum ?? largeBounds.infimum) ?? 0;
    final Trilean verdict =
        smallBounds.isAtMost(_shiftUp(largeBounds, allowance));

    return _fromTrilean(
      id: id,
      basis: basis,
      subjects: subjects,
      verdict: verdict,
      band: band,
      deviation: () => _asQuantity(
        _overshoot(smallBounds, largeBounds, allowance),
        Unit.gram,
      ),
    );
  }

  // ------------------------------------------------------------- INV-06

  /// `protein + carbohydrate + totalFat ≤ 100 g per 100 g`.
  ///
  /// Applies only to a per-100 g column. On a per-100 ml basis the check is
  /// meaningless — 100 ml of a liquid is not 100 g of it — and reporting
  /// `INAPPLICABLE` there is what `TEST_STRATEGY.md` §12.3 requires of the
  /// beverage dry run.
  InvariantResult _macronutrientSum(Basis basis) {
    const List<InvariantSubject> subjects = <InvariantSubject>[
      NutrientSubject(NutrientId.protein),
      NutrientSubject(NutrientId.carbohydrate),
      NutrientSubject(NutrientId.totalFat),
    ];
    if (basis != Basis.per100g) {
      return _inapplicable(InvariantId.inv06, basis, subjects);
    }
    final Interval? sum = _macronutrientInterval(basis);
    if (sum == null) {
      return _missingOrUnbounded(InvariantId.inv06, basis, subjects);
    }

    const int hundredGrams = 100 * 1000000;
    final Tolerance? band = bandFor(InvariantId.inv06);
    final int allowance = band?.allowanceFor(hundredGrams) ?? 0;
    final Trilean verdict =
        sum.isAtMost(Interval.point(hundredGrams + allowance));

    return _fromTrilean(
      id: InvariantId.inv06,
      basis: basis,
      subjects: subjects,
      verdict: verdict,
      band: band,
      deviation: () => _asQuantity(
        (sum.infimum - hundredGrams - allowance).abs(),
        Unit.gram,
      ),
    );
  }

  // ------------------------------------------------------------- INV-07

  /// Declared energy reconciles with the Atwater estimate.
  ///
  /// `4·protein + 4·carbohydrate + 9·fat`, computed exactly in micro-joules
  /// and expressed in millijoules with a single outward rounding, so the
  /// estimate interval never narrows and can never manufacture a definite
  /// verdict the arithmetic did not support.
  InvariantResult _atwater(Basis basis) {
    const List<InvariantSubject> subjects = <InvariantSubject>[
      NutrientSubject(NutrientId.energy),
      NutrientSubject(NutrientId.protein),
      NutrientSubject(NutrientId.carbohydrate),
      NutrientSubject(NutrientId.totalFat),
    ];
    final TypedField? energy = fieldFor(NutrientId.energy, basis);
    if (energy == null) {
      return _inapplicable(InvariantId.inv07, basis, subjects);
    }
    final Interval? declared = _boundsOf(energy.quantity);
    final Interval? estimate = _atwaterInterval(basis);
    if (declared == null || estimate == null) {
      return _missingOrUnbounded(InvariantId.inv07, basis, subjects);
    }

    final int reference = estimate.supremum ?? estimate.infimum;
    final Tolerance? band = bandFor(InvariantId.inv07);
    final int allowance = band?.allowanceFor(reference) ?? 0;
    final Interval permitted = Interval(
      infimum: estimate.infimum - allowance,
      infimumInclusive: true,
      supremum: (estimate.supremum ?? estimate.infimum) + allowance,
      supremumInclusive: true,
    );
    final Trilean verdict = _within(declared, permitted);

    return _fromTrilean(
      id: InvariantId.inv07,
      basis: basis,
      subjects: subjects,
      verdict: verdict,
      band: band,
      deviation: () =>
          _asQuantity(_distanceOutside(declared, permitted), Unit.kilocalorie),
    );
  }

  // ------------------------------------------------------------- INV-08

  /// The per-serve column reconciles with per-100 g scaled by the serve size.
  ///
  /// Aggregated across every nutrient declared on both bases, for the same
  /// reason INV-01 is: the data model carries one basis per result, not one
  /// nutrient. When it fails, only the nutrients that failed are named.
  InvariantResult _perServeReconciles(Basis basis) {
    const List<InvariantSubject> fallback = <InvariantSubject>[
      ServingSubject(ServingField.servingSize),
    ];
    // Only ever called for Basis.perServe — the caller guards it — so the
    // one thing that can be missing here is the declared serve size.
    final Quantity? serveSize = serving.servingSize;
    if (serveSize == null) {
      return _inapplicable(InvariantId.inv08, basis, fallback);
    }
    final Interval? serveBounds = _boundsOf(serveSize);
    if (serveBounds == null) {
      return _indeterminate(InvariantId.inv08, basis, fallback);
    }

    final Tolerance? band = bandFor(InvariantId.inv08);
    final List<InvariantSubject> checked = <InvariantSubject>[
      const ServingSubject(ServingField.servingSize),
    ];
    final List<InvariantSubject> offenders = <InvariantSubject>[
      const ServingSubject(ServingField.servingSize),
    ];
    bool anyIndeterminate = false;
    bool anyChecked = false;
    int worst = 0;

    for (final TypedField perServe in typed.fields) {
      if (perServe.basis != Basis.perServe) {
        continue;
      }
      final TypedField? perHundred = fieldFor(perServe.nutrient, Basis.per100g);
      if (perHundred == null) {
        continue;
      }
      final Interval? declared = _boundsOf(perServe.quantity);
      final Interval? hundred = _boundsOf(perHundred.quantity);
      if (declared == null || hundred == null) {
        anyIndeterminate = true;
        continue;
      }
      anyChecked = true;
      checked.add(NutrientSubject(perServe.nutrient));

      final Interval? expected = _scaleByServe(hundred, serveBounds);
      if (expected == null) {
        anyIndeterminate = true;
        continue;
      }
      // The floor is one increment of the declared unit: the last decimal
      // place the label actually printed is no longer available once the
      // value is typed, and the tracked precision is the closest honest
      // reading of DATA_MODEL 4.4's "one unit of the last declared decimal".
      final int floor = perServe.quantity.unit.baseUnitsPerIncrement;
      final int reference = expected.supremum ?? expected.infimum;
      final int relative = band?.allowanceFor(reference) ?? 0;
      final int allowance = relative > floor ? relative : floor;
      final Interval permitted = Interval(
        infimum: expected.infimum - allowance,
        infimumInclusive: true,
        supremum: (expected.supremum ?? expected.infimum) + allowance,
        supremumInclusive: true,
      );
      final Trilean verdict = _within(declared, permitted);
      if (verdict == Trilean.definitelyFalse) {
        offenders.add(NutrientSubject(perServe.nutrient));
        final int out = _distanceOutside(declared, permitted);
        if (out > worst) {
          worst = out;
        }
      } else if (verdict == Trilean.indeterminate) {
        anyIndeterminate = true;
      }
    }

    if (offenders.length > 1) {
      return InvariantResult(
        invariantId: InvariantId.inv08,
        outcome: InvariantOutcome.failed,
        basis: basis,
        participatingFields: offenders,
        observedDeviation: _asQuantity(worst, Unit.gram),
        toleranceApplied: band,
      );
    }
    if (!anyChecked && !anyIndeterminate) {
      return _inapplicable(InvariantId.inv08, basis, fallback);
    }
    return InvariantResult(
      invariantId: InvariantId.inv08,
      outcome: anyIndeterminate
          ? InvariantOutcome.indeterminate
          : InvariantOutcome.passed,
      basis: basis,
      participatingFields: checked,
      toleranceApplied: band,
    );
  }

  // ------------------------------------------------------------- INV-09

  /// `servingSize ≤ netQuantity`. Exact — a serve larger than the pack is
  /// never a rounding artefact.
  InvariantResult evaluateServingSizeWithinPack() {
    const List<InvariantSubject> subjects = <InvariantSubject>[
      ServingSubject(ServingField.servingSize),
      ServingSubject(ServingField.netQuantity),
    ];
    final Quantity? serve = serving.servingSize;
    final Quantity? net = serving.netQuantity;
    if (serve == null || net == null) {
      return _inapplicable(InvariantId.inv09, null, subjects);
    }
    if (!serve.unit.isConvertibleTo(net.unit)) {
      // A serve in grams against a pack in millilitres cannot be compared.
      // Declining is honest; converting would invent a density.
      return _inapplicable(InvariantId.inv09, null, subjects);
    }
    final Interval? serveBounds = _boundsOf(serve);
    final Interval? netBounds = _boundsOf(net);
    if (serveBounds == null || netBounds == null) {
      return _indeterminate(InvariantId.inv09, null, subjects);
    }

    return _fromTrilean(
      id: InvariantId.inv09,
      basis: null,
      subjects: subjects,
      verdict: serveBounds.isAtMost(netBounds),
      band: bandFor(InvariantId.inv09),
      deviation: () =>
          _asQuantity(_overshoot(serveBounds, netBounds, 0), serve.unit),
    );
  }

  // ------------------------------------------------------------- INV-10

  /// `servingsPerPack ≈ netQuantity ÷ servingSize`.
  InvariantResult evaluateServingCount() {
    const List<InvariantSubject> subjects = <InvariantSubject>[
      ServingSubject(ServingField.servingsPerPack),
      ServingSubject(ServingField.netQuantity),
      ServingSubject(ServingField.servingSize),
    ];
    final Quantity? count = serving.servingsPerPack;
    final Quantity? serve = serving.servingSize;
    final Quantity? net = serving.netQuantity;
    if (count == null || serve == null || net == null) {
      return _inapplicable(InvariantId.inv10, null, subjects);
    }
    if (!serve.unit.isConvertibleTo(net.unit)) {
      return _inapplicable(InvariantId.inv10, null, subjects);
    }
    final Interval? countBounds = _boundsOf(count);
    final Interval? serveBounds = _boundsOf(serve);
    final Interval? netBounds = _boundsOf(net);
    if (countBounds == null || serveBounds == null || netBounds == null) {
      return _indeterminate(InvariantId.inv10, null, subjects);
    }
    final Interval? expected = _divideOut(netBounds, serveBounds);
    if (expected == null) {
      return _indeterminate(InvariantId.inv10, null, subjects);
    }

    final Tolerance? band = bandFor(InvariantId.inv10);
    final int allowance =
        band?.allowanceFor(expected.supremum ?? expected.infimum) ?? 0;
    final Interval permitted = Interval(
      infimum: expected.infimum - allowance,
      infimumInclusive: true,
      supremum: (expected.supremum ?? expected.infimum) + allowance,
      supremumInclusive: true,
    );

    return _fromTrilean(
      id: InvariantId.inv10,
      basis: null,
      subjects: subjects,
      verdict: _within(countBounds, permitted),
      band: band,
      deviation: () =>
          _asQuantity(_distanceOutside(countBounds, permitted), Unit.count),
    );
  }

  // ------------------------------------------------------------- helpers

  /// The interval a quantity denotes, or null when it cannot be bounded.
  ///
  /// Null only for an `APPROXIMATELY` value whose rule pack delta is missing.
  /// `ApproximationDeltas.deltaFor` throws in that case, and S7 must be total
  /// (FR-PAR-17), so the guard is checked rather than the throw caught.
  Interval? _boundsOf(Quantity q) {
    if (q.qualifier == Qualifier.approximately && !deltas.hasDeltaFor(q.unit)) {
      return null;
    }
    return q.boundsIn(deltas);
  }

  /// The macronutrient sum on [basis], in micrograms.
  Interval? _macronutrientInterval(Basis basis) {
    Interval? total;
    for (final NutrientId id in const <NutrientId>[
      NutrientId.protein,
      NutrientId.carbohydrate,
      NutrientId.totalFat,
    ]) {
      final TypedField? f = fieldFor(id, basis);
      if (f == null) {
        return null;
      }
      final Interval? bounds = _boundsOf(f.quantity);
      if (bounds == null) {
        return null;
      }
      total = total == null ? bounds : _add(total, bounds);
    }
    return total;
  }

  /// The Atwater estimate on [basis], in millijoules.
  Interval? _atwaterInterval(Basis basis) {
    int infimum = 0;
    int? supremum = 0;
    for (final MapEntry<NutrientId, int> term in <NutrientId, int>{
      NutrientId.protein: _microJoulesPerMicrogramProtein,
      NutrientId.carbohydrate: _microJoulesPerMicrogramProtein,
      NutrientId.totalFat: _microJoulesPerMicrogramFat,
    }.entries) {
      final TypedField? f = fieldFor(term.key, basis);
      if (f == null) {
        return null;
      }
      final Interval? bounds = _boundsOf(f.quantity);
      if (bounds == null) {
        return null;
      }
      infimum += bounds.infimum * term.value;
      final int? top = bounds.supremum;
      supremum = (supremum == null || top == null)
          ? null
          : supremum + top * term.value;
    }
    // Outward rounding, so the estimate never narrows.
    return Interval(
      infimum: infimum ~/ 1000,
      infimumInclusive: true,
      supremum: supremum == null ? null : (supremum + 999) ~/ 1000,
      supremumInclusive: true,
    );
  }

  /// Per-100 g scaled to the declared serve, rounded outward.
  Interval? _scaleByServe(Interval perHundred, Interval serve) {
    final int? serveTop = serve.supremum;
    if (serve.infimum <= 0 || serveTop == null) {
      return null;
    }
    const int hundredGrams = 100 * 1000000;
    final int? top = perHundred.supremum;
    return Interval(
      infimum: perHundred.infimum * serve.infimum ~/ hundredGrams,
      infimumInclusive: true,
      supremum: top == null
          ? null
          : (top * serveTop + hundredGrams - 1) ~/ hundredGrams,
      supremumInclusive: true,
    );
  }

  /// `numerator ÷ denominator`, expressed in count increments, rounded
  /// outward so a definite verdict is never manufactured by rounding.
  Interval? _divideOut(Interval numerator, Interval denominator) {
    final int? denTop = denominator.supremum;
    if (denominator.infimum <= 0 || denTop == null) {
      return null;
    }
    final int? numTop = numerator.supremum;
    return Interval(
      infimum: numerator.infimum * 100 ~/ denTop,
      infimumInclusive: true,
      supremum: numTop == null
          ? null
          : (numTop * 100 + denominator.infimum - 1) ~/ denominator.infimum,
      supremumInclusive: true,
    );
  }

  InvariantResult _fromTrilean({
    required InvariantId id,
    required Basis? basis,
    required List<InvariantSubject> subjects,
    required Trilean verdict,
    required Tolerance? band,
    required Quantity Function() deviation,
  }) =>
      InvariantResult(
        invariantId: id,
        outcome: switch (verdict) {
          Trilean.definitelyTrue => InvariantOutcome.passed,
          Trilean.definitelyFalse => InvariantOutcome.failed,
          Trilean.indeterminate => InvariantOutcome.indeterminate,
        },
        basis: basis,
        participatingFields: subjects,
        observedDeviation:
            verdict == Trilean.definitelyFalse ? deviation() : null,
        toleranceApplied: band,
      );

  InvariantResult _inapplicable(
    InvariantId id,
    Basis? basis,
    List<InvariantSubject> subjects,
  ) =>
      InvariantResult(
        invariantId: id,
        outcome: InvariantOutcome.inapplicable,
        basis: basis,
        participatingFields: subjects,
      );

  InvariantResult _indeterminate(
    InvariantId id,
    Basis? basis,
    List<InvariantSubject> subjects,
  ) =>
      InvariantResult(
        invariantId: id,
        outcome: InvariantOutcome.indeterminate,
        basis: basis,
        participatingFields: subjects,
        toleranceApplied: bandFor(id),
      );

  /// A missing participant is `INAPPLICABLE`; an unbounded one is
  /// `INDETERMINATE`. The two are distinguished by re-checking presence.
  InvariantResult _missingOrUnbounded(
    InvariantId id,
    Basis basis,
    List<InvariantSubject> subjects,
  ) {
    for (final InvariantSubject s in subjects) {
      if (s is NutrientSubject && fieldFor(s.nutrient, basis) == null) {
        return _inapplicable(id, basis, subjects);
      }
    }
    return _indeterminate(id, basis, subjects);
  }
}

Interval _add(Interval a, Interval b) {
  final int? aTop = a.supremum;
  final int? bTop = b.supremum;
  return Interval(
    infimum: a.infimum + b.infimum,
    infimumInclusive: a.infimumInclusive && b.infimumInclusive,
    supremum: (aTop == null || bTop == null) ? null : aTop + bTop,
    supremumInclusive: a.supremumInclusive && b.supremumInclusive,
  );
}

/// The interval shifted up by [by], both bounds together.
///
/// `saturated ≤ total + grace` compares against a *shifted* declaration, not a
/// widened one. Widening only the upper bound would leave the lower bound
/// where it was, and `sup(small) ≤ inf(large)` — the condition for a definite
/// pass — would then never hold for two point declarations that differ only by
/// the manufacturer's rounding. That is precisely the case the grace exists
/// to absorb.
Interval _shiftUp(Interval i, int by) {
  if (by == 0) {
    return i;
  }
  final int? top = i.supremum;
  return Interval(
    infimum: i.infimum + by,
    infimumInclusive: i.infimumInclusive,
    supremum: top == null ? null : top + by,
    supremumInclusive: i.supremumInclusive,
  );
}

/// Whether [value] lies wholly inside [permitted].
///
/// Containment, not a pair of orderings. Expressed through `isAtMost` it would
/// require every value of one interval to be at most every value of the other
/// in both directions, which two identical non-degenerate intervals can never
/// satisfy — a band that exactly matches the declaration would report
/// `INDETERMINATE` when it plainly holds.
Trilean _within(Interval value, Interval permitted) {
  final int? valueTop = value.supremum;
  final int? permittedTop = permitted.supremum;

  final bool aboveFloor = value.infimum >= permitted.infimum;
  final bool belowCeiling =
      permittedTop == null || (valueTop != null && valueTop <= permittedTop);
  if (aboveFloor && belowCeiling) {
    return Trilean.definitelyTrue;
  }

  // Definitely outside only when the intervals do not meet at all. Anything
  // else overlaps, and an overlap does not settle the question (ADR-0027).
  if (permittedTop != null && value.infimum > permittedTop) {
    return Trilean.definitelyFalse;
  }
  if (valueTop != null && valueTop < permitted.infimum) {
    return Trilean.definitelyFalse;
  }
  return Trilean.indeterminate;
}

int _overshoot(Interval small, Interval large, int allowance) {
  final int ceiling = (large.supremum ?? large.infimum) + allowance;
  final int over = small.infimum - ceiling;
  return over > 0 ? over : 0;
}

int _distanceOutside(Interval value, Interval permitted) {
  final int? top = permitted.supremum;
  if (top != null && value.infimum > top) {
    return value.infimum - top;
  }
  final int? valueTop = value.supremum;
  if (valueTop != null && valueTop < permitted.infimum) {
    return permitted.infimum - valueTop;
  }
  return 0;
}

Quantity _asQuantity(int baseUnits, Unit unit) => Quantity.exact(
      divideRounded(baseUnits, unit.baseUnitsPerIncrement),
      unit,
    );
