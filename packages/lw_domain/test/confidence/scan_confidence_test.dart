import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  ScanConfidence classify({
    bool allResolved = true,
    int resolved = 10,
    int high = 10,
    int low = 0,
    int failed = 0,
  }) =>
      ScanConfidence.from(
        everyCriticalFieldResolved: allResolved,
        resolvedCriticalCount: resolved,
        highCriticalCount: high,
        lowCriticalCount: low,
        failedInvariantCount: failed,
      );

  group('ScanConfidence — a separate type from field Confidence (MI-10)', () {
    test('FR-CNF-07 exactly four levels exist, including PARTIAL', () {
      // PARTIAL has no counterpart in the field lattice: it records *our*
      // failure to read, not a judgement about a value.
      expect(ScanConfidence.values, hasLength(4));
      expect(
        ScanConfidence.values.map((ScanConfidence s) => s.name),
        <String>['high', 'medium', 'low', 'partial'],
      );
    });

    test('MI-10 it is not a Confidence and cannot be substituted for one', () {
      // Kept a distinct type deliberately. DATA_MODEL 4.5: aggregate
      // confidence must never participate in rule evaluation, and the cheapest
      // enforcement is to keep it out of the types that do.
      expect(ScanConfidence.high, isNot(isA<Confidence>()));
    });
  });

  group('ScanConfidence — the DATA_MODEL 4.5 rule', () {
    test('FR-ERR-03 an unread critical field makes the scan PARTIAL', () {
      // Reserved for our failure to read. A label that legitimately declares
      // no added sugars is a declaration gap for Layer 1 to report, not a
      // scan failure.
      expect(classify(allResolved: false), ScanConfidence.partial);
      expect(
        classify(allResolved: false, high: 10, failed: 0),
        ScanConfidence.partial,
        reason: 'PARTIAL outranks every other outcome',
      );
    });

    test('DATA_MODEL 4.5 HIGH needs 80 per cent HIGH and zero failures', () {
      expect(classify(resolved: 10, high: 10), ScanConfidence.high);
      expect(classify(resolved: 10, high: 8), ScanConfidence.high,
          reason: 'exactly 80 per cent still qualifies');
      expect(classify(resolved: 10, high: 7), ScanConfidence.medium,
          reason: 'below the bar falls to MEDIUM, not to LOW');
    });

    test('DATA_MODEL 4.5 one failed invariant blocks HIGH but not MEDIUM', () {
      expect(
          classify(resolved: 10, high: 10, failed: 1), ScanConfidence.medium);
    });

    test('DATA_MODEL 4.5 two failed invariants make the scan LOW', () {
      expect(classify(resolved: 10, high: 10, failed: 2), ScanConfidence.low);
    });

    test('DATA_MODEL 4.5 any LOW critical field makes the scan LOW', () {
      // One poor reading among twelve is worth telling the user about, even
      // when everything else reconciled.
      expect(classify(resolved: 10, high: 9, low: 1), ScanConfidence.low);
    });

    test('DATA_MODEL 4.5 MEDIUM is the honest middle, not a fallback', () {
      expect(classify(resolved: 10, high: 5), ScanConfidence.medium);
      expect(classify(resolved: 10, high: 0), ScanConfidence.medium,
          reason: 'no LOW field and no failure is still MEDIUM');
    });

    test('FR-PAR-17 zero resolved critical fields never reports HIGH', () {
      // Guards the ratio: 0 of 0 is not 100 per cent of anything, and a scan
      // that read nothing must not be presented as trustworthy.
      expect(classify(resolved: 0, high: 0), ScanConfidence.medium);
      expect(classify(allResolved: false, resolved: 0, high: 0),
          ScanConfidence.partial);
    });

    test('FR-PAR-17 negative counts are rejected rather than absorbed', () {
      expect(() => classify(resolved: -1), throwsArgumentError);
      expect(() => classify(high: -1), throwsArgumentError);
      expect(() => classify(low: -1), throwsArgumentError);
      expect(() => classify(failed: -1), throwsArgumentError);
    });

    test('FR-PAR-17 more HIGH fields than resolved fields is rejected', () {
      // An impossible count means the caller miscounted; absorbing it would
      // let a miscount present itself as a trustworthy scan.
      expect(() => classify(resolved: 3, high: 4), throwsArgumentError);
      expect(() => classify(resolved: 3, high: 2, low: 2), throwsArgumentError);
    });

    test('FR-CNF-06 classification is deterministic', () {
      expect(classify(resolved: 10, high: 8, failed: 0),
          classify(resolved: 10, high: 8, failed: 0));
    });
  });
}
