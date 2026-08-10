import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/lw_rulepack.dart';
import 'package:test/test.dart';

import 'pack_fixture.dart';

void main() {
  Future<RulePackResult<RulePack>> loadWithConfidence(String json) =>
      RulePackLoader(
        source: PackFixture.pack(
          overrides: <String, String>{'rules/confidence.json': json},
        ),
        implementedSchemaMajor: 1,
        applicationVersion: Version(0, 1, 0),
      ).load();

  String confidenceJson(String tolerances,
          {String deltas = '''
   {"unit":"COUNT","delta":{"scaledValue":50,"unit":"COUNT"},
    "basis":"Half a serving."}'''}) =>
      '''
{"signalPriority":["S3_INVARIANTS","S2_PARSE_STRENGTH","S1_OCR"],
 "assignment":[{"when":{"parseStrength":"EXACT"},"result":"HIGH"}],
 "tolerances":[$tolerances],
 "approximationDeltas":[$deltas]}''';

  group('relativeFraction — exact conversion or refusal (D1)', () {
    test('the three shipped fractions convert exactly', () async {
      // 0.15, 0.05 and 0.1 are all exactly representable as tenths of a
      // percent once scaled, which is why the shipped pack loads.
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-07","mode":"RELATIVE_WITH_FLOOR",
    "relativeFraction":0.15,
    "absoluteFloor":{"scaledValue":200,"unit":"KILOCALORIE"},
    "calibrationBasis":"Atwater is a model, not an identity."},
   {"invariantId":"INV-08","mode":"RELATIVE_WITH_FLOOR",
    "relativeFraction":0.05,
    "absoluteFloor":{"scaledValue":10,"unit":"GRAM"},
    "calibrationBasis":"Serving arithmetic rounding."},
   {"invariantId":"INV-10","mode":"RELATIVE_WITH_FLOOR",
    "relativeFraction":0.1,
    "absoluteFloor":{"scaledValue":50,"unit":"COUNT"},
    "calibrationBasis":"Servings per pack rounding."}'''));
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      final ToleranceTable t = r.valueOrNull!.tolerances;
      expect(t.forInvariant(InvariantId.inv07),
          Tolerance.relative(percentTenths: 150, floorBaseUnits: 83680000));
      expect(t.forInvariant(InvariantId.inv08),
          Tolerance.relative(percentTenths: 50, floorBaseUnits: 100000));
      expect(t.forInvariant(InvariantId.inv10),
          Tolerance.relative(percentTenths: 100, floorBaseUnits: 50));
    });

    test('an inexact fraction is REFUSED, never rounded', () async {
      // The ruling that matters most in this file. 0.1234 would round to 12.3%
      // and the pack would still read 0.1234 — a band silently widened by
      // rounding accepts the very error it exists to catch.
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-07","mode":"RELATIVE",
    "relativeFraction":0.1234,
    "calibrationBasis":"Deliberately inexact."}'''));
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.unrepresentableValue);
      expect(r.failureOrNull!.file, 'rules/confidence.json');
      expect(r.failureOrNull!.detail, contains('tenths of a percent'));
    });

    test('a fraction finer than a tenth of a percent is refused', () async {
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-07","mode":"RELATIVE",
    "relativeFraction":0.00005,
    "calibrationBasis":"Finer than the representation allows."}'''));
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.unrepresentableValue);
    });

    test('an integral fraction is accepted', () async {
      // 1 means 100 per cent. A whole number arrives from JSON as an int and
      // must convert as cleanly as a decimal does.
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-07","mode":"RELATIVE",
    "relativeFraction":1,
    "calibrationBasis":"A whole-number fraction."}'''));
      expect(r.isSuccess, isTrue, reason: '${r.failureOrNull}');
      expect(
        r.valueOrNull!.tolerances.forInvariant(InvariantId.inv07),
        Tolerance.relative(percentTenths: 1000, floorBaseUnits: 0),
      );
    });

    test('a negative fraction is refused', () async {
      // An allowance that tightened the comparison would make a correct
      // declaration fail.
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-07","mode":"RELATIVE",
    "relativeFraction":-0.1,
    "calibrationBasis":"Negative."}'''));
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
    });
  });

  group('tolerance modes', () {
    test('EXACT admits no allowance', () async {
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-01","mode":"EXACT",
    "calibrationBasis":"Non-negativity admits no tolerance."}'''));
      expect(r.valueOrNull!.tolerances.forInvariant(InvariantId.inv01),
          const Tolerance.exact());
    });

    test('ABSOLUTE converts the floor quantity to base units', () async {
      // 10 increments of GRAM is 0.1 g, which is 100 000 micrograms.
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-02","mode":"ABSOLUTE",
    "absoluteFloor":{"scaledValue":10,"unit":"GRAM"},
    "calibrationBasis":"Absorbs independent rounding."}'''));
      expect(r.valueOrNull!.tolerances.forInvariant(InvariantId.inv02),
          Tolerance.grace(100000));
    });

    test('RELATIVE without a floor is a zero floor, not a missing one',
        () async {
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-07","mode":"RELATIVE","relativeFraction":0.15,
    "calibrationBasis":"No floor stated."}'''));
      expect(
        r.valueOrNull!.tolerances.forInvariant(InvariantId.inv07),
        Tolerance.relative(percentTenths: 150, floorBaseUnits: 0),
      );
    });

    test('an unknown mode is refused, never treated as EXACT', () async {
      // Defaulting to EXACT would silently tighten a band; defaulting to a
      // wide one would silently disable a check. Neither is acceptable.
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-01","mode":"GENEROUS",
    "calibrationBasis":"Not a mode."}'''));
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
      expect(r.failureOrNull!.detail, contains('GENEROUS'));
    });

    test('two bands for one invariant are refused', () async {
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-01","mode":"EXACT",
    "calibrationBasis":"First band."},
   {"invariantId":"INV-01","mode":"EXACT",
    "calibrationBasis":"Second band."}'''));
      expect(r.failureOrNull!.kind, RulePackFailureKind.duplicateKey);
    });

    test('an unknown invariant code is refused', () async {
      final RulePackResult<RulePack> r =
          await loadWithConfidence(confidenceJson('''
   {"invariantId":"INV-99","mode":"EXACT",
    "calibrationBasis":"No such invariant."}'''));
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
      expect(r.failureOrNull!.detail, contains('INV-99'));
    });
  });

  group('approximation deltas', () {
    test('a delta stated in the wrong unit is refused', () async {
      // A gram delta written in millilitres would produce a band three orders
      // of magnitude wrong, and nothing downstream could notice.
      final RulePackResult<RulePack> r = await loadWithConfidence(
        confidenceJson(
          '''
   {"invariantId":"INV-01","mode":"EXACT",
    "calibrationBasis":"Non-negativity admits no tolerance."}''',
          deltas: '''
   {"unit":"GRAM","delta":{"scaledValue":100,"unit":"MILLILITRE"},
    "basis":"Mismatched unit."}''',
        ),
      );
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
      // The diagnostic speaks the vocabulary of the schema, because the person
      // who must fix this is reading JSON, not Dart. A message saying
      // "millilitre" where the file says "MILLILITRE" sends a contributor
      // hunting for a line that is not there.
      expect(r.failureOrNull!.detail, contains('MILLILITRE'));
      expect(r.failureOrNull!.detail, contains('GRAM'));
      // Both spellings appear, so pin the direction too: the keyed unit is
      // named first, the delta's own unit second. Reversed, the message would
      // point at the wrong field.
      expect(
          r.failureOrNull!.detail, 'Delta for GRAM is stated in MILLILITRE.');
      expect(r.failureOrNull!.detail, isNot(contains('millilitre')));
    });

    test('two deltas for one unit are refused', () async {
      final RulePackResult<RulePack> r = await loadWithConfidence(
        confidenceJson(
          '''
   {"invariantId":"INV-01","mode":"EXACT",
    "calibrationBasis":"Non-negativity admits no tolerance."}''',
          deltas: '''
   {"unit":"GRAM","delta":{"scaledValue":100,"unit":"GRAM"},
    "basis":"First."},
   {"unit":"GRAM","delta":{"scaledValue":200,"unit":"GRAM"},
    "basis":"Second."}''',
        ),
      );
      expect(r.failureOrNull!.kind, RulePackFailureKind.duplicateKey);
      // The same contract as above, on the other diagnostic in this decoder.
      expect(r.failureOrNull!.detail, contains('GRAM'));
      expect(r.failureOrNull!.detail, isNot(contains('gram')));
    });
  });

  group('assignment table', () {
    test('a rule with no condition is refused', () async {
      // It would match everything and shadow every rule after it — the failure
      // an ordered first-match table is most prone to.
      final RulePackResult<RulePack> r = await RulePackLoader(
        source: PackFixture.pack(overrides: <String, String>{
          'rules/confidence.json': '''
{"signalPriority":["S3_INVARIANTS","S2_PARSE_STRENGTH","S1_OCR"],
 "assignment":[{"when":{},"result":"HIGH"}],
 "tolerances":[{"invariantId":"INV-01","mode":"EXACT",
   "calibrationBasis":"Non-negativity admits no tolerance."}],
 "approximationDeltas":[]}''',
        }),
        implementedSchemaMajor: 1,
        applicationVersion: Version(0, 1, 0),
      ).load();
      expect(r.isSuccess, isFalse);
      expect(r.failureOrNull!.kind, RulePackFailureKind.schemaViolation);
    });
  });
}
