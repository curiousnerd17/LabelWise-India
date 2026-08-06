/// The LabelWise India domain core.
///
/// **This package declares zero dependencies, by design** (ADR-0007). No
/// Flutter, no packages, not even JSON. The rule pack enters as already-parsed
/// domain types; deserialisation happens in infrastructure. A dependency added
/// here is an architectural violation, not a convenience.
///
/// The purity is not aesthetic. The parser is iterated dozens of times
/// against a 55-label golden corpus, and pure-Dart tests run that corpus in
/// seconds where
/// device tests would take minutes. The layering exists primarily to buy that
/// iteration speed (NFR-MNT-01, NFR-TST-02, E1).
library;

export 'src/confidence/confidence.dart';
export 'src/confidence/confidence_policy.dart';
export 'src/confidence/confidence_signals.dart';
export 'src/confidence/scan_confidence.dart';
export 'src/invariants/invariant_id.dart';
export 'src/invariants/invariant_result.dart';
export 'src/invariants/tolerance.dart';
export 'src/label/approximation_deltas.dart';
export 'src/label/basis.dart';
export 'src/label/dimension.dart';
export 'src/label/field_state.dart';
export 'src/label/interval.dart';
export 'src/label/nutrient_id.dart';
export 'src/label/qualifier.dart';
export 'src/label/quantity.dart';
export 'src/label/serving_facts.dart';
export 'src/label/trilean.dart';
export 'src/label/unit.dart';
export 'src/parser/basis_markers.dart';
export 'src/parser/candidates.dart';
export 'src/parser/classified_regions.dart';
export 'src/parser/label_layout.dart';
export 'src/parser/normalised_text.dart';
export 'src/parser/parse_failure.dart';
export 'src/parser/qualifier_lexicon.dart';
export 'src/parser/recognition_result.dart';
export 'src/parser/region_markers.dart';
export 'src/parser/resolved_fields.dart';
export 'src/parser/scored_fields.dart';
export 'src/parser/stage.dart';
export 'src/parser/stages/s1_normalisation.dart';
export 'src/parser/stages/s2_layout.dart';
export 'src/parser/stages/s3_region_classification.dart';
export 'src/parser/stages/s4_tokenisation.dart';
export 'src/parser/stages/s5_field_resolution.dart';
export 'src/parser/stages/s6_unit_normalisation.dart';
export 'src/parser/stages/s7_invariant_evaluation.dart';
export 'src/parser/stages/s8_confidence_assignment.dart';
export 'src/parser/typed_fields.dart';
export 'src/parser/unit_lexicon.dart';
export 'src/parser/validated_fields.dart';
export 'src/provenance/field_origin.dart';
export 'src/provenance/parse_strength.dart';
export 'src/provenance/pipeline_stage.dart';
export 'src/provenance/provenance.dart';
export 'src/provenance/region_ref.dart';
export 'src/provenance/rule_id.dart';
export 'src/provenance/substitution.dart';
export 'src/rules/synonym_table.dart';
export 'src/version.dart';
