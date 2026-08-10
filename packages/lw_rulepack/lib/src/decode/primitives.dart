import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/src/json_view.dart';

/// The schema's closed sets, mapped to the domain's.
///
/// **Every map here is the single point of truth for one enum crossing the
/// boundary.** The schema names them in SCREAMING_SNAKE and the domain in
/// lowerCamel; writing the correspondence once, as data, means a new member
/// added to either side shows up as one missing entry rather than as a silent
/// default somewhere downstream.
final class Primitives {
  const Primitives._();

  /// `nutrientId` — the closed, typed set (ADR-0014).
  static const Map<String, NutrientId> nutrients = <String, NutrientId>{
    'ENERGY': NutrientId.energy,
    'PROTEIN': NutrientId.protein,
    'CARBOHYDRATE': NutrientId.carbohydrate,
    'TOTAL_SUGARS': NutrientId.totalSugars,
    'ADDED_SUGARS': NutrientId.addedSugars,
    'DIETARY_FIBRE': NutrientId.dietaryFibre,
    'TOTAL_FAT': NutrientId.totalFat,
    'SATURATED_FAT': NutrientId.saturatedFat,
    'TRANS_FAT': NutrientId.transFat,
    'MONOUNSATURATED_FAT': NutrientId.monounsaturatedFat,
    'POLYUNSATURATED_FAT': NutrientId.polyunsaturatedFat,
    'CHOLESTEROL': NutrientId.cholesterol,
    'SODIUM': NutrientId.sodium,
  };

  /// `unit` — scale is a property of the unit (ADR-0021).
  static const Map<String, Unit> units = <String, Unit>{
    'GRAM': Unit.gram,
    'MILLIGRAM': Unit.milligram,
    'MICROGRAM': Unit.microgram,
    'MILLILITRE': Unit.millilitre,
    'KILOCALORIE': Unit.kilocalorie,
    'KILOJOULE': Unit.kilojoule,
    'PERCENT': Unit.percent,
    'COUNT': Unit.count,
  };

  /// `basis`.
  static const Map<String, Basis> bases = <String, Basis>{
    'PER_100G': Basis.per100g,
    'PER_100ML': Basis.per100ml,
    'PER_SERVE': Basis.perServe,
    'PER_PACK': Basis.perPack,
  };

  /// `parseStrength` — signal S2.
  static const Map<String, ParseStrength> parseStrengths =
      <String, ParseStrength>{
    'EXACT': ParseStrength.exact,
    'NORMALISED': ParseStrength.normalised,
    'HEURISTIC': ParseStrength.heuristic,
  };

  /// `confidence` — the lattice.
  static const Map<String, Confidence> confidences = <String, Confidence>{
    'HIGH': Confidence.high,
    'MEDIUM': Confidence.medium,
    'LOW': Confidence.low,
    'ABSENT': Confidence.absent,
  };

  /// `qualifier` — a quantity denotes an interval (ADR-0027).
  static const Map<String, Qualifier> qualifiers = <String, Qualifier>{
    'EXACT': Qualifier.exact,
    'LESS_THAN': Qualifier.lessThan,
    'GREATER_THAN': Qualifier.greaterThan,
    'APPROXIMATELY': Qualifier.approximately,
  };

  /// `sourceType`.
  static const Map<String, SourceType> sourceTypes = <String, SourceType>{
    'REGULATION': SourceType.regulation,
    'WHO_MODEL': SourceType.whoModel,
    'PEER_REVIEWED': SourceType.peerReviewed,
    'GOVERNMENT_GUIDANCE': SourceType.governmentGuidance,
  };

  /// `evidenceStrength` (FR-KB-07).
  static const Map<String, EvidenceStrength> evidenceStrengths =
      <String, EvidenceStrength>{
    'ESTABLISHED': EvidenceStrength.established,
    'LIMITED': EvidenceStrength.limited,
    'CONTESTED': EvidenceStrength.contested,
  };

  /// `status` on a category record.
  static const Map<String, CategoryStatus> categoryStatuses =
      <String, CategoryStatus>{
    'PRIORITY': CategoryStatus.priority,
    'VERIFICATION_ONLY': CategoryStatus.verificationOnly,
    'SUPPORTED': CategoryStatus.supported,
  };

