import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/src/decode/primitives.dart';
import 'package:lw_rulepack/src/json_view.dart';

/// Decoders for the manifest and the eager knowledge segments.
///
/// Each entry point takes a positioned [JsonView] and returns a domain type, or
/// raises a [DecodeException] the loader converts at the boundary. **Nothing
/// here catches** — a decoder that swallowed a failure would produce a
/// half-built table, and FR-ERR-06 has no room for one.
final class KnowledgeDecoder {
  const KnowledgeDecoder._();

  /// Decodes `manifest.json`.
  static RulePackManifest manifest(JsonView root) {
    // Each version is decoded outside the try below. Version rejects a negative
    // component with an ArgumentError of its own, and a catch wide enough to
    // include them would report a bad version number as a digest problem —
    // sending a contributor to the wrong field entirely.
    final Version schema = _version(root.required('schemaVersion'));
    final Version packVersion = _version(root.required('packVersion'));
    final Version minApp = _version(root.required('minAppVersion'));
    final JsonView hashField = root.required('integrityHash');
    final String hash = hashField.asString;
    try {
      return RulePackManifest(
        schemaVersion: schema,
        packVersion: packVersion,
        minAppVersion: minApp,
        integrityHash: hash,
        contentLicence: root.required('contentLicence').asString,
        generatedAt: root.required('generatedAt').asString,
        notes: root.has('notes') ? root.required('notes').asString : null,
      );
    } on ArgumentError {
      // The only ArgumentError the manifest raises: a malformed digest. That is
      // a programming error when we build one and a pack defect when we read
      // one, so it becomes a positioned failure here.
      hashField.reject(
        RulePackFailureKind.schemaViolation,
        'Expected sha256: and 64 lower-case hex digits, found "$hash".',
      );
    }
  }

  /// Decodes a version, converting its own range check to a positioned
  /// failure.
  static Version _version(JsonView v) {
    try {
      return Primitives.version(v);
    } on ArgumentError catch (e) {
      v.reject(RulePackFailureKind.schemaViolation, '${e.message}');
    }
  }

  /// Decodes `sources.json`.
  static SourceRegistry sources(JsonView root) {
    final List<Source> decoded = <Source>[];
    for (final JsonView v in root.required('sources').elements) {
      decoded.add(
        Source(
          sourceId: v.required('sourceId').asId(SourceId.new),
          title: v.required('title').asString,
          publisher: v.required('publisher').asString,
          publicationDate: v.required('publicationDate').asString,
          accessDate: v.required('accessDate').asString,
          url: v.has('url') ? v.required('url').asString : null,
          sourceType: v.required('sourceType').asEnum(Primitives.sourceTypes),
          evidenceStrength: v
              .required('evidenceStrength')
              .asEnum(Primitives.evidenceStrengths),
          notes: v.has('notes') ? v.required('notes').asString : null,
        ),
      );
    }
    try {
      return SourceRegistry(decoded);
    } on ArgumentError catch (e) {
      root.reject(RulePackFailureKind.duplicateKey, '${e.message}');
    }
  }

  /// Decodes `nutrients/synonyms.json` into the S5 table.
  static SynonymTable synonyms(JsonView root) {
    final List<SynonymEntry> entries = <SynonymEntry>[];
    for (final JsonView v in root.required('entries').elements) {
      final List<SynonymPattern> patterns = <SynonymPattern>[];
      for (final JsonView p in v.required('patterns').elements) {
        patterns.add(
          SynonymPattern(
            text: p.required('text').asString,
            strength: p.required('strength').asEnum(Primitives.parseStrengths),
            caseSensitive: p.has('caseSensitive')
                ? p.required('caseSensitive').asBool
                : false,
          ),
        );
      }
      final List<Unit> units = <Unit>[
        for (final JsonView u in v.required('expectedUnits').elements)
          u.asEnum(Primitives.units),
      ];
      try {
        entries.add(
          SynonymEntry(
            nutrient: v.required('nutrient').asEnum(Primitives.nutrients),
            patterns: patterns,
            expectedUnits: units,
          ),
        );
      } on ArgumentError catch (e) {
        v.reject(RulePackFailureKind.schemaViolation, '${e.message}');
      }
    }
    try {
      return SynonymTable(entries);
    } on ArgumentError catch (e) {
      // The table refuses one wording claimed by two nutrients. A wording that
      // resolved to whichever entry came first would be a silent misreading.
      root.reject(RulePackFailureKind.duplicateKey, '${e.message}');
    }
  }

  /// Decodes `nutrients/rda.json`.
  static RdaTable rda(JsonView root) {
    final List<RdaDenominator> decoded = <RdaDenominator>[];
    for (final JsonView v in root.required('denominators').elements) {
      try {
        decoded.add(
          RdaDenominator(
            constantId: v.required('constantId').asId(ConstantId.new),
            nutrient: v.required('nutrient').asEnum(Primitives.nutrients),
            value: Primitives.quantity(v.required('value')),
            sourceRefs: _sourceRefs(v),
          ),
        );
      } on ArgumentError catch (e) {
        v.reject(RulePackFailureKind.schemaViolation, '${e.message}');
      }
    }
    try {
      return RdaTable(decoded);
    } on ArgumentError catch (e) {
      root.reject(RulePackFailureKind.duplicateKey, '${e.message}');
    }
  }

