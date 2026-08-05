import 'package:lw_domain/src/confidence/confidence.dart';
import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/quantity.dart';
import 'package:lw_domain/src/provenance/field_origin.dart';
import 'package:lw_domain/src/provenance/provenance.dart';

/// Why a value could not be typed from what was recognised.
///
/// An enum, not a string: the domain holds identity, never display text
/// (M5, FR-LOC-01). The user-facing wording resolves through the message
/// catalogue in the presentation layer.
enum UnresolvedReason {
  /// A number was recognised but no unit could be determined (FR-PAR-05).
  unitNotDetermined,

  /// A value was recognised but could not be attributed to a basis — per
  /// 100 g, per serve or per pack (FR-PAR-04).
  basisNotDetermined,

  /// Text was recognised in the value position but is not a number.
  valueNotParseable,

  /// More than one rule matched and none is clearly better.
  ambiguousMatch,

  /// Text was recognised but no rule in the pack matches it.
  noMatchingRule,
}

/// The state of a single field on a label.
///
/// A closed union discharging three requirements at once:
///
/// - **FR-PAR-09** — extracted, unresolved and not-declared are three
///   distinguishable outcomes, not a nullable value plus flags.
/// - **FR-ERR-03** — [UnresolvedField] and [NotDeclaredField] are distinct
///   types (MI-08). "We could not read this" and "the label does not say" are
///   different facts, and conflating them lets a parser failure masquerade as a
///   manufacturer's omission.
/// - **FR-CNF-12** — [UserSuppliedField] has no confidence member at all
///   (MI-02). Violation becomes unrepresentable rather than merely forbidden.
///
/// `sealed`, so a switch that omits a variant fails to compile. Exhaustiveness
/// is a language guarantee here, not a test.
sealed class FieldState {
  const FieldState();

  /// The value carried, or null for variants that carry none.
  Quantity? get quantityOrNull;

  /// The basis the value is expressed against, or null for variants that carry
  /// no value.
  Basis? get basisOrNull;

  /// The recorded confidence, or null where none exists.
  ///
  /// Null for [UserSuppliedField] because no confidence was inferred, and for
  /// [UnresolvedField] and [NotDeclaredField] because there is no value to be
  /// confident about. Use [propagatedConfidence] when combining fields.
  Confidence? get confidenceOrNull;

  /// How this field behaves when its confidence is combined with others.
  ///
  /// [UserSuppliedField] propagates as [Confidence.high]: the user has looked
  /// at the packet, which the parser cannot do (`ARCHITECTURE.md` §7.4). That
  /// is a propagation rule, not a stored confidence — the distinction is what
  /// keeps FR-CNF-12 intact.
  Confidence get propagatedConfidence;
}

/// A value read from the label by the parser.
final class ExtractedField extends FieldState {
  /// Records an extracted value with its confidence and provenance.
  const ExtractedField({
    required this.quantity,
    required this.basis,
    required this.provenance,
    required this.confidence,
  });

  /// The value as read.
  final Quantity quantity;

  /// The reference quantity it is expressed against.
  final Basis basis;

  /// Where it came from and how (ADR-0009).
  final Provenance provenance;

  /// How much trust it warrants (FR-CNF-01). Required — an extracted field
  /// without a confidence is not constructible.
  final Confidence confidence;

  @override
  Quantity? get quantityOrNull => quantity;

  @override
  Basis? get basisOrNull => basis;

  @override
  Confidence? get confidenceOrNull => confidence;

  @override
  Confidence get propagatedConfidence => confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractedField &&
          quantity == other.quantity &&
          basis == other.basis &&
          provenance == other.provenance &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(quantity, basis, provenance, confidence);

  @override
  String toString() => 'ExtractedField($quantity, ${basis.name}, '
      '${confidence.name})';
}

/// A value computed from other fields.
final class DerivedField extends FieldState {
  /// Records a derived value with its confidence and provenance.
  const DerivedField({
    required this.quantity,
    required this.basis,
    required this.provenance,
    required this.confidence,
  });

