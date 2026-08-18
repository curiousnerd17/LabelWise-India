import 'package:lw_domain/src/analysis/finding_subject.dart';
import 'package:lw_domain/src/confidence/confidence.dart';
import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/rulepack/pack_ids.dart';

/// The arithmetic a Layer 1 derivation performed.
///
/// Exactly the six operations `DATA_MODEL.md` §6.2 names. A seventh would be a
/// capability nothing implements, and an enum member no code can produce is a
/// promise the product does not keep.
enum DerivationOperation {
  /// A value declared per serve, restated per 100 g or 100 ml (FR-L1-02).
  normaliseTo100,

  /// A per-100 value expressed for the declared serve.
  scaleToServe,

  /// A per-100 value expressed for the whole pack (FR-L1-03).
  scaleToPack,

  /// A value expressed as a share of a gazetted daily value (FR-L1-04).
  rdaPercent,

  /// Salt restated as sodium, or the reverse.
  saltToSodium,

  /// Energy converted between kilojoules and kilocalories (FR-PAR-07).
  energyConvert,
}

/// One declared value the arithmetic consumed.
///
/// Records the value **as it was read**, qualifier included: `< 0.5 g` and
/// `0.5 g` are different declarations (MI-16, ADR-0027), and a derivation that
/// recorded them identically would misstate what it consumed.
final class DerivationInput {
  /// Records one input.
  const DerivationInput({
    required this.field,
    required this.quantity,
    required this.basis,
    required this.confidence,
  });

  /// Which figure this value is.
  final FindingSubject field;

  /// The value consumed, exactly as declared.
  final Quantity quantity;

  /// The reference the value was expressed against.
  final Basis basis;

  /// How much the input itself was trusted.
  ///
  /// Carried per input rather than only on the result, so a reader can see
  /// *which* input weakened a derived figure rather than only that something
  /// did (ADR-0009).
  final Confidence confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DerivationInput &&
          field == other.field &&
          quantity == other.quantity &&
          basis == other.basis &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(field, quantity, basis, confidence);

  @override
  String toString() =>
      'DerivationInput($field, $quantity, ${basis.name}, ${confidence.name})';
}

/// A gazetted constant the arithmetic applied, with its citation.
///
/// **This is what makes an RDA computation auditable.** The 2,000 mg sodium
/// denominator appears here as a named constant with a source reference, not as
/// a number that materialised inside the arithmetic.
///
/// The value is carried, not merely referenced. A finding stored today and read
/// months later must still show the denominator that was actually applied, even
/// if the rule pack has since revised it (FR-HIS-05).
final class ConstantUsed {
  /// Records one applied constant.
  const ConstantUsed({
    required this.constantId,
    required this.value,
    required this.sourceRef,
  });

  /// The rule pack identifier of the constant.
  final ConstantId constantId;

  /// Its value at the time the derivation ran.
  final Quantity value;

  /// Where the constant comes from, resolvable through the source registry.
  final SourceId sourceRef;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstantUsed &&
          constantId == other.constantId &&
          value == other.value &&
          sourceRef == other.sourceRef;

  @override
  int get hashCode => Object.hash(constantId, value, sourceRef);

  @override
  String toString() => 'ConstantUsed(${constantId.value} = $value)';
}

/// How a Layer 1 figure was arrived at (FR-EXP-09).
///
/// A derived number with no derivation is a number the user is asked to trust.
/// Every Layer 1 finding that computes anything carries one of these, so the
/// arithmetic can be shown rather than asserted.
final class Derivation {
  /// Records a derivation.
  ///
  /// Both lists are copied and stored unmodifiable: an audit trail a caller can
  /// edit after the fact is not an audit trail.
  Derivation({
    required this.operation,
    required List<DerivationInput> inputs,
    required List<ConstantUsed> constantsUsed,
    required this.result,
  })  : inputs = List<DerivationInput>.unmodifiable(inputs),
        constantsUsed = List<ConstantUsed>.unmodifiable(constantsUsed);

  /// The arithmetic performed.
  final DerivationOperation operation;

  /// The declared values consumed, **in the order the arithmetic used them**.
  ///
  /// Order is part of the value: reversing it describes a different
  /// calculation.
  final List<DerivationInput> inputs;

  /// The gazetted constants applied, in pack order.
  ///
  /// Legitimately empty for arithmetic that applies none — whole-pack scaling
  /// multiplies two declared values and consults no constant. Empty is a fact
  /// about the operation, not a missing field.
  final List<ConstantUsed> constantsUsed;

  /// What the arithmetic produced.
  final Quantity result;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Derivation) {
      return false;
    }
    if (operation != other.operation || result != other.result) {
      return false;
    }
    return _sameInputs(other.inputs) && _sameConstants(other.constantsUsed);
  }

  bool _sameInputs(List<DerivationInput> other) {
    if (inputs.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (inputs[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  bool _sameConstants(List<ConstantUsed> other) {
    if (constantsUsed.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (constantsUsed[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        operation,
        result,
        Object.hashAll(inputs),
        Object.hashAll(constantsUsed),
      );

  @override
  String toString() => 'Derivation(${operation.name}, ${inputs.length} inputs, '
      '${constantsUsed.length} constants, $result)';
}
