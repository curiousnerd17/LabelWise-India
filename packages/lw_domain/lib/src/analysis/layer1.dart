import 'package:lw_domain/src/analysis/derivation.dart';
import 'package:lw_domain/src/analysis/factual_finding.dart';
import 'package:lw_domain/src/analysis/factual_value.dart';
import 'package:lw_domain/src/analysis/finding_subject.dart';
import 'package:lw_domain/src/analysis/layer1_result.dart';
import 'package:lw_domain/src/analysis/serving_reconciliation_result.dart';
import 'package:lw_domain/src/confidence/confidence.dart';
import 'package:lw_domain/src/invariants/invariant_id.dart';
import 'package:lw_domain/src/invariants/invariant_result.dart';
import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/checked_arithmetic.dart';
import 'package:lw_domain/src/label/field_state.dart';
import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/parsed_label.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/label/rounding.dart';
import 'package:lw_domain/src/label/serving_facts.dart';
import 'package:lw_domain/src/label/unit.dart';
import 'package:lw_domain/src/provenance/provenance.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';
import 'package:lw_domain/src/rulepack/pack_ids.dart';
import 'package:lw_domain/src/rulepack/rda_table.dart';
import 'package:lw_domain/src/rulepack/source.dart';
import 'package:lw_domain/src/version.dart';

/// The rules Layer 1 applies, named so every derived value can cite one.
abstract final class _L1Rules {
  static final RuleId normaliseTo100 = RuleId('rule.l1.normalise-to-100');
  static final RuleId scaleToPack = RuleId('rule.l1.scale-to-pack');
  static final RuleId rdaPercent = RuleId('rule.l1.rda-percent');
  static final RuleId servingReconciliation =
      RuleId('rule.l1.serving-reconciliation');
}

/// The catalogue entries Layer 1 names. Identifiers only — the domain never
/// holds display text (FR-LOC-01, M5).
abstract final class _L1Messages {
  static final MessageId normalisation = MessageId('msg.l1.normalisation');
  static final MessageId wholePack = MessageId('msg.l1.whole-pack');
  static final MessageId rdaContribution = MessageId('msg.l1.rda-contribution');
  static final MessageId rdaNoDenominator =
      MessageId('msg.l1.rda-no-denominator');
  static final MessageId servingReconciliation =
      MessageId('msg.l1.serving-reconciliation');
  static final MessageId notComputable = MessageId('msg.l1.not-computable');
}

/// One hundred grams, in base units. The reference every per-100 declaration
/// is expressed against.
const int _hundredGramsBase = 100 * 1000000;

/// **Layer 1 — factual analysis.**
///
/// Restates what the label declares and computes what follows arithmetically
/// from it. **It contains no judgement** (FR-L1-01, P5): there is no field in
/// a `FactualFinding` where "high in sodium" could be stored, which is what
/// makes the constraint structural rather than a matter of wording.
///
/// Pure, total and deterministic: the only inputs are [label], [rda] and
/// [sources], so identical arguments produce identical output on every run.
/// No clock, no randomness, no I/O, and [label] is never mutated.
///
/// **It does not reconcile the serving figures itself.** S7 already evaluated
/// INV-09 and INV-10 against the rule pack's tolerances during parsing, and
/// those verdicts travel on `ParsedLabel.invariantResults`. Recomputing them
/// here would need a tolerance this function is not given, and two
/// implementations of one comparison eventually disagree. Layer 1 reads the
/// answer and presents the figures side by side (FR-L1-05).
///
/// [rda] is the sole source of daily values: no denominator is written into
/// this file, so a rule pack revision changes the arithmetic without a code
/// change (FR-L1-04, ADR-0012).
Layer1Result analyseFactually(
  ParsedLabel label, {
  required RdaTable rda,
  required SourceRegistry sources,
}) {
  final Version version = label.rulePackVersion;
  final List<FactualFinding> findings = <FactualFinding>[];
  final List<NutrientField> wholePack = <NutrientField>[];

  // `ParsedLabel.nutrients` is already ordered deterministically, and the
  // findings follow that order (FR-PAR-02).
  for (final NutrientField field in label.nutrients) {
    final _Declared? declared = _declaredValue(field);
    if (declared == null) {
      // Nothing usable was declared. There is no value to restate and none to
      // invent (FR-L1-09).
      continue;
    }

    findings.add(_normalisation(field.nutrient, declared, version));

    final FactualFinding? packFinding =
        _wholePack(field.nutrient, declared, label.servingInfo, version);
    if (packFinding != null) {
      findings.add(packFinding);
      final FactualValue v = packFinding.value;
      if (v is ComputedFactualValue) {
        wholePack.add(NutrientField(
          nutrient: field.nutrient,
          perHundred: field.perHundred,
          perServe: field.perServe,
          perPack: v.field,
        ));
      }
    }

    findings.add(_rdaContribution(field.nutrient, declared, rda, version));
  }

  final ServingDiscrepancy discrepancy = _discrepancyFrom(label);
  final ServingReconciliationResult reconciliation =
      ServingReconciliationResult(
    declaredServe: label.servingInfo.declaredServingSize,
    servesPerPack: label.servingInfo.servingsPerPack,
    wholePackValues: wholePack,
    discrepancy: discrepancy,
  );
  findings.add(_reconciliationFinding(label.servingInfo, discrepancy, version));

  return Layer1Result(
    findings: findings,
    servingReconciliation: reconciliation,
  );
}

