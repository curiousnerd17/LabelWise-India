import 'package:lw_domain/src/rulepack/pack_ids.dart';

/// What kind of authority a source is.
///
/// The distinction is not decorative. A gazetted regulation and a peer-reviewed
/// paper support different kinds of claim, and Layer 1 may rest only on the
/// former (B6): a regulation states what is required, a study states what was
/// observed.
enum SourceType {
  /// Gazetted law — FSSAI regulations.
  regulation,

  /// A WHO nutrient-profile model.
  whoModel,

  /// A peer-reviewed publication.
  peerReviewed,

  /// Non-binding guidance from a government or intergovernmental body.
  governmentGuidance,
}

/// How settled the evidence behind a claim is.
///
/// **This is what makes P1 achievable for additives at all** (FR-KB-07).
/// Without it, "contains INS 102" and "INS 102 is contested" would be presented
/// with the same confidence, which overstates the second and understates
/// nothing.
enum EvidenceStrength {
  /// Broad agreement; a regulation, or a well-replicated finding.
  established,

  /// Real but thin — few studies, small samples, or indirect evidence.
  limited,

  /// Competent bodies disagree.
  contested,
}

/// One entry of the citation registry.
///
/// `DATA_MODEL.md` §7.3. Every advisory claim in the product terminates here,
/// and FR-KB-05 fixes the minimum record: who said it, when they said it, and
/// when we last looked.
final class Source {
  /// Records a citable source.
  const Source({
    required this.sourceId,
    required this.title,
    required this.publisher,
    required this.publicationDate,
    required this.accessDate,
    required this.sourceType,
    required this.evidenceStrength,
    this.url,
    this.notes,
  });

  /// Stable key, referenced by rules, denominators and additive records.
  final SourceId sourceId;

  /// The document's title, as published.
  final String title;

  /// The body that published it.
  final String publisher;

  /// When it was published, as printed on the document.
  ///
  /// A `String`, not a date: publication dates in this registry are as printed,
  /// and some are a year alone. Parsing them to a `DateTime` would invent a day
  /// and a timezone the source never stated (M4).
  final String publicationDate;

  /// When we last read it — the ISO date recorded in the pack.
  ///
  /// Also a `String`, and for a second reason: a `DateTime` in a domain type
  /// would be a wall-clock value, which MI-07 forbids outright.
  final String accessDate;

  /// Where it can be read, when it is online.
  final String? url;

  /// What kind of authority this is.
  final SourceType sourceType;

  /// How settled the evidence is.
  final EvidenceStrength evidenceStrength;

  /// Curator's notes — scope, caveats, what was and was not examined.
  ///
  /// Not display text: this is provenance for whoever audits the pack.
  final String? notes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Source &&
          sourceId == other.sourceId &&
          title == other.title &&
          publisher == other.publisher &&
          publicationDate == other.publicationDate &&
          accessDate == other.accessDate &&
          url == other.url &&
          sourceType == other.sourceType &&
          evidenceStrength == other.evidenceStrength &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
        sourceId,
        title,
        publisher,
        publicationDate,
        accessDate,
        url,
        sourceType,
        evidenceStrength,
        notes,
      );

  @override
  String toString() => 'Source($sourceId, ${sourceType.name})';
}

/// The citation registry — every source the pack can cite.
///
/// Immutable once built, and the resolution target for MI-05. CI-08 already
/// proves no reference dangles; [contains] is what lets the loader prove the
/// same thing about a pack that was edited after CI saw it.
final class SourceRegistry {
  /// Records the registry, indexing by identifier.
  ///
  /// Throws [ArgumentError] on a duplicate `sourceId`. Two entries under one
  /// key would make every citation mean "whichever came first" — a silent
  /// choice, and silent choices about evidence are the worst kind.
  SourceRegistry(List<Source> sources)
      : sources = List<Source>.unmodifiable(sources),
        _byId = _index(sources);

  static Map<SourceId, Source> _index(List<Source> sources) {
    final Map<SourceId, Source> index = <SourceId, Source>{};
    for (final Source s in sources) {
      if (index.containsKey(s.sourceId)) {
        throw ArgumentError.value(
          s.sourceId.value,
          'sources',
          'Duplicate source identifier.',
        );
      }
      index[s.sourceId] = s;
    }
    return index;
  }

  /// Every source, in pack order.
  ///
  /// Pack order, not sorted: the pack's order is the curator's, it is stable
  /// across loads, and re-sorting here would make the domain's output depend on
  /// a comparison the pack never asked for (FR-PAR-02).
  final List<Source> sources;

  final Map<SourceId, Source> _byId;

  /// The source for [id], or null when the registry has no such entry.
  Source? operator [](SourceId id) => _byId[id];

  /// Whether [id] resolves.
  bool contains(SourceId id) => _byId.containsKey(id);

  /// How many sources the registry holds.
  int get length => sources.length;

  @override
  String toString() => 'SourceRegistry(${sources.length} sources)';
}