  /// The computed value.
  final Quantity quantity;

  /// The reference quantity it is expressed against.
  final Basis basis;

  /// Where it came from and how.
  final Provenance provenance;

  /// The meet of its inputs' confidences, possibly downgraded when the
  /// derivation is itself approximate (ADR-0010).
  final Confidence confidence;

  @override
  Quantity? get quantityOrNull => quantity;

  @override
  Basis? get basisOrNull => basis;

  @override
  Confidence? get confidenceOrNull => confidence;

  @override
  Confidence get propagatedConfidence => confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DerivedField &&
          quantity == other.quantity &&
          basis == other.basis &&
          provenance == other.provenance &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(quantity, basis, provenance, confidence);

  @override
  String toString() =>
      'DerivedField($quantity, ${basis.name}, ${confidence.name})';
}

/// A value entered or corrected by the user.
///
/// **There is deliberately no confidence member** (FR-CNF-12, MI-02). A
/// user-supplied value is not a point on the confidence lattice but a different
/// kind of thing, and the absence of the field is what makes assigning one
/// impossible rather than merely discouraged.
final class UserSuppliedField extends FieldState {
  /// Records a value the user supplied.
  const UserSuppliedField({
    required this.quantity,
    required this.basis,
    required this.provenance,
  });

  /// The value the user entered.
  final Quantity quantity;

  /// The reference quantity it is expressed against.
  final Basis basis;

  /// Provenance with [FieldOrigin.userSupplied]; carries no rule and no
  /// strength.
  final Provenance provenance;

  @override
  Quantity? get quantityOrNull => quantity;

  @override
  Basis? get basisOrNull => basis;

  /// Always null. No confidence was inferred and none may be (FR-CNF-12).
  @override
  Confidence? get confidenceOrNull => null;

  /// Propagates as [Confidence.high] — the user has seen the packet.
  @override
  Confidence get propagatedConfidence => Confidence.high;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSuppliedField &&
          quantity == other.quantity &&
          basis == other.basis &&
          provenance == other.provenance;

  @override
  int get hashCode => Object.hash(quantity, basis, provenance);

  @override
  String toString() => 'UserSuppliedField($quantity, ${basis.name})';
}

/// Something was recognised in this field's position but could not be typed.
///
/// Distinct from [NotDeclaredField]: this is our failure, not the label's
/// silence (FR-ERR-03).
final class UnresolvedField extends FieldState {
  /// Records a field we could not resolve, and why.
  const UnresolvedField({
    required this.reason,
    required this.provenance,
  });

  /// Why resolution failed.
  final UnresolvedReason reason;

  /// How far the pipeline got before failing.
  final Provenance provenance;

  @override
  Quantity? get quantityOrNull => null;

  @override
  Basis? get basisOrNull => null;

  @override
  Confidence? get confidenceOrNull => null;

  @override
  Confidence get propagatedConfidence => Confidence.absent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnresolvedField &&
          reason == other.reason &&
          provenance == other.provenance;

  @override
  int get hashCode => Object.hash(reason, provenance);

  @override
  String toString() => 'UnresolvedField(${reason.name})';
}

/// The label does not carry this field.
///
/// Distinct from [UnresolvedField]: this is the label's state, not our
/// failure (FR-ERR-03). Excluded from the accuracy denominator, because a
/// manufacturer's omission is not a parser error (`TEST_STRATEGY.md` §4.4).
final class NotDeclaredField extends FieldState {
  /// Records that the label does not declare this field.
  const NotDeclaredField();

  @override
  Quantity? get quantityOrNull => null;

  @override
  Basis? get basisOrNull => null;

  @override
  Confidence? get confidenceOrNull => null;

  @override
  Confidence get propagatedConfidence => Confidence.absent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NotDeclaredField;

  @override
  int get hashCode => (NotDeclaredField).hashCode;

  @override
  String toString() => 'NotDeclaredField()';
}
