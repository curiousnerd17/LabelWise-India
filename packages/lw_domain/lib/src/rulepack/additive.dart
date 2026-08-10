import 'package:lw_domain/src/label/ingredient.dart';
import 'package:lw_domain/src/rulepack/pack_ids.dart';
import 'package:lw_domain/src/rulepack/source.dart';

/// What an additive does in the food.
///
/// The Codex CXG 36-1989 functional classes. A closed set: these are defined by
/// an international standard, not by us, and inventing a class would make our
/// vocabulary untraceable to the standard it claims to follow.
enum FunctionalClass {
  /// Adjusts or maintains acidity.
  acidityRegulator,

  /// Stops powders clumping.
  anticakingAgent,

  /// Prevents or reduces foaming.
  antifoamingAgent,

  /// Slows spoilage caused by oxygen.
  antioxidant,

  /// Adds bulk without adding energy.
  bulkingAgent,

  /// Adds or restores colour.
  colour,

  /// Stabilises or intensifies existing colour.
  colourRetentionAgent,

  /// Keeps oil and water mixed.
  emulsifier,

  /// Keeps tissue firm.
  firmingAgent,

  /// Intensifies existing taste or smell.
  flavourEnhancer,

  /// Improves baking quality of flour.
  flourTreatmentAgent,

  /// Helps form or maintain a foam.
  foamingAgent,

  /// Forms a gel.
  gellingAgent,

  /// Gives a shiny coating.
  glazingAgent,

  /// Keeps food moist.
  humectant,

  /// Slows microbial spoilage.
  preservative,

  /// Expels food from a container.
  propellant,

  /// Releases gas to raise a dough.
  raisingAgent,

  /// Binds metal ions.
  sequestrant,

  /// Keeps a mixture uniform.
  stabiliser,

  /// Provides sweetness.
  sweetener,

  /// Increases viscosity.
  thickener,
}

/// Whether an additive was found permitted in the schedules examined.
///
/// **Two values, not three, and the absent third is the point.** There is no
/// `PROHIBITED`, because finding nothing is not evidence of prohibition.
enum PermissionStatus {
  /// Found by name in a cited schedule, for the listed food products only.
  permitted,

  /// Not found in the schedules examined.
  ///
  /// > **This never means prohibited.** Only Tables 1 and 2 of Appendix A were
  /// > read. Presenting an unexamined additive as disallowed would be exactly
  /// > the confident-and-wrong output P1 exists to prevent.
  unknown,
}

/// One citation supporting a permission claim.
///
/// `DATA_MODEL.md` §7.7. Every field exists so a reader can check us against
/// the primary source rather than take our word for it.
final class PermissionEvidence {
  /// Records one schedule entry.
  const PermissionEvidence({
    required this.sourceRef,
    required this.scheduleRef,
    required this.entryName,
    required this.foodProducts,
    required this.limit,
  });

  /// Which registry source this comes from.
  final SourceId sourceRef;

  /// Exact location, such as `Appendix A, Table 1, section G.a, item 3`.
  final String scheduleRef;

  /// The additive name **as printed in the schedule**.
  ///
  /// Appendix A contains no INS numbers, so mapping an INS number to a schedule
  /// entry is *our inference*. Recording the printed name is what makes that
  /// inference auditable instead of invisible.
  final String entryName;

  /// The food products the cited column covers.
  ///
  /// **Permission does not extend beyond them.** A colour permitted in biscuits
  /// is not thereby permitted in noodles.
  final String foodProducts;

  /// The limit as printed — `GMP`, `100 ppm max`.
  ///
  /// A `String`, deliberately. These are printed in units and forms that do not
  /// share a scale, and coercing them to a number would fabricate precision the
  /// regulation does not state.
  final String limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PermissionEvidence &&
          sourceRef == other.sourceRef &&
          scheduleRef == other.scheduleRef &&
          entryName == other.entryName &&
          foodProducts == other.foodProducts &&
          limit == other.limit;

  @override
  int get hashCode => Object.hash(
        sourceRef,
        scheduleRef,
        entryName,
        foodProducts,
        limit,
      );

  @override
  String toString() => 'PermissionEvidence($entryName in $foodProducts)';
}

/// An additive's Indian regulatory standing.
///
/// **Deliberately not a boolean.** Appendix A of the FSS (Food Products
/// Standards and Food Additives) Regulations 2011 lists additives by name, per
/// food product, with a per-product limit — and contains no INS numbers at all.
/// "Is INS 322 permitted in India?" is not a question the regulation answers,
/// and a `bool` would state a claim no source supports.
final class IndianPermission {
  /// Records a permission standing.
  ///
  /// Throws [ArgumentError] when [status] is [PermissionStatus.permitted] and
  /// [evidence] is empty. A permission claim with no citation is the exact
  /// failure FR-KB-04 exists to prevent, and the type refuses it rather than
  /// leaving it to validation somebody might skip.
  IndianPermission({
    required this.status,
    List<PermissionEvidence> evidence = const <PermissionEvidence>[],
    this.note,
  }) : evidence = List<PermissionEvidence>.unmodifiable(evidence) {
    if (status == PermissionStatus.permitted && evidence.isEmpty) {
      throw ArgumentError.value(
        status.name,
        'evidence',
        'PERMITTED requires at least one citation.',
      );
    }
  }

  /// Whether permission was found in the schedules examined.
  final PermissionStatus status;

