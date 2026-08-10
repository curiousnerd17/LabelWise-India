import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/lw_rulepack.dart';
import 'package:test/test.dart';

import 'pack_fixture.dart';

void main() {
  RulePackLoader loaderFor(
    RulePackSource source, {
    int schemaMajor = 1,
    Version? app,
    String locale = 'en',
  }) =>
      RulePackLoader(
        source: source,
        implementedSchemaMajor: schemaMajor,
        applicationVersion: app ?? Version(0, 1, 0),
        locale: locale,
      );

  Future<RulePack> loadOk(RulePackSource s) async {
    final RulePackResult<RulePack> r = await loaderFor(s).load();
    expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
    return r.valueOrNull!;
  }

  Future<RulePackFailure> loadFail(
    RulePackSource s, {
    int schemaMajor = 1,
    Version? app,
    String locale = 'en',
  }) async {
    final RulePackResult<RulePack> r = await loaderFor(
      s,
      schemaMajor: schemaMajor,
      app: app,
      locale: locale,
    ).load();
    expect(r.isSuccess, isFalse, reason: 'expected rejection');
    return r.failureOrNull!;
  }

  group('Loader — the happy path assembles every eager segment', () {
    test('FR-KB-08 a valid pack loads with no network and no file system',
        () async {
      final RulePack p = await loadOk(PackFixture.pack());
      expect(p.manifest.packVersion, Version(0, 1, 0));
      expect(p.sources.length, 1);
      expect(p.synonyms.entries, hasLength(1));
      expect(p.rda.length, 1);
      expect(p.categories.length, 2);
      expect(p.advisoryRules.isEmpty, isTrue);
      expect(p.messages.length, 4);
    });

    test('FR-KB-02 the pack version is carried for every finding', () async {
      expect((await loadOk(PackFixture.pack())).version, Version(0, 1, 0));
    });

    test('S5 the synonym table arrives usable, not raw', () async {
      final RulePack p = await loadOk(PackFixture.pack());
      final SynonymMatch? m = p.synonyms.match('Protein');
      expect(m, isNotNull);
      expect(m!.nutrient, NutrientId.protein);
      expect(m.pattern.strength, ParseStrength.exact);
    });

    test('FR-CAT-04 inapplicable invariants survive decoding', () async {
      // The selector that removes INV-06 from beverages with no code branch.
      final RulePack p = await loadOk(PackFixture.pack());
      final Category beverages = p.categories[CategoryId('cat.beverages')]!;
      expect(beverages.excludes(InvariantId.inv06), isTrue);
      expect(beverages.status, CategoryStatus.verificationOnly);
      expect(beverages.defaultBasis, Basis.per100ml);
    });

    test('ADR-0010 the assignment table keeps pack order', () async {
      // First match wins, and the failed-invariant rule is first so FR-CNF-05
      // holds absolutely. Reordering would silently break that guarantee.
      final RulePack p = await loadOk(PackFixture.pack());
      expect(p.confidencePolicy.rules.first.anyInvariantFailed, isTrue);
      expect(p.confidencePolicy.rules.first.result, Confidence.low);
      expect(p.confidencePolicy.rules[1].parseStrength, ParseStrength.exact);
    });

    test('S7 tolerances arrive in base units', () async {
      final RulePack p = await loadOk(PackFixture.pack());
      expect(p.tolerances.forInvariant(InvariantId.inv01),
          const Tolerance.exact());
      // 10 increments of GRAM = 0.1 g = 100 000 micrograms.
      expect(p.tolerances.forInvariant(InvariantId.inv02),
          Tolerance.grace(100000));
      expect(
        p.tolerances.forInvariant(InvariantId.inv07),
        Tolerance.relative(percentTenths: 150, floorBaseUnits: 83680000),
      );
    });

    test('ADR-0027 approximation deltas arrive in base units', () async {
      final RulePack p = await loadOk(PackFixture.pack());
      expect(p.approximationDeltas.hasDeltaFor(Unit.count), isTrue);
      expect(p.approximationDeltas.deltaFor(Unit.count), 50);
      expect(p.approximationDeltas.hasDeltaFor(Unit.gram), isFalse);
    });

    test('FR-PAR-02 loading is deterministic', () async {
      final InMemoryRulePackSource s = PackFixture.pack();
      final RulePack a = await loadOk(s);
      final RulePack b = await loadOk(s);
      expect(a.manifest, b.manifest);
      expect(a.toString(), b.toString());
    });
  });

  group('Loader — compatibility, two independent checks (ADR-0022)', () {
    test('a newer schema major is refused explicitly', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(schemaVersion: '{"major":2,"minor":0,"patch":0}'),
      );
      expect(f.kind, RulePackFailureKind.schemaVersionUnsupported);
      expect(f.file, 'manifest.json');
      expect(f.detail, contains('2.0.0'));
    });

    test('a newer schema MINOR is accepted', () async {
      // Within a major, added fields are optional by construction, so an older
      // reader can still read a newer pack.
      final RulePack p = await loadOk(
        PackFixture.pack(schemaVersion: '{"major":1,"minor":9,"patch":3}'),
      );
      expect(p.manifest.schemaVersion, Version(1, 9, 3));
    });

    test('an application older than minAppVersion is refused', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(minAppVersion: '{"major":2,"minor":0,"patch":0}'),
        app: Version(1, 9, 9),
      );
      expect(f.kind, RulePackFailureKind.appVersionTooOld);
      expect(f.detail, contains('2.0.0'));
    });

    test('exactly minAppVersion is accepted', () async {
      final RulePackResult<RulePack> r = await loaderFor(
        PackFixture.pack(minAppVersion: '{"major":1,"minor":0,"patch":0}'),
        app: Version(1, 0, 0),
      ).load();
      expect(r.isSuccess, isTrue, reason: 'the minimum itself qualifies');
    });

    test('ADR-0022 comparison is semantic, not lexicographic', () async {
      // "1.10.0" precedes "1.9.0" as a string. A pack requiring 1.9.0 must
      // load into build 1.10.0.
      final RulePackResult<RulePack> r = await loaderFor(
        PackFixture.pack(minAppVersion: '{"major":1,"minor":9,"patch":0}'),
        app: Version(1, 10, 0),
      ).load();
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
    });

    test('schema refusal is reported before an integrity mismatch', () async {
      // A pack we cannot interpret should say so, rather than first reporting
      // a digest problem that tells the user nothing about the real cause.
      final RulePackFailure f = await loadFail(
        PackFixture.pack(
          schemaVersion: '{"major":9,"minor":0,"patch":0}',
          integrityHash: 'sha256:${'0' * 64}',
        ),
      );
      expect(f.kind, RulePackFailureKind.schemaVersionUnsupported);
    });
  });

  group('Loader — integrity (FR-ERR-06)', () {
    test('a tampered pack is refused, with no partial load', () async {
      final RulePackResult<RulePack> r =
          await loaderFor(PackFixture.corrupt()).load();
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.integrityMismatch);
      expect(r.valueOrNull, isNull,
          reason: 'there is no fallback to unvalidated data');
    });

    test('an edited content file is detected', () async {
      final RulePackFixtureEdit edit = RulePackFixtureEdit();
      final RulePackFailure f = await loadFail(edit.editedAfterHashing());
      expect(f.kind, RulePackFailureKind.integrityMismatch);
      expect(f.detail, contains('computed'));
    });

    test('a malformed digest in the manifest is a schema violation', () async {
      // Distinct from a mismatch: the manifest itself is wrong, and reporting
      // a mismatch would send a contributor looking at the content files.
      final RulePackFailure f =
          await loadFail(PackFixture.pack(integrityHash: 'sha256:nope'));
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.file, 'manifest.json');
    });
  });

  group('Loader — source and format failures', () {
    test('a missing manifest is packMissing, not a crash', () async {
      final RulePackFailure f =
          await loadFail(PackFixture.pack(includeManifest: false));
      expect(f.kind, RulePackFailureKind.packMissing);
      expect(f.file, 'manifest.json');
    });

    test('a missing catalogue for the requested locale is packMissing',
        () async {
      final RulePackFailure f =
          await loadFail(PackFixture.pack(), locale: 'hi');
      expect(f.kind, RulePackFailureKind.packMissing);
      expect(f.file, 'messages/hi.json');
    });

    test('unreadable JSON is distinguished from readable-and-wrong', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(
            overrides: <String, String>{'sources.json': '{ not json'}),
      );
      expect(f.kind, RulePackFailureKind.malformedJson);
      expect(f.file, 'sources.json');
    });

    test('a wrong type is a positioned schema violation', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(overrides: <String, String>{
          'nutrients/rda.json': '''
{"denominators":[
  {"constantId":"const.rda.sodium","nutrient":"SODIUM",
   "value":{"scaledValue":"twenty","unit":"MILLIGRAM"},
   "sourceRefs":["src.fssai.labelling.2020"]}
]}''',
        }),
      );
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.file, 'nutrients/rda.json');
      expect(f.pointer, contains('scaledValue'));
      expect(f.detail, contains('integer'));
    });

    test('an unknown enum member is refused, never defaulted', () async {
      // A silent default would turn a new pack value into an old behaviour,
      // which is the hardest kind of version skew to notice.
      final RulePackFailure f = await loadFail(
        PackFixture.pack(overrides: <String, String>{
          'nutrients/rda.json': '''
{"denominators":[
  {"constantId":"const.rda.sodium","nutrient":"VITAMIN_Q",
   "value":{"scaledValue":20000,"unit":"MILLIGRAM"},
   "sourceRefs":["src.fssai.labelling.2020"]}
]}''',
        }),
      );
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.detail, contains('VITAMIN_Q'));
    });

    test('a malformed identifier is refused at the boundary', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(overrides: <String, String>{
          'categories/categories.json': '''
{"categories":[
  {"categoryId":"cat.instant_noodles",
   "nameMessageId":"msg.category.biscuits",
   "defaultBasis":"PER_100G","status":"PRIORITY"}
]}''',
        }),
      );
      // Underscore is not the canonical separator; the schema was tightened to
      // match the domain in DATA_MODEL v1.7, and the loader agrees with both.
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.detail, contains('cat.instant_noodles'));
    });

    test('a duplicate key is its own failure kind', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(overrides: <String, String>{
          'nutrients/rda.json': '''
{"denominators":[
  {"constantId":"const.rda.sodium","nutrient":"SODIUM",
   "value":{"scaledValue":20000,"unit":"MILLIGRAM"},
   "sourceRefs":["src.fssai.labelling.2020"]},
  {"constantId":"const.rda.sodium2","nutrient":"SODIUM",
   "value":{"scaledValue":24000,"unit":"MILLIGRAM"},
   "sourceRefs":["src.fssai.labelling.2020"]}
]}''',
        }),
      );
      expect(f.kind, RulePackFailureKind.duplicateKey);
    });

    test('FR-LOC-04 an unreviewed Hindi catalogue is refused', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(overrides: <String, String>{
          'messages/hi.json':
              '{"locale":"hi","reviewed":false,"messages":{"msg.a":"क"}}',
        }),
        locale: 'hi',
      );
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.file, 'messages/hi.json');
    });
  });

  group('Loader — MI-05, references resolve inside the pack', () {
    test('a dangling sourceRef is refused', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(overrides: <String, String>{
          'nutrients/rda.json': '''
{"denominators":[
  {"constantId":"const.rda.sodium","nutrient":"SODIUM",
   "value":{"scaledValue":20000,"unit":"MILLIGRAM"},
   "sourceRefs":["src.does.not.exist"]}
]}''',
        }),
      );
      expect(f.kind, RulePackFailureKind.danglingReference);
      expect(f.file, 'nutrients/rda.json');
      expect(f.detail, contains('src.does.not.exist'));
    });

    test('a dangling category messageId is refused', () async {
      final RulePackFailure f = await loadFail(
        PackFixture.pack(overrides: <String, String>{
          'categories/categories.json': '''
{"categories":[
  {"categoryId":"cat.biscuits","nameMessageId":"msg.nowhere",
   "defaultBasis":"PER_100G","status":"PRIORITY"}
]}''',
        }),
      );
      expect(f.kind, RulePackFailureKind.danglingReference);
      expect(f.file, 'categories/categories.json');
      expect(f.detail, contains('msg.nowhere'));
    });
  });

  group('Loader — §9.2 the additive segment is deferred', () {
    test('the eager load does not decode additives', () async {
      // Structural: RulePack carries no additive table, so a nutrition-only
      // scan cannot have paid for one.
      final RulePack p = await loadOk(PackFixture.pack());
      expect(p.toString(), isNot(contains('additive')));
    });

    test('additives decode on demand, keyed by INS number', () async {
      final RulePackResult<AdditiveTable> r =
          await loaderFor(PackFixture.pack()).loadAdditives();
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      final AdditiveTable t = r.valueOrNull!;
      expect(t.length, 2);
      expect(t[InsNumber(100)]!.commonName, 'Curcumin');
      expect(t[InsNumber(100)]!.alternateNames, <String>['Turmeric yellow']);
      expect(t[InsNumber(322)]!.functionalClass, FunctionalClass.emulsifier);
    });

    test('P1 UNKNOWN permission carries no fabricated evidence', () async {
      final AdditiveTable t =
          (await loaderFor(PackFixture.pack()).loadAdditives()).valueOrNull!;
      final IndianPermission p = t[InsNumber(322)]!.indianPermission;
      expect(p.status, PermissionStatus.unknown);
      expect(p.evidence, isEmpty);
    });

    test('a PERMITTED record carries its citation', () async {
      final AdditiveTable t =
          (await loaderFor(PackFixture.pack()).loadAdditives()).valueOrNull!;
      final IndianPermission p = t[InsNumber(100)]!.indianPermission;
      expect(p.status, PermissionStatus.permitted);
      expect(p.evidence.single.entryName, 'Curcumin or turmeric');
      expect(p.evidence.single.foodProducts, 'Biscuits');
      expect(p.evidence.single.limit, 'GMP');
    });

    test('FR-KB-04 PERMITTED with no evidence is refused', () async {
      final RulePackResult<AdditiveTable> r = await loaderFor(
        PackFixture.pack(overrides: <String, String>{
          'additives/ins.json': '''
{"additives":[
  {"insNumber":100,"commonName":"Curcumin","functionalClass":"COLOUR",
   "descriptionMessageId":"msg.additive.ins-100",
   "evidenceStrength":"ESTABLISHED",
   "sourceRefs":["src.fssai.labelling.2020"],
   "indianPermission":{"status":"PERMITTED"}}
]}''',
        }),
      ).loadAdditives();
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
      expect(r.failureOrNull!.file, 'additives/ins.json');
    });

    test('a duplicate INS number is refused', () async {
      final RulePackResult<AdditiveTable> r = await loaderFor(
        PackFixture.pack(overrides: <String, String>{
          'additives/ins.json': '''
{"additives":[
  {"insNumber":100,"commonName":"A","functionalClass":"COLOUR",
   "descriptionMessageId":"msg.additive.ins-100",
   "evidenceStrength":"ESTABLISHED",
   "sourceRefs":["src.fssai.labelling.2020"],
   "indianPermission":{"status":"UNKNOWN"}},
  {"insNumber":100,"commonName":"B","functionalClass":"COLOUR",
   "descriptionMessageId":"msg.additive.ins-100",
   "evidenceStrength":"ESTABLISHED",
   "sourceRefs":["src.fssai.labelling.2020"],
   "indianPermission":{"status":"UNKNOWN"}}
]}''',
        }),
      ).loadAdditives();
      expect(r.failureOrNull!.kind, RulePackFailureKind.duplicateKey);
    });

    test('a missing additive file is packMissing, not a crash', () async {
      final Map<String, String> withoutAdditives =
          Map<String, String>.from(PackFixture.defaults)
            ..remove('additives/ins.json');
      final RulePackResult<AdditiveTable> r = await RulePackLoader(
        source: InMemoryRulePackSource.fromText(withoutAdditives),
        implementedSchemaMajor: 1,
        applicationVersion: Version(0, 1, 0),
      ).loadAdditives();
      expect(r.failureOrNull!.kind, RulePackFailureKind.packMissing);
      expect(r.failureOrNull!.file, 'additives/ins.json');
    });
  });
}

/// Produces a pack whose bytes changed after its digest was recorded.
final class RulePackFixtureEdit {
  /// A pack whose manifest records the digest of the *unedited* files.
  InMemoryRulePackSource editedAfterHashing() {
    final String honestDigest = PackFixture.computeDigest(PackFixture.defaults);
    return PackFixture.pack(
      overrides: <String, String>{
        'sources.json': PackFixture.defaults['sources.json']!
            .replaceAll('FSSAI', 'Somebody else'),
      },
      integrityHash: honestDigest,
    );
  }
}
