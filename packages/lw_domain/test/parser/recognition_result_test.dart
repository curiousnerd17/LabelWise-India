import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  group('OcrConfidence — the engine signal, not our classification', () {
    test('FR-OCR-04 is a normalised scaled integer, never a Confidence', () {
      // Signal S1. Deliberately a different type from Confidence: the engine's
      // self-report is not our verdict, and conflating them would let S1 leak
      // into S8 (ADR-0010).
      final OcrConfidence c = OcrConfidence(8500);
      expect(c.scaledValue, 8500);
      expect(OcrConfidence.scale, 10000);
      expect(c, isNot(isA<Confidence>()));
    });

    test('FR-OCR-04 rejects a value outside the normalised range', () {
      expect(() => OcrConfidence(-1), throwsArgumentError);
      expect(() => OcrConfidence(10001), throwsArgumentError);
      expect(() => OcrConfidence(0), returnsNormally);
      expect(() => OcrConfidence(10000), returnsNormally);
    });

    test('P4 compares by value', () {
      expect(OcrConfidence(5000), OcrConfidence(5000));
      expect(OcrConfidence(5000).hashCode, OcrConfidence(5000).hashCode);
      expect(OcrConfidence(5000), isNot(OcrConfidence(5001)));
    });
  });

  group('RecognitionElement — the neutral OCR model (B2)', () {
    test('FR-OCR-03 carries text and positional geometry', () {
      final RecognitionElement e = RecognitionElement(
        text: 'Energy',
        region: box(100, 200, 900, 260),
      );
      expect(e.text, 'Energy');
      expect(e.region, box(100, 200, 900, 260));
    });

    test('FR-OCR-04 absent confidence is null, never a substituted default',
        () {
      // The adapter must report absence explicitly. A defaulted value would be
      // indistinguishable from a real reading and would corrupt S1.
      final RecognitionElement e = RecognitionElement(
        text: 'Energy',
        region: box(0, 0, 10, 10),
      );
      expect(e.ocrConfidence, isNull);

      final RecognitionElement withConfidence = RecognitionElement(
        text: 'Energy',
        region: box(0, 0, 10, 10),
        ocrConfidence: OcrConfidence(9000),
      );
      expect(withConfidence.ocrConfidence, OcrConfidence(9000));
    });

    test('FR-OCR-06 text is held exactly as recognised', () {
      // No trimming, no case folding, no correction. S1 is the first place
      // text may change, and every change there is recorded.
      final RecognitionElement e = RecognitionElement(
        text: '  ENERGY  (kCal) ',
        region: box(0, 0, 10, 10),
      );
      expect(e.text, '  ENERGY  (kCal) ');
    });

    test('P4 compares by value', () {
      final RecognitionElement a =
          RecognitionElement(text: 'x', region: box(0, 0, 1, 1));
      final RecognitionElement b =
          RecognitionElement(text: 'x', region: box(0, 0, 1, 1));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('RecognitionResult — S0 output (FR-OCR-02)', () {
    test('FR-OCR-03 preserves engine reading order', () {
      final RecognitionResult r = RecognitionResult(
        elements: <RecognitionElement>[
          RecognitionElement(text: 'first', region: box(0, 0, 10, 10)),
          RecognitionElement(text: 'second', region: box(0, 20, 10, 30)),
        ],
        dominantScript: DominantScript.latin,
      );
      expect(r.elements.map((RecognitionElement e) => e.text),
          <String>['first', 'second']);
    });

    test('FR-OCR-05 records the script the adapter observed', () {
      // The adapter observes; the domain decides policy (approved Q3). The
      // result carries the observation without acting on it.
      for (final DominantScript s in DominantScript.values) {
        final RecognitionResult r = RecognitionResult(
          elements: const <RecognitionElement>[],
          dominantScript: s,
        );
        expect(r.dominantScript, s);
      }
      expect(DominantScript.values, hasLength(4));
    });

    test('FR-OCR-07 an empty result is representable, not an error', () {
      // "No text found" is a legitimate adapter outcome. Deciding what it means
      // is S1's job, not the model's.
      final RecognitionResult r = RecognitionResult(
        elements: const <RecognitionElement>[],
        dominantScript: DominantScript.undetermined,
      );
      expect(r.elements, isEmpty);
    });

    test('FR-OCR-06 the element list is unmodifiable', () {
      final RecognitionResult r = RecognitionResult(
        elements: <RecognitionElement>[
          RecognitionElement(text: 'x', region: box(0, 0, 1, 1)),
        ],
        dominantScript: DominantScript.latin,
      );
      expect(
        () => r.elements.add(
          RecognitionElement(text: 'y', region: box(0, 0, 1, 1)),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