/// A usable declared value and the state it came from.
///
/// Holding the originating [state] matters: its `propagatedConfidence` is what
/// every derivation over it must meet with (FR-L1-08), and a `UserSuppliedField`
/// propagates differently from an `ExtractedField` (ARCHITECTURE §7.4).
final class _Declared {
  const _Declared(this.state, this.quantity, this.basis);

  final FieldState state;
  final Quantity quantity;
  final Basis basis;

  Confidence get confidence => state.propagatedConfidence;
}

/// The per-100 declaration for a nutrient, or null when there is none to use.
///
/// Reads `perHundred` only. A per-serve figure could be restated per 100 g
/// only by dividing by the declared serve, and this milestone does not perform
/// that conversion — attempting it where the serve is absent or unresolved
/// would be the inference FR-L1-09 forbids.
_Declared? _declaredValue(NutrientField field) {
  final FieldState state = field.perHundred;
  final Quantity? quantity = state.quantityOrNull;
  final Basis? basis = state.basisOrNull;
  if (quantity == null || basis == null) {
    // NotDeclared and Unresolved both land here, and both stay exactly what
    // they were — Layer 1 reinterprets neither (MI-08, FR-ERR-03).
    return null;
  }
  return _Declared(state, quantity, basis);
}

/// The value restated on its declared per-100 basis (FR-L1-02).
///
/// For a figure the label already declares per 100 g or 100 ml this is an
/// identity restatement, recorded as a derivation so the chain is unbroken.
/// No mass is converted to volume: that needs a density the label does not
/// declare, and assuming one would be invention.
FactualFinding _normalisation(
  NutrientId nutrient,
  _Declared declared,
  Version version,
) {
  final DerivationInput input = DerivationInput(
    field: FindingNutrient(nutrient),
    quantity: declared.quantity,
    basis: declared.basis,
    confidence: declared.confidence,
  );
  final Confidence confidence =
      Confidence.meetAll(<Confidence>[declared.confidence]);

  return FactualFinding(
    kind: FactualFindingKind.normalisation,
    subject: FindingNutrient(nutrient),
    value: ComputedFactualValue(DerivedField(
      quantity: declared.quantity,
      basis: declared.basis,
      provenance: Provenance.factual(
        parseRuleId: _L1Rules.normaliseTo100,
        rulePackVersion: version,
      ),
      confidence: confidence,
    )),
    confidence: confidence,
    messageId: _L1Messages.normalisation,
    derivation: Derivation(
      operation: DerivationOperation.normaliseTo100,
      inputs: <DerivationInput>[input],
      constantsUsed: const <ConstantUsed>[],
      result: declared.quantity,
    ),
  );
}

/// The whole-pack total, or null when the label supplies no net quantity.
///
/// `per-100 x net quantity / 100 g`, computed in base units so no intermediate
/// depends on a unit's tracked precision. Null — rather than a finding —
/// because a pack that declares no net quantity gives Layer 1 nothing to state
/// about its total.
FactualFinding? _wholePack(
  NutrientId nutrient,
  _Declared declared,
  ServingInfo serving,
  Version version,
) {
  final FieldState netState = serving.netQuantity;
  final Quantity? net = netState.quantityOrNull;
  if (net == null) {
    return null;
  }

  final Confidence confidence = Confidence.meetAll(<Confidence>[
    declared.confidence,
    netState.propagatedConfidence,
  ]);
  final List<DerivationInput> inputs = <DerivationInput>[
    DerivationInput(
      field: FindingNutrient(nutrient),
      quantity: declared.quantity,
      basis: declared.basis,
      confidence: declared.confidence,
    ),
    DerivationInput(
      field: const FindingServing(ServingField.netQuantity),
      quantity: net,
      basis: Basis.perPack,
      confidence: netState.propagatedConfidence,
    ),
  ];

  final Quantity? total = _scaleToPack(declared.quantity, net);
  if (total == null) {
    // The inputs were read; the arithmetic was declined. No number is
    // fabricated and no derivation is invented for a calculation that did not
    // complete (M11b).
    return FactualFinding(
      kind: FactualFindingKind.normalisation,
      subject: FindingNutrient(nutrient),
      value: const NotComputableFactualValue(),
      confidence: confidence,
      messageId: _L1Messages.notComputable,
    );
  }

  return FactualFinding(
    kind: FactualFindingKind.normalisation,
    subject: FindingNutrient(nutrient),
    value: ComputedFactualValue(DerivedField(
      quantity: total,
      basis: Basis.perPack,
      provenance: Provenance.factual(
        parseRuleId: _L1Rules.scaleToPack,
        rulePackVersion: version,
      ),
      confidence: confidence,
    )),
    confidence: confidence,
    messageId: _L1Messages.wholePack,
    derivation: Derivation(
      operation: DerivationOperation.scaleToPack,
      inputs: inputs,
      constantsUsed: const <ConstantUsed>[],
      result: total,
    ),
  );
}

