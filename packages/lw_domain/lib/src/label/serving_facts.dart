import 'package:lw_domain/src/label/quantity.dart';

/// A declared figure about the pack rather than about a nutrient.
///
/// Named in `DATA_MODEL.md` §4.3 and §6.3 as one half of an invariant's
/// subject, alongside `NutrientId`. Serving-size manipulation is the primary
/// legal deception on Indian packaging (`PROJECT_VISION.md` §2.1), so these
/// three are critical fields and their arithmetic is checked as carefully as
/// any nutrient's.
enum ServingField {
  /// The manufacturer's declared serve.
  servingSize,

  /// How many serves the pack contains. Often declared approximately.
  servingsPerPack,

  /// Total declared pack contents.
  netQuantity,
}

/// The declared pack figures INV-08, INV-09 and INV-10 reconcile.
///
/// Every field is optional because a label may declare any subset. An absent
/// figure makes the invariants that need it `INAPPLICABLE` — "there was
/// nothing to check" — rather than failing them, which FR-CNF-04 calls
/// "inapplicable for want of data".
///
/// Supplied to S7 rather than carried on `TypedFields`: resolving serving
/// wordings to these three fields is FR-PAR-08 work that the rule pack does
/// not yet cover. Passing them in keeps the invariants live and testable now,
/// and keeps S7 unchanged when that resolution arrives.
final class ServingFacts {
  /// Records the declared figures.
  const ServingFacts({
    this.servingSize,
    this.servingsPerPack,
    this.netQuantity,
  });

  /// No figure declared. INV-08 to INV-10 are `INAPPLICABLE` against this.
  static const ServingFacts none = ServingFacts();

  /// The declared serve, as a mass or a volume.
  final Quantity? servingSize;

  /// The declared number of serves, as a count.
  final Quantity? servingsPerPack;

  /// The declared net quantity, as a mass or a volume.
  final Quantity? netQuantity;

  /// Whether no figure at all was declared.
  bool get isEmpty =>
      servingSize == null && servingsPerPack == null && netQuantity == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServingFacts &&
          servingSize == other.servingSize &&
          servingsPerPack == other.servingsPerPack &&
          netQuantity == other.netQuantity;

  @override
  int get hashCode => Object.hash(servingSize, servingsPerPack, netQuantity);

  @override
  String toString() => isEmpty
      ? 'ServingFacts(none)'
      : 'ServingFacts($servingSize, $servingsPerPack, $netQuantity)';
}
