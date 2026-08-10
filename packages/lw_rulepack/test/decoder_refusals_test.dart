import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/lw_rulepack.dart';
import 'package:test/test.dart';

import 'pack_fixture.dart';

/// The refusal paths of the eager decoders.
///
/// Every case here is a pack that is well-formed JSON and passes the shape
/// checks, but that a **domain type refuses to represent**: a duplicate key, a
/// citation-free record, a negative version. Those refusals arrive as
/// `ArgumentError` from the domain and must leave the loader as a positioned
/// `RulePackFailure` — a throw escaping here would break the port contract that
/// nothing throws for an expected condition.
///
/// CI validates the shipped pack, so none of this can happen to a pack CI has
/// seen. It happens to a pack edited afterwards, which is exactly the case
/// FR-ERR-06 exists for.
void main() {
  Future<RulePackFailure> reject(Map<String, String> overrides,
      {String locale = 'en'}) async {
    final RulePackResult<RulePack> r = await RulePackLoader(
      source: PackFixture.pack(overrides: overrides),
      implementedSchemaMajor: 1,
      applicationVersion: Version(0, 1, 0),
      locale: locale,
    ).load();
    expect(r.isSuccess, isFalse, reason: 'expected a rejection');
    return r.failureOrNull!;
  }

  Future<RulePack> accept(Map<String, String> overrides) async {
    final RulePackResult<RulePack> r = await RulePackLoader(
      source: PackFixture.pack(overrides: overrides),
      implementedSchemaMajor: 1,
      applicationVersion: Version(0, 1, 0),
    ).load();
    expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
    return r.valueOrNull!;
  }

  group('manifest — a malformed version is a version failure', () {
    test('a negative version component is refused at its own field', () async {
      // Version rejects this itself. The value of the test is *where* the
      // failure points: a catch wide enough to include the version decode
      // would report this as a bad integrity hash and send a contributor to
      // entirely the wrong field.
      final RulePackResult<RulePack> r = await RulePackLoader(
        source: PackFixture.pack(
          schemaVersion: '{"major":-1,"minor":0,"patch":0}',
        ),
        implementedSchemaMajor: 1,
        applicationVersion: Version(0, 1, 0),
      ).load();
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
      expect(r.failureOrNull!.file, 'manifest.json');
      expect(r.failureOrNull!.pointer, contains('schemaVersion'));
      expect(r.failureOrNull!.detail, isNot(contains('sha256')));
    });
  });

  group('sources — the registry refuses a duplicate key', () {
    test('two entries under one sourceId are refused', () async {
      // Two entries under one key make every citation mean "whichever came
      // first" — a silent choice, and silent choices about evidence are the
      // worst kind.
      final RulePackFailure f = await reject(<String, String>{
        'sources.json': '''
{"sources":[
  {"sourceId":"src.fssai.labelling.2020","title":"A","publisher":"B",
   "publicationDate":"2020-12-14","accessDate":"2026-08-04",
   "sourceType":"REGULATION","evidenceStrength":"ESTABLISHED"},
  {"sourceId":"src.fssai.labelling.2020","title":"C","publisher":"D",
   "publicationDate":"2021-01-01","accessDate":"2026-08-04",
   "sourceType":"REGULATION","evidenceStrength":"LIMITED"}
]}''',
      });
      expect(f.kind, RulePackFailureKind.duplicateKey);
      expect(f.file, 'sources.json');
    });
  });

  group('synonyms — S5 wordings must be unambiguous', () {
    test('an entry with no wording is refused', () async {
      // A nutrient no wording can reach is unreachable content.
      final RulePackFailure f = await reject(<String, String>{
        'nutrients/synonyms.json':
            '{"entries":[{"nutrient":"PROTEIN","patterns":[],'
                '"expectedUnits":["GRAM"]}]}',
      });
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.file, 'nutrients/synonyms.json');
    });

    test('one wording claimed by two nutrients is refused', () async {
      // A wording resolving to whichever entry came first would be a silent
      // misreading of the panel — the worst outcome S5 can produce.
      final RulePackFailure f = await reject(<String, String>{
        'nutrients/synonyms.json': '''
{"entries":[
  {"nutrient":"PROTEIN","patterns":[{"text":"Protein","strength":"EXACT"}],
   "expectedUnits":["GRAM"]},
  {"nutrient":"TOTAL_FAT","patterns":[{"text":"Protein","strength":"EXACT"}],
   "expectedUnits":["GRAM"]}
]}''',
      });
      expect(f.kind, RulePackFailureKind.duplicateKey);
      expect(f.file, 'nutrients/synonyms.json');
    });

    test('FR-KB-12 caseSensitive is honoured when a contributor sets it',
        () async {
      // Defaults to false so ENERGY and energy resolve without two patterns.
      // A contributor who needs the distinction states it, and the flag must
      // survive decoding or their entry silently does nothing.
      final RulePack p = await accept(<String, String>{
        'nutrients/synonyms.json': '''
{"entries":[
  {"nutrient":"PROTEIN","patterns":[
     {"text":"Protein","strength":"EXACT","caseSensitive":true}],
   "expectedUnits":["GRAM"]}
]}''',
      });
      final SynonymPattern pattern = p.synonyms.entries.single.patterns.single;
      expect(pattern.caseSensitive, isTrue);
      expect(p.synonyms.match('Protein'), isNotNull);
    });
  });

  group('rda — a gazetted constant needs a citation', () {
    test('a denominator with no sourceRefs is refused', () async {
      // A constant with no source is indistinguishable from a number somebody
      // remembered.
      final RulePackFailure f = await reject(<String, String>{
        'nutrients/rda.json': '''
{"denominators":[
  {"constantId":"const.rda.sodium","nutrient":"SODIUM",
   "value":{"scaledValue":20000,"unit":"MILLIGRAM"},"sourceRefs":[]}
]}''',
      });
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.file, 'nutrients/rda.json');
    });
  });

  group('categories — FR-CAT-03 adding one is a data change', () {
    test('two categories under one identifier are refused', () async {
      final RulePackFailure f = await reject(<String, String>{
        'categories/categories.json': '''
{"categories":[
  {"categoryId":"cat.biscuits","nameMessageId":"msg.category.biscuits",
   "defaultBasis":"PER_100G","status":"PRIORITY"},
  {"categoryId":"cat.biscuits","nameMessageId":"msg.category.biscuits",
   "defaultBasis":"PER_100ML","status":"SUPPORTED"}
]}''',
      });
      expect(f.kind, RulePackFailureKind.duplicateKey);
      expect(f.file, 'categories/categories.json');
    });
  });

  group('messages — B8, the identifier is the key', () {
    test('a malformed message key is refused', () async {
      // Validating the key is what stops a malformed id reaching a lookup that
      // would simply never match — a message that silently never resolves.
      final RulePackFailure f = await reject(<String, String>{
        'messages/en.json':
            '{"locale":"en","reviewed":true,"messages":{"biscuits":"B"}}',
      });
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.file, 'messages/en.json');
      expect(f.detail, contains('biscuits'));
    });

    test('FR-LOC-04 reviewedBy is carried when recorded', () async {
      // Review is a shipping condition for a non-English catalogue, and the
      // attribution is the record of who discharged it.
      final RulePack p = await accept(<String, String>{
        'messages/en.json': '''
{"locale":"en","reviewed":true,"reviewedBy":"A reviewer","messages":{
  "msg.category.biscuits":"Biscuits",
  "msg.category.beverages":"Packaged beverages"
}}''',
      });
      expect(p.messages.reviewedBy, 'A reviewer');
      expect(p.messages.reviewed, isTrue);
    });
  });

  group('confidence — a band the domain will not represent', () {
    test('a negative absolute floor is refused', () async {
      // An allowance that tightened the comparison would make a correct
      // declaration fail, so Tolerance refuses it and the loader reports it.
      final RulePackFailure f = await reject(<String, String>{
        'rules/confidence.json': '''
{"signalPriority":["S3_INVARIANTS","S2_PARSE_STRENGTH","S1_OCR"],
 "assignment":[{"when":{"parseStrength":"EXACT"},"result":"HIGH"}],
 "tolerances":[
   {"invariantId":"INV-02","mode":"ABSOLUTE",
    "absoluteFloor":{"scaledValue":-10,"unit":"GRAM"},
    "calibrationBasis":"Deliberately negative."}
 ],
 "approximationDeltas":[]}''',
      });
      expect(f.kind, RulePackFailureKind.schemaViolation);
      expect(f.file, 'rules/confidence.json');
    });
  });

  group('additives — the INS key must be a plausible number', () {
    test('an INS number outside the series is refused', () async {
      // Zero is what a misread produces, and an additive table keyed on it
      // would answer lookups nothing on a label can ask.
      final RulePackResult<AdditiveTable> r = await RulePackLoader(
        source: PackFixture.pack(overrides: <String, String>{
          'additives/ins.json': '''
{"additives":[
  {"insNumber":0,"commonName":"Nothing","functionalClass":"COLOUR",
   "descriptionMessageId":"msg.additive.ins-100",
   "evidenceStrength":"ESTABLISHED",
   "sourceRefs":["src.fssai.labelling.2020"],
   "indianPermission":{"status":"UNKNOWN"}}
]}''',
        }),
        implementedSchemaMajor: 1,
        applicationVersion: Version(0, 1, 0),
      ).loadAdditives();
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
      expect(r.failureOrNull!.file, 'additives/ins.json');
    });
  });
}