/// `per100 x net / 100 g`, or null when it cannot be computed safely.
Quantity? _scaleToPack(Quantity per100, Quantity net) {
  final int? valueBase = per100.baseUnitsOrNull;
  final int? netBase = net.baseUnitsOrNull;
  if (valueBase == null || netBase == null || netBase <= 0) {
    return null;
  }
  // The product bound, not the storage bound: the intermediate is divided
  // straight back down, and refusing it at the storage bound would refuse
  // honest labels (BL-1).
  final int? product =
      checkedMultiply(valueBase, netBase, limit: maxSafeProduct);
  if (product == null) {
    return null;
  }
  final int totalBase = product ~/ _hundredGramsBase;
  if (!isSafeBaseUnitMagnitude(totalBase)) {
    return null;
  }
  final int scaled =
      divideRounded(totalBase, per100.unit.baseUnitsPerIncrement);
  return isSafeBaseUnitMagnitude(scaled)
      ? Quantity.qualified(scaled, per100.unit, per100.qualifier)
      : null;
}

/// The share of a gazetted daily value, or the statement that none exists.
///
/// The denominator comes from [rda] and nowhere else. When the pack gazettes
/// none the finding says so explicitly — not `NotDeclared`, which would blame
/// the label, and not `Unresolved`, which would blame the parser (MI-08).
FactualFinding _rdaContribution(
  NutrientId nutrient,
  _Declared declared,
  RdaTable rda,
  Version version,
) {
  final RdaDenominator? denominator = rda[nutrient];
  if (denominator == null) {
    return FactualFinding(
      kind: FactualFindingKind.rdaContribution,
      subject: FindingNutrient(nutrient),
      value: const NoDenominatorFactualValue(),
      confidence: declared.confidence,
      messageId: _L1Messages.rdaNoDenominator,
    );
  }

  final Confidence confidence =
      Confidence.meetAll(<Confidence>[declared.confidence]);
  final Quantity? percent = _rdaPercent(declared.quantity, denominator.value);
  if (percent == null) {
    return FactualFinding(
      kind: FactualFindingKind.rdaContribution,
      subject: FindingNutrient(nutrient),
      value: const NotComputableFactualValue(),
      confidence: confidence,
      messageId: _L1Messages.notComputable,
    );
  }

  return FactualFinding(
    kind: FactualFindingKind.rdaContribution,
    subject: FindingNutrient(nutrient),
    value: ComputedFactualValue(DerivedField(
      quantity: percent,
      basis: declared.basis,
      provenance: Provenance.factual(
        parseRuleId: _L1Rules.rdaPercent,
        rulePackVersion: version,
      ),
      confidence: confidence,
    )),
    confidence: confidence,
    messageId: _L1Messages.rdaContribution,
    derivation: Derivation(
      operation: DerivationOperation.rdaPercent,
      inputs: <DerivationInput>[
        DerivationInput(
          field: FindingNutrient(nutrient),
          quantity: declared.quantity,
          basis: declared.basis,
          confidence: declared.confidence,
        ),
      ],
      // What makes the percentage auditable: the constant is named, valued and
      // cited rather than materialising inside the arithmetic.
      constantsUsed: <ConstantUsed>[
        ConstantUsed(
          constantId: denominator.constantId,
          value: denominator.value,
          sourceRef: denominator.sourceRefs.first,
        ),
      ],
      result: percent,
    ),
  );
}

