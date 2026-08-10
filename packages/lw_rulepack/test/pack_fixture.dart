import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:lw_rulepack/lw_rulepack.dart';

/// Builds in-memory rule packs for tests.
///
/// **The digest is computed, never hard-coded.** A fixture carrying a literal
/// hash would have to be updated by hand every time a fixture file changed, and
/// the update everyone would forget is the one that makes the integrity test
/// vacuous. [pack] computes the correct digest by the same recipe the loader
/// uses; [corrupt] is how a test asks for a wrong one, explicitly.
final class PackFixture {
  const PackFixture._();

  /// A minimal pack whose every file is valid and whose digest is correct.
  ///
  /// [overrides] replace or add files after the defaults, before the digest is
  /// computed — so an overridden pack is still internally consistent unless the
  /// test asks otherwise.
  static InMemoryRulePackSource pack({
    Map<String, String> overrides = const <String, String>{},
    String? integrityHash,
    String schemaVersion = '{"major":1,"minor":0,"patch":0}',
    String packVersion = '{"major":0,"minor":1,"patch":0}',
    String minAppVersion = '{"major":0,"minor":1,"patch":0}',
    bool includeManifest = true,
  }) {
    final Map<String, String> files = <String, String>{
      ...defaults,
      ...overrides,
    };
    final String digest = integrityHash ?? computeDigest(files);
    if (includeManifest) {
      files['manifest.json'] = jsonEncode(<String, Object?>{
        'schemaVersion': jsonDecode(schemaVersion),
        'packVersion': jsonDecode(packVersion),
        'minAppVersion': jsonDecode(minAppVersion),
        'integrityHash': digest,
        'contentLicence': 'CC-BY-4.0',
        'generatedAt': '2026-08-04',
      });
    }
    return InMemoryRulePackSource.fromText(files);
  }

  /// A pack whose recorded digest is wrong.
  static InMemoryRulePackSource corrupt() =>
      pack(integrityHash: 'sha256:${'0' * 64}');

  /// The digest of [files], by the normative recipe of §7.2.
  ///
  /// Implemented here independently of the loader so that the integrity test
  /// compares two implementations rather than one against itself.
  static String computeDigest(Map<String, String> files) {
    final List<String> content =
        files.keys.where(PackPaths.isContentFile).toList()..sort();
    final List<int> buffer = <int>[];
    for (final String path in content) {
      buffer
        ..addAll(utf8.encode(path))
        ..addAll(utf8.encode(files[path]!));
    }
    return 'sha256:${sha256.convert(buffer)}';
  }

  /// The content files of a minimal, internally consistent pack.
  static const Map<String, String> defaults = <String, String>{
    'LICENSE': 'CC BY 4.0',
    'schema/common.schema.json': '{"\$defs":{}}',
    'sources.json': '''
{"sources":[
  {"sourceId":"src.fssai.labelling.2020",
   "title":"Labelling and Display Regulations",
   "publisher":"FSSAI","publicationDate":"2020-12-14",
   "accessDate":"2026-08-04","sourceType":"REGULATION",
   "evidenceStrength":"ESTABLISHED"}
]}''',
    'nutrients/synonyms.json': '''
{"entries":[
  {"nutrient":"PROTEIN",
   "patterns":[{"text":"Protein","strength":"EXACT"}],
   "expectedUnits":["GRAM"]}
]}''',
    'nutrients/rda.json': '''
{"denominators":[
  {"constantId":"const.rda.sodium","nutrient":"SODIUM",
   "value":{"scaledValue":20000,"unit":"MILLIGRAM"},
   "sourceRefs":["src.fssai.labelling.2020"]}
]}''',
    'rules/thresholds.json': '{"rules":[]}',
    'rules/confidence.json': '''
{"signalPriority":["S3_INVARIANTS","S2_PARSE_STRENGTH","S1_OCR"],
 "assignment":[
   {"when":{"anyInvariantFailed":true},"result":"LOW"},
   {"when":{"parseStrength":"EXACT"},"result":"HIGH"}
 ],
 "tolerances":[
   {"invariantId":"INV-01","mode":"EXACT",
    "calibrationBasis":"Non-negativity admits no tolerance."},
   {"invariantId":"INV-02","mode":"ABSOLUTE",
    "absoluteFloor":{"scaledValue":10,"unit":"GRAM"},
    "calibrationBasis":"Absorbs independent rounding."},
   {"invariantId":"INV-07","mode":"RELATIVE_WITH_FLOOR",
    "relativeFraction":0.15,
    "absoluteFloor":{"scaledValue":200,"unit":"KILOCALORIE"},
    "calibrationBasis":"Atwater is a model, not an identity."}
 ],
 "approximationDeltas":[
   {"unit":"COUNT","delta":{"scaledValue":50,"unit":"COUNT"},
    "basis":"Half a serving."}
 ]}''',
    'additives/ins.json': '''
{"additives":[
  {"insNumber":100,"commonName":"Curcumin",
   "alternateNames":["Turmeric yellow"],
   "functionalClass":"COLOUR",
   "descriptionMessageId":"msg.additive.ins-100",
   "evidenceStrength":"ESTABLISHED",
   "sourceRefs":["src.fssai.labelling.2020"],
   "indianPermission":{"status":"PERMITTED","evidence":[
     {"sourceRef":"src.fssai.labelling.2020",
      "scheduleRef":"Appendix A, Table 1, section G.a, item 3",
      "entryName":"Curcumin or turmeric",
      "foodProducts":"Biscuits","limit":"GMP"}]}},
  {"insNumber":322,"commonName":"Lecithin",
   "functionalClass":"EMULSIFIER",
   "descriptionMessageId":"msg.additive.ins-322",
   "evidenceStrength":"ESTABLISHED",
   "sourceRefs":["src.fssai.labelling.2020"],
   "indianPermission":{"status":"UNKNOWN"}}
]}''',
    'categories/categories.json': '''
{"categories":[
  {"categoryId":"cat.biscuits","nameMessageId":"msg.category.biscuits",
   "defaultBasis":"PER_100G","status":"PRIORITY"},
  {"categoryId":"cat.beverages","nameMessageId":"msg.category.beverages",
   "defaultBasis":"PER_100ML","status":"VERIFICATION_ONLY",
   "inapplicableInvariants":["INV-06"]}
]}''',
    'messages/en.json': '''
{"locale":"en","reviewed":true,"messages":{
  "msg.category.biscuits":"Biscuits",
  "msg.category.beverages":"Packaged beverages",
  "msg.additive.ins-100":"A yellow colour taken from turmeric.",
  "msg.additive.ins-322":"An emulsifier that keeps oil and water mixed."
}}''',
  };
}