  /// `status` on an additive's Indian permission.
  ///
  /// Two members. There is no `PROHIBITED`, and the absence is the claim.
  static const Map<String, PermissionStatus> permissionStatuses =
      <String, PermissionStatus>{
    'PERMITTED': PermissionStatus.permitted,
    'UNKNOWN': PermissionStatus.unknown,
  };

  /// `functionalClass` — Codex CXG 36-1989.
  static const Map<String, FunctionalClass> functionalClasses =
      <String, FunctionalClass>{
    'ACIDITY_REGULATOR': FunctionalClass.acidityRegulator,
    'ANTICAKING_AGENT': FunctionalClass.anticakingAgent,
    'ANTIFOAMING_AGENT': FunctionalClass.antifoamingAgent,
    'ANTIOXIDANT': FunctionalClass.antioxidant,
    'BULKING_AGENT': FunctionalClass.bulkingAgent,
    'COLOUR': FunctionalClass.colour,
    'COLOUR_RETENTION_AGENT': FunctionalClass.colourRetentionAgent,
    'EMULSIFIER': FunctionalClass.emulsifier,
    'FIRMING_AGENT': FunctionalClass.firmingAgent,
    'FLAVOUR_ENHANCER': FunctionalClass.flavourEnhancer,
    'FLOUR_TREATMENT_AGENT': FunctionalClass.flourTreatmentAgent,
    'FOAMING_AGENT': FunctionalClass.foamingAgent,
    'GELLING_AGENT': FunctionalClass.gellingAgent,
    'GLAZING_AGENT': FunctionalClass.glazingAgent,
    'HUMECTANT': FunctionalClass.humectant,
    'PRESERVATIVE': FunctionalClass.preservative,
    'PROPELLANT': FunctionalClass.propellant,
    'RAISING_AGENT': FunctionalClass.raisingAgent,
    'SEQUESTRANT': FunctionalClass.sequestrant,
    'STABILISER': FunctionalClass.stabiliser,
    'SWEETENER': FunctionalClass.sweetener,
    'THICKENER': FunctionalClass.thickener,
  };

  /// `comparator` on an advisory rule.
  static const Map<String, ThresholdComparator> comparators =
      <String, ThresholdComparator>{
    'GTE': ThresholdComparator.gte,
    'GT': ThresholdComparator.gt,
    'LTE': ThresholdComparator.lte,
    'LT': ThresholdComparator.lt,
  };

  /// `classification` on an advisory rule.
  static const Map<String, AdvisoryClassification> classifications =
      <String, AdvisoryClassification>{
    'LOW': AdvisoryClassification.low,
    'MODERATE': AdvisoryClassification.moderate,
    'HIGH_IN': AdvisoryClassification.highIn,
  };

  /// `invariantId`, keyed on the printed code.
  static Map<String, InvariantId> get invariants => <String, InvariantId>{
        for (final InvariantId id in InvariantId.values) id.code: id,
      };

  /// Decodes a `version` object (ADR-0022).
  static Version version(JsonView v) => Version(
        v.required('major').asInt,
        v.required('minor').asInt,
        v.required('patch').asInt,
      );

  /// Decodes a `quantity` object.
  ///
  /// An absent `qualifier` yields [Qualifier.exact] — normative, not a
  /// convenience (ADR-0027 decision 5, MI-17). The writing half of the rule,
  /// that `EXACT` is never emitted, is enforced by CI-16.
  static Quantity quantity(JsonView v) {
    final int scaled = v.required('scaledValue').asInt;
    final Unit unit = v.required('unit').asEnum(units);
    final Qualifier qualifier = v.has('qualifier')
        ? v.required('qualifier').asEnum(qualifiers)
        : Qualifier.exact;
    return Quantity.qualified(scaled, unit, qualifier);
  }

  /// Converts [q] to the base units of its dimension.
  ///
  /// Tolerances and approximation deltas are held in base units so that a band
  /// stated in grams and a value read in milligrams compare without a
  /// conversion at the comparison site (ADR-0021).
  static int toBaseUnits(Quantity q) =>
      q.scaledValue * q.unit.baseUnitsPerIncrement;
}
