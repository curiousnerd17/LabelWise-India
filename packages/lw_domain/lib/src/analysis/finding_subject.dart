import 'package:lw_domain/src/label/nutrient_id.dart';
import 'package:lw_domain/src/label/serving_facts.dart';

/// What a Layer 1 finding, or one input to a derivation, is **about**.
///
/// `sealed`, so a switch that omits a variant does not compile. When additive
/// identification arrives (FR-L1-07, deferred), the new variant will stop every
/// existing switch from building until it decides what to do — which is the
/// failure mode worth having, rather than a silent fallthrough.
///
/// > **Deliberately not `InvariantSubject`, despite being structurally
/// > identical today.** S7's union answers "which fields participated in this
/// > invariant"; this one answers "which figure is this factual statement
/// > about". They agree only by coincidence of the domain currently having two
/// > kinds of subject. Layer 1's third variant will be an additive, which no
/// > invariant will ever carry — so sharing the type would turn a Layer 1
/// > addition into a change to S7 and every exhaustive switch it owns. Layer 1
/// > owns its own vocabulary; the duplication is the price and it is recorded
/// > here rather than discovered later.
sealed class FindingSubject {
  /// Base constructor for the two kinds.
  const FindingSubject();
}

/// A nutrient the finding restates or derives.
final class FindingNutrient implements FindingSubject {
  /// Records a nutrient subject.
  const FindingNutrient(this.nutrient);

  /// The nutrient the statement is about.
  final NutrientId nutrient;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FindingNutrient && nutrient == other.nutrient;

  @override
  int get hashCode => nutrient.hashCode;

  @override
  String toString() => 'FindingNutrient(${nutrient.name})';
}

/// A declared pack figure the finding restates or derives.
final class FindingServing implements FindingSubject {
  /// Records a serving subject.
  const FindingServing(this.field);

  /// The pack figure the statement is about.
  final ServingField field;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FindingServing && field == other.field;

  @override
  int get hashCode => field.hashCode;

  @override
  String toString() => 'FindingServing(${field.name})';
}
