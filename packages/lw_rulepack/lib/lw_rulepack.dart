/// Rule pack schema binding, deserialisation and integrity verification.
///
/// **Isolated so that `lw_domain` never learns what JSON is** (ADR-0012). The
/// domain receives already-decoded domain types; this package is the only place
/// that knows the pack is a set of JSON files, and the only place that knows
/// how the integrity digest is computed.
///
/// It performs **no I/O**. `RulePackSource` is the seam, and
/// `lw_infrastructure` implements it over assets (ADR-0007, §5 of
/// `ARCHITECTURE.md`). That is what lets the whole loader — including every
/// failure path — be tested from a `Map` literal, with no device and no file
/// system.
library;

export 'src/integrity.dart';
export 'src/json_view.dart' show DecodeException;
export 'src/pack_paths.dart';
export 'src/rule_pack_loader.dart';
export 'src/rule_pack_source.dart';