  /// The citations supporting a `PERMITTED` status.
  ///
  /// Empty for `UNKNOWN`, and that emptiness is honest: we found nothing, so we
  /// cite nothing.
  final List<PermissionEvidence> evidence;

  /// Curator's note on scope or caveats.
  final String? note;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndianPermission &&
          status == other.status &&
          note == other.note &&
          _sameEvidence(other.evidence);

  bool _sameEvidence(List<PermissionEvidence> other) {
    if (evidence.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (evidence[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(status, note, Object.hashAll(evidence));

  @override
  String toString() =>
      'IndianPermission(${status.name}, ${evidence.length} citations)';
}

/// One INS-keyed additive record.
///
/// `DATA_MODEL.md` §7.7, keyed on the INS integer because Indian labelling
/// mandates the number (ADR-0005) — which makes it the one identifier we can
/// rely on being printed.
///
/// **This is a record, not an engine.** Matching an ingredient token to a
/// record is additive identification, which `ROADMAP.md` §4.3 item 4.4
/// schedules for Layer 1 and which is not part of this milestone.
final class AdditiveRecord {
  /// Records an additive.
  ///
  /// Throws [ArgumentError] when [sourceRefs] is empty (FR-KB-04).
  AdditiveRecord({
    required this.insNumber,
    required this.commonName,
    required this.functionalClass,
    required this.descriptionMessageId,
    required this.evidenceStrength,
    required List<SourceId> sourceRefs,
    required this.indianPermission,
    List<String> alternateNames = const <String>[],
  })  : sourceRefs = List<SourceId>.unmodifiable(sourceRefs),
        alternateNames = List<String>.unmodifiable(alternateNames) {
    if (sourceRefs.isEmpty) {
      throw ArgumentError.value(
        insNumber.value,
        'sourceRefs',
        'An additive record with no citation cannot be shown to a user.',
      );
    }
  }

  /// The INS number — the primary key.
  final InsNumber insNumber;

  /// The name most commonly printed.
  ///
  /// A proper name, not display prose: `Curcumin` is what the substance is
  /// called, in any language. The plain-language *explanation* is
  /// [descriptionMessageId] and lives in the catalogue.
  final String commonName;

  /// Other names the same additive is printed under.
  final List<String> alternateNames;

  /// What it does in the food.
  final FunctionalClass functionalClass;

  /// The catalogue key for the plain-language description (P9, FR-KB-06).
  final MessageId descriptionMessageId;

  /// How settled the evidence about this additive is (FR-KB-07).
  final EvidenceStrength evidenceStrength;

  /// Where the record's claims come from. Never empty.
  final List<SourceId> sourceRefs;

  /// Indian regulatory standing.
  final IndianPermission indianPermission;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdditiveRecord &&
          insNumber == other.insNumber &&
          commonName == other.commonName &&
          functionalClass == other.functionalClass &&
          descriptionMessageId == other.descriptionMessageId &&
          evidenceStrength == other.evidenceStrength &&
          indianPermission == other.indianPermission &&
          _sameStrings(alternateNames, other.alternateNames) &&
          _sameRefs(other.sourceRefs);

  static bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  bool _sameRefs(List<SourceId> other) {
    if (sourceRefs.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (sourceRefs[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        insNumber,
        commonName,
        functionalClass,
        descriptionMessageId,
        evidenceStrength,
        indianPermission,
        Object.hashAll(alternateNames),
        Object.hashAll(sourceRefs),
      );

  @override
  String toString() => 'AdditiveRecord(${insNumber.value}, $commonName)';
}

/// The INS-keyed additive table.
///
/// **The pack's largest segment, and the one §9.2 of `ARCHITECTURE.md` loads
/// lazily** — it is not needed for a nutrition-only scan, and eager loading
/// would spend the 300 ms rule pack budget on data most scans never touch.
final class AdditiveTable {
  /// Records the table, indexing by INS number.
  ///
  /// Throws [ArgumentError] on a duplicate INS number.
  AdditiveTable(List<AdditiveRecord> additives)
      : additives = List<AdditiveRecord>.unmodifiable(additives),
        _byIns = _index(additives);

  /// The empty table, for a pack whose additives have not been loaded.
  static final AdditiveTable empty = AdditiveTable(const <AdditiveRecord>[]);

  static Map<int, AdditiveRecord> _index(List<AdditiveRecord> additives) {
    final Map<int, AdditiveRecord> index = <int, AdditiveRecord>{};
    for (final AdditiveRecord a in additives) {
      if (index.containsKey(a.insNumber.value)) {
        throw ArgumentError.value(
          a.insNumber.value,
          'additives',
          'Duplicate INS number.',
        );
      }
      index[a.insNumber.value] = a;
    }
    return index;
  }

  /// Every record, in pack order.
  final List<AdditiveRecord> additives;

  final Map<int, AdditiveRecord> _byIns;

  /// The record for [ins], or null when the pack has no entry.
  ///
  /// **Null is the common case and it is not a failure.** The pack covers the
  /// INS numbers frequent in four categories; an unrecognised number is
  /// reported to the user as unidentified *with the number shown*, which is
  /// P1-compliant and useful. Guessing would not be.
  AdditiveRecord? operator [](InsNumber ins) => _byIns[ins.value];

  /// Whether [ins] resolves.
  bool contains(InsNumber ins) => _byIns.containsKey(ins.value);

  /// How many records the table holds.
  int get length => additives.length;

  @override
  String toString() => 'AdditiveTable(${additives.length} additives)';
}
