import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  RecognitionResult input(
    List<String> texts, {
    DominantScript script = DominantScript.latin,
  }) =>
      RecognitionResult(
        elements: <RecognitionElement>[
          for (int i = 0; i < texts.length; i++)
            RecognitionElement(
              text: texts[i],
              region: box(0, i * 100, 1000, i * 100 + 60),
            ),
        ],
        dominantScript: script,
      );

  NormalisedText run(RecognitionResult r) {
    final StageResult<NormalisedText> out = normaliseText(r);
    expect(out.isSuccess, isTrue, reason: 'expected S1 success');
    return out.valueOrNull!;
  }

  group('S1 — failure paths are values, not exceptions (FR-PAR-17)', () {
    test('FR-OCR-07 no elements yields noTextRecognised', () {
      final StageResult<NormalisedText> out = normaliseText(
        RecognitionResult(
          elements: const <RecognitionElement>[],
          dominantScript: DominantScript.latin,
        ),
      );
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.noTextRecognised);
      expect(out.failureOrNull!.stage, PipelineStage.normalisation);
    });

    test('FR-OCR-05 a Devanagari-dominant result is declined, not parsed', () {
      // Honest refusal beats a bad parse (ADR-0015). The adapter observed the
      // script; S1 applies the policy.
      final StageResult<NormalisedText> out = normaliseText(
        input(<String>['ऊर्जा'], script: DominantScript.devanagari),
      );
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.unsupportedScript);
    });

    test('FR-OCR-05 a non-Latin, non-Devanagari script is also declined', () {
      final StageResult<NormalisedText> out =
          normaliseText(input(<String>['x'], script: DominantScript.other));
      expect(out.failureOrNull!.kind, ParseFailureKind.unsupportedScript);
    });

    test('FR-OCR-05 an undetermined script is parsed, not declined', () {
      // Undetermined is not evidence of a foreign script. Refusing here would
      // decline labels the adapter simply could not classify.
      expect(
        normaliseText(
          input(<String>['Energy'], script: DominantScript.undetermined),
        ).isSuccess,
        isTrue,
      );
    });
  });

  group('S1 — whitespace normalisation (FR-PAR-06)', () {
    test('FR-PAR-06 collapses runs of whitespace and trims', () {
      final NormalisedText out = run(input(<String>['  Total   Fat  ']));
      expect(out.elements.single.text, 'Total Fat');
    });

    test('FR-PAR-06 records a substitution when whitespace changed', () {
      final NormalisedText out = run(input(<String>['  Total   Fat  ']));
      final NormalisedElement e = out.elements.single;
      expect(e.substitutions, hasLength(1));
      expect(e.substitutions.single.kind, SubstitutionKind.whitespace);
      expect(e.substitutions.single.before, '  Total   Fat  ');
      expect(e.substitutions.single.after, 'Total Fat');
    });

    test('FR-PAR-06 records no substitution when nothing changed', () {
      // A no-op entry pads the audit trail and makes real changes harder to
      // find. Substitution's own constructor rejects it.
      final NormalisedText out = run(input(<String>['Total Fat']));
      expect(out.elements.single.substitutions, isEmpty);
    });

    test('FR-OCR-06 the original text is retained verbatim', () {
      final NormalisedText out = run(input(<String>['  ENERGY  ']));
      expect(out.elements.single.originalText, '  ENERGY  ');
      expect(out.elements.single.text, 'ENERGY');
    });
  });

  group('S1 — character confusion (ARCHITECTURE 6.1)', () {
    test('FR-PAR-06 corrects a confusable character inside a numeric token',
        () {
      final NormalisedText out = run(input(<String>['1OO']));
      expect(out.elements.single.text, '100');
      expect(
        out.elements.single.substitutions.any(
          (Substitution s) => s.kind == SubstitutionKind.characterConfusion,
        ),
        isTrue,
      );
    });

    test('FR-PAR-06 corrects lowercase l and uppercase S and B in numbers', () {
      // These tokens must not be designators. "S0" and "B0" are
      // indistinguishable from "B6" and "B12" under any token-local rule, so
      // asserting them here would contradict the designator test below.
      expect(run(input(<String>['l2.5'])).elements.single.text, '12.5');
      expect(run(input(<String>['2S'])).elements.single.text, '25');
      expect(run(input(<String>['1B'])).elements.single.text, '18');
    });

    test('FR-PAR-06 leaves a token containing no digit untouched', () {
      // "PROTEIN" must not become "PR0TEIN", and "SODIUM" must not become
      // "50DIUM". Correcting words is worse than not correcting numbers.
      for (final String word in <String>['PROTEIN', 'SODIUM', 'Bold', 'Salt']) {
        final NormalisedText out = run(input(<String>[word]));
        expect(out.elements.single.text, word, reason: 'must not alter $word');
        expect(out.elements.single.substitutions, isEmpty);
      }
    });

    test('FR-PAR-06 leaves a letter-and-digits designator untouched', () {
      // "B12" is vitamin B12, not 812. "E211" is an additive designator.
      // A leading letter followed only by digits marks a designator.
      for (final String d in <String>['B12', 'E211', 'B6']) {
        expect(run(input(<String>[d])).elements.single.text, d,
            reason: 'must not alter designator $d');
      }
    });

    test('FR-PAR-06 corrects only within the token, preserving the rest', () {
      final NormalisedText out = run(input(<String>['Energy 4O0 kcal']));
      expect(out.elements.single.text, 'Energy 400 kcal');
    });

    test('FR-PAR-06 an empty confusion table performs no correction', () {
      final StageResult<NormalisedText> out = normaliseText(
        input(<String>['1OO']),
        confusions: const CharacterConfusionTable(<CharacterConfusion>[]),
      );
      expect(out.valueOrNull!.elements.single.text, '1OO');
    });
  });

  group('S1 — structure is preserved (traceability)', () {
    test('FR-PAR-01 element count and order are unchanged', () {
      final NormalisedText out =
          run(input(<String>['Energy', 'Protein', 'Total Fat']));
      expect(out.elements, hasLength(3));
      expect(
        out.elements.map((NormalisedElement e) => e.text),
        <String>['Energy', 'Protein', 'Total Fat'],
      );
    });

    test('FR-PAR-13 every element records its source index and region', () {
      final NormalisedText out = run(input(<String>['a', 'b', 'c']));
      for (int i = 0; i < out.elements.length; i++) {
        expect(out.elements[i].sourceIndex, i);
        expect(out.elements[i].region, box(0, i * 100, 1000, i * 100 + 60));
      }
    });

    test('FR-PAR-13 the output records the stage that produced it', () {
      expect(run(input(<String>['x'])).producedByStage,
          PipelineStage.normalisation);
    });

    test('FR-OCR-04 element confidence passes through unchanged', () {
      final RecognitionResult r = RecognitionResult(
        elements: <RecognitionElement>[
          RecognitionElement(
            text: 'x',
            region: box(0, 0, 10, 10),
            ocrConfidence: OcrConfidence(7500),
          ),
          RecognitionElement(text: 'y', region: box(0, 20, 10, 30)),
        ],
        dominantScript: DominantScript.latin,
      );
      final NormalisedText out = run(r);
      expect(out.elements[0].ocrConfidence, OcrConfidence(7500));
      expect(out.elements[1].ocrConfidence, isNull);
    });

    test('FR-PAR-01 an element normalising to empty text is retained', () {
      // Dropping it would silently change element count and break the
      // source-index mapping that later stages rely on.
      final NormalisedText out = run(input(<String>['   ', 'Energy']));
      expect(out.elements, hasLength(2));
      expect(out.elements[0].text, '');
      expect(out.elements[1].sourceIndex, 1);
    });
  });
}