  /// Decodes `categories/categories.json`.
  static CategoryTable categories(JsonView root) {
    final Map<String, InvariantId> invariants = Primitives.invariants;
    final List<Category> decoded = <Category>[];
    for (final JsonView v in root.required('categories').elements) {
      final List<InvariantId> excluded = <InvariantId>[
        if (v.has('inapplicableInvariants'))
          for (final JsonView i
              in v.required('inapplicableInvariants').elements)
            i.asEnum(invariants),
      ];
      decoded.add(
        Category(
          categoryId: v.required('categoryId').asId(CategoryId.new),
          nameMessageId: v.required('nameMessageId').asId(MessageId.new),
          defaultBasis: v.required('defaultBasis').asEnum(Primitives.bases),
          status: v.required('status').asEnum(Primitives.categoryStatuses),
          inapplicableInvariants: excluded,
        ),
      );
    }
    try {
      return CategoryTable(decoded);
    } on ArgumentError catch (e) {
      root.reject(RulePackFailureKind.duplicateKey, '${e.message}');
    }
  }

  /// Decodes one `messages/<locale>.json` catalogue.
  static MessageCatalogue messages(JsonView root) {
    final Map<MessageId, String> entries = <MessageId, String>{};
    final JsonView table = root.required('messages');
    for (final String key in table.asObject.keys) {
      final JsonView entry = table.required(key);
      // The identifier is the KEY here, not the value — the value is the text.
      // Validating the key is what stops a malformed id reaching a lookup that
      // would simply never match.
      if (!MessageId.isValid(key)) {
        entry.reject(
          RulePackFailureKind.schemaViolation,
          'Not a well-formed message identifier: "$key".',
        );
      }
      entries[MessageId(key)] = entry.asString;
    }
    try {
      return MessageCatalogue(
        locale: root.required('locale').asString,
        reviewed: root.required('reviewed').asBool,
        reviewedBy: root.has('reviewedBy')
            ? root.required('reviewedBy').asString
            : null,
        messages: entries,
      );
    } on ArgumentError catch (e) {
      // An unreviewed non-English catalogue. FR-LOC-04 makes review a shipping
      // condition, so this is a rejection rather than a warning.
      root.reject(RulePackFailureKind.schemaViolation, '${e.message}');
    }
  }

  /// Decodes `rules/thresholds.json`.
  ///
  /// Structural only. **Nothing here evaluates a threshold** — Layer 2 is v0.2
  /// scope (ADR-0025) and the file ships empty.
  static AdvisoryRuleTable thresholds(JsonView root) {
    final List<AdvisoryRule> decoded = <AdvisoryRule>[];
    for (final JsonView v in root.required('rules').elements) {
      try {
        decoded.add(
          AdvisoryRule(
            ruleId: v.required('ruleId').asId(RuleId.new),
            ruleVersion: Primitives.version(v.required('ruleVersion')),
            nutrient: v.required('nutrient').asEnum(Primitives.nutrients),
            basis: v.required('basis').asEnum(Primitives.bases),
            comparator: v.required('comparator').asEnum(Primitives.comparators),
            threshold: Primitives.quantity(v.required('threshold')),
            classification:
                v.required('classification').asEnum(Primitives.classifications),
            severityWeight: v.has('severityWeight')
                ? v.required('severityWeight').asNum
                : null,
            categorySelector: v.has('categorySelector')
                ? _selector(v.required('categorySelector'))
                : null,
            sourceRefs: _sourceRefs(v),
            messageId: v.required('messageId').asId(MessageId.new),
          ),
        );
      } on ArgumentError catch (e) {
        v.reject(RulePackFailureKind.schemaViolation, '${e.message}');
      }
    }
    try {
      return AdvisoryRuleTable(decoded);
    } on ArgumentError catch (e) {
      root.reject(RulePackFailureKind.duplicateKey, '${e.message}');
    }
  }

  static CategorySelector _selector(JsonView v) => CategorySelector(
        appliesToAll:
            v.has('appliesToAll') ? v.required('appliesToAll').asBool : true,
        includeCategories: <CategoryId>[
          if (v.has('includeCategories'))
            for (final JsonView c in v.required('includeCategories').elements)
              c.asId(CategoryId.new),
        ],
        excludeCategories: <CategoryId>[
          if (v.has('excludeCategories'))
            for (final JsonView c in v.required('excludeCategories').elements)
              c.asId(CategoryId.new),
        ],
      );

  static List<SourceId> _sourceRefs(JsonView v) => <SourceId>[
        for (final JsonView s in v.required('sourceRefs').elements)
          s.asId(SourceId.new),
      ];
}
