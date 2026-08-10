import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  const String digest =
      'sha256:33177c6c7a71c5650c3a28d05f95d3c83154507d947612e78af312b6e5d84d46';

  RulePackManifest manifest({
    Version? schema,
    Version? pack,
    Version? minApp,
    String hash = digest,
  }) =>
      RulePackManifest(
        schemaVersion: schema ?? Version(1, 0, 0),
        packVersion: pack ?? Version(0, 1, 0),
        minAppVersion: minApp ?? Version(0, 1, 0),
        integrityHash: hash,
        contentLicence: 'CC-BY-4.0',
        generatedAt: '2026-08-04',
      );

  RulePack pack({RulePackManifest? m}) => RulePack(
        manifest: m ?? manifest(),
        sources: SourceRegistry(<Source>[
          Source(
            sourceId: SourceId('src.fssai.labelling.2020'),
            title: 'Labelling and Display Regulations',
            publisher: 'FSSAI',
            publicationDate: '2020-12-14',
            accessDate: '2026-08-04',
            sourceType: SourceType.regulation,
            evidenceStrength: EvidenceStrength.established,
          ),
        ]),
        synonyms: SynonymTable(<SynonymEntry>[
          SynonymEntry(
            nutrient: NutrientId.protein,
            patterns: <SynonymPattern>[
              const SynonymPattern(
                  text: 'Protein', strength: ParseStrength.exact),
            ],
            expectedUnits: <Unit>[Unit.gram],
          ),
        ]),
        rda: RdaTable(<RdaDenominator>[
          RdaDenominator(
            constantId: ConstantId('const.rda.sodium'),
            nutrient: NutrientId.sodium,
            value: const Quantity.exact(20000, Unit.milligram),
            sourceRefs: <SourceId>[SourceId('src.fssai.labelling.2020')],
          ),
        ]),
        categories: CategoryTable(<Category>[
          Category(
            categoryId: CategoryId('cat.biscuits'),
            nameMessageId: MessageId('msg.category.biscuits'),
            defaultBasis: Basis.per100g,
            status: CategoryStatus.priority,
          ),
        ]),
        advisoryRules: AdvisoryRuleTable(const <AdvisoryRule>[]),
        confidencePolicy: ConfidencePolicy.defaults,
        tolerances: ToleranceTable.defaults,
        approximationDeltas: ApproximationDeltas.none,
        messages: MessageCatalogue(
          locale: 'en',
          reviewed: true,
          messages: <MessageId, String>{
            MessageId('msg.category.biscuits'): 'Biscuits',
          },
        ),
      );

  group('RulePackManifest — the digest shape is checked at construction', () {
    test('a well-formed digest is accepted', () {
      expect(manifest().integrityHash, digest);
    });

    test('a malformed digest is refused, not stored', () {
      // A malformed digest stored as-is would produce a comparison that
      // quietly never matches — a refusal with no diagnosable cause.
      expect(() => manifest(hash: 'sha256:short'), throwsArgumentError);
      expect(() => manifest(hash: 'md5:${'a' * 64}'), throwsArgumentError);
      expect(() => manifest(hash: 'sha256:${'A' * 64}'), throwsArgumentError,
          reason: 'upper-case hex is not the canonical form');
      expect(() => manifest(hash: 'a' * 64), throwsArgumentError);
    });

    test('MI-07 generatedAt is a recorded string, not a clock value', () {
      expect(manifest().generatedAt, isA<String>());
    });

    test('ADR-0017 the content licence is separate from the code licence', () {
      expect(manifest().contentLicence, 'CC-BY-4.0');
    });

    test('P4 compares by value across every field', () {
      expect(manifest(), manifest());
      expect(manifest().hashCode, manifest().hashCode);
      expect(manifest(), isNot(manifest(pack: Version(0, 2, 0))));
      expect(manifest(), isNot(manifest(schema: Version(2, 0, 0))));
      expect(manifest(), isNot(manifest(minApp: Version(0, 2, 0))));
    });

    test('toString names both versions', () {
      expect(manifest().toString(), contains('0.1.0'));
      expect(manifest().toString(), contains('1.0.0'));
    });
  });

  group('RulePackManifest — ADR-0022, two independent checks', () {
    test('schema compatibility turns on the major alone', () {
      // Within a major, added fields are optional by construction, so a newer
      // minor is readable by an older reader.
      expect(manifest(schema: Version(1, 0, 0)).supportsSchema(1), isTrue);
      expect(manifest(schema: Version(1, 9, 3)).supportsSchema(1), isTrue);
      expect(manifest(schema: Version(2, 0, 0)).supportsSchema(1), isFalse);
      expect(manifest(schema: Version(0, 9, 0)).supportsSchema(1), isFalse);
    });

    test('application compatibility compares full versions', () {
      expect(
        manifest(minApp: Version(0, 1, 0)).acceptsApplication(Version(0, 1, 0)),
        isTrue,
        reason: 'exactly the minimum qualifies',
      );
      expect(
        manifest(minApp: Version(0, 1, 0)).acceptsApplication(Version(1, 0, 0)),
        isTrue,
      );
      expect(
        manifest(minApp: Version(0, 2, 0)).acceptsApplication(Version(0, 1, 9)),
        isFalse,
      );
    });

    test('ADR-0022 comparison is semantic, never lexicographic', () {
      // Lexicographically "1.10.0" precedes "1.9.0", and the failure mode is a
      // pack refusing to load for no visible reason.
      expect(
        manifest(minApp: Version(1, 9, 0))
            .acceptsApplication(Version(1, 10, 0)),
        isTrue,
      );
      expect(
        manifest(minApp: Version(1, 10, 0))
            .acceptsApplication(Version(1, 9, 0)),
        isFalse,
      );
    });

    test('the two checks are genuinely independent', () {
      // A pack can be readable but distrusted, or trusted but unreadable.
      // Collapsing them into one comparison is how a pack silently loads that
      // should not.
      final RulePackManifest m =
          manifest(schema: Version(2, 0, 0), minApp: Version(0, 1, 0));
      expect(m.supportsSchema(1), isFalse);
      expect(m.acceptsApplication(Version(9, 9, 9)), isTrue);

      final RulePackManifest n =
          manifest(schema: Version(1, 0, 0), minApp: Version(5, 0, 0));
      expect(n.supportsSchema(1), isTrue);
      expect(n.acceptsApplication(Version(0, 1, 0)), isFalse);
    });
  });

  group('RulePack — the eager segment, immutable once assembled', () {
    test('every eager segment is reachable', () {
      final RulePack p = pack();
      expect(p.sources.length, 1);
      expect(p.synonyms.entries, hasLength(1));
      expect(p.rda.length, 1);
      expect(p.categories.length, 1);
      expect(p.advisoryRules.isEmpty, isTrue);
      expect(p.messages.length, 1);
      expect(p.confidencePolicy.rules, isNotEmpty);
      expect(p.tolerances.forInvariant(InvariantId.inv01), isNotNull);
    });

    test('§9.2 the additive table is not part of the eager pack', () {
      // The largest segment, and a nutrition-only scan never needs it. Eager
      // loading would spend the 300 ms budget on data most scans discard.
      // Verified structurally: RulePack has no additive field to read.
      final RulePack p = pack();
      expect(p.toString(), isNot(contains('additive')));
    });

    test('FR-KB-02 the pack version is reachable without the manifest', () {
      expect(pack().version, Version(0, 1, 0));
      expect(pack().version, pack().manifest.packVersion);
    });

    test('FR-CNF-04 the confidence policy comes from the pack, not code', () {
      // The stage orchestrates; the policy decides, and the policy is data.
      expect(pack().confidencePolicy, isA<ConfidencePolicy>());
    });

    test('ADR-0027 the approximation deltas travel with the pack', () {
      expect(pack().approximationDeltas, isA<ApproximationDeltas>());
    });

    test('toString summarises the pack without dumping it', () {
      final String s = pack().toString();
      expect(s, contains('0.1.0'));
      expect(s, contains('1 sources'));
      expect(s, contains('1 categories'));
      expect(s, contains('0 rules'));
    });
  });
}
