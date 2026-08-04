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
export 'src/label/approximation_deltas.dart';
export 'src/label/basis.dart';
export 'src/label/dimension.dart';
export 'src/label/interval.dart';
export 'src/label/nutrient_id.dart';
export 'src/label/qualifier.dart';
export 'src/label/quantity.dart';
export 'src/label/trilean.dart';
export 'src/label/unit.dart';
export 'src/version.dart';