/// `value / denominator` as a percentage, or null when it cannot be computed.
Quantity? _rdaPercent(Quantity value, Quantity denominator) {
  if (!value.unit.isConvertibleTo(denominator.unit)) {
    // Comparing a mass against a volume would need a density nobody declared.
    return null;
  }
  final int? valueBase = value.baseUnitsOrNull;
  final int? denominatorBase = denominator.baseUnitsOrNull;
  if (valueBase == null || denominatorBase == null || denominatorBase <= 0) {
    return null;
  }
  // x100 for the percentage, then x the percent unit's own scale, so the
  // result is expressed in the increments Unit.percent tracks.
  final int? numerator = checkedMultiply(
    valueBase,
    100 * Unit.percent.scale,
    limit: maxSafeProduct,
  );
  if (numerator == null) {
    return null;
  }
  final int scaled = numerator ~/ denominatorBase;
  return isSafeBaseUnitMagnitude(scaled)
      ? Quantity.qualified(scaled, Unit.percent, value.qualifier)
      : null;
}

/// S7's verdict on the serving figures, translated into a factual state.
///
/// **Read, never recomputed.** INV-09 (`serve <= net`) and INV-10 (`net / serve`
/// against the declared count) were evaluated during parsing with the rule
/// pack's tolerances. Layer 1 is not given those tolerances, and inventing one
/// here would produce a second answer that can contradict the first.
ServingDiscrepancy _discrepancyFrom(ParsedLabel label) {
  final InvariantResult? inv09 = _resultFor(label, InvariantId.inv09);
  final InvariantResult? inv10 = _resultFor(label, InvariantId.inv10);

  // A serve larger than the pack is reported first: it is the stronger
  // statement, and exact rather than tolerance-bounded.
  if (inv09?.outcome == InvariantOutcome.failed) {
    return ServingDiscrepancy.serveExceedsPack;
  }
  if (inv10?.outcome == InvariantOutcome.failed) {
    return ServingDiscrepancy.servesInconsistent;
  }
  if (inv09?.outcome == InvariantOutcome.passed ||
      inv10?.outcome == InvariantOutcome.passed) {
    return ServingDiscrepancy.none;
  }
  // Indeterminate, inapplicable, or absent: the figures could not be
  // reconciled, and saying anything more would be invention.
  return ServingDiscrepancy.notComputable;
}

InvariantResult? _resultFor(ParsedLabel label, InvariantId id) {
  for (final InvariantResult r in label.invariantResults) {
    if (r.invariantId == id) {
      return r;
    }
  }
  return null;
}

/// The declared serving figures, restated side by side (FR-L1-05).
///
/// The finding and the `ServingReconciliationResult` are different things: the
/// object holds the four related figures, this states the outcome. Both are
/// available, and neither stands in for the other.
FactualFinding _reconciliationFinding(
  ServingInfo serving,
  ServingDiscrepancy discrepancy,
  Version version,
) {
  final FieldState serveState = serving.declaredServingSize;
  final FieldState countState = serving.servingsPerPack;
  final FieldState netState = serving.netQuantity;
  final Quantity? serve = serveState.quantityOrNull;
  final Quantity? count = countState.quantityOrNull;
  final Quantity? net = netState.quantityOrNull;

  final Confidence confidence = Confidence.meetAll(<Confidence>[
    serveState.propagatedConfidence,
    countState.propagatedConfidence,
    netState.propagatedConfidence,
  ]);

  if (discrepancy == ServingDiscrepancy.notComputable ||
      serve == null ||
      count == null ||
      net == null) {
    return FactualFinding(
      kind: FactualFindingKind.servingReconciliation,
      subject: const FindingServing(ServingField.servingSize),
      value: const NotComputableFactualValue(),
      confidence: confidence,
      messageId: _L1Messages.servingReconciliation,
    );
  }

  return FactualFinding(
    kind: FactualFindingKind.servingReconciliation,
    subject: const FindingServing(ServingField.servingSize),
    value: ComputedFactualValue(DerivedField(
      quantity: net,
      basis: Basis.perPack,
      provenance: Provenance.factual(
        parseRuleId: _L1Rules.servingReconciliation,
        rulePackVersion: version,
      ),
      confidence: confidence,
    )),
    confidence: confidence,
    messageId: _L1Messages.servingReconciliation,
    derivation: Derivation(
      operation: DerivationOperation.scaleToPack,
      inputs: <DerivationInput>[
        DerivationInput(
          field: const FindingServing(ServingField.servingSize),
          quantity: serve,
          basis: Basis.perServe,
          confidence: serveState.propagatedConfidence,
        ),
        DerivationInput(
          field: const FindingServing(ServingField.servingsPerPack),
          quantity: count,
          basis: Basis.perPack,
          confidence: countState.propagatedConfidence,
        ),
      ],
      constantsUsed: const <ConstantUsed>[],
      result: net,
    ),
  );
}
