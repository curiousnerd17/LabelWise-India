import 'package:lw_domain/src/parser/normalised_text.dart';
import 'package:lw_domain/src/parser/parse_failure.dart';
import 'package:lw_domain/src/parser/recognition_result.dart';
import 'package:lw_domain/src/parser/stage.dart';
import 'package:lw_domain/src/provenance/pipeline_stage.dart';
import 'package:lw_domain/src/provenance/rule_id.dart';
import 'package:lw_domain/src/provenance/substitution.dart';

/// One character the recognition engine commonly confuses for another.
final class CharacterConfusion {
  /// Records a confusion pair.
  const CharacterConfusion({required this.from, required this.to});

  /// The character the engine produced.
  final String from;

  /// The character it should have produced in a numeric context.
  final String to;
}

/// The confusions S1 corrects.
///
/// Supplied to the stage rather than hard-coded, so `lw_rulepack` can widen it
/// later without a domain change (P10). The default carries the four pairs
/// named in `ARCHITECTURE.md` §6.1.
final class CharacterConfusionTable {
  /// Creates a confusion table.
  const CharacterConfusionTable(this.confusions);

  /// The four confusions named in the architecture: `O`→`0`, `l`→`1`,
  /// `S`→`5`, `B`→`8`.
  static const CharacterConfusionTable defaults =
      CharacterConfusionTable(<CharacterConfusion>[
    CharacterConfusion(from: 'O', to: '0'),
    CharacterConfusion(from: 'l', to: '1'),
    CharacterConfusion(from: 'S', to: '5'),
    CharacterConfusion(from: 'B', to: '8'),
  ]);

  /// The confusions to correct.
  final List<CharacterConfusion> confusions;
}

/// Rule identifiers S1 attributes its substitutions to.
final class _S1Rules {
  const _S1Rules._();
  static final RuleId whitespace = RuleId('rule.normalise.whitespace');
  static final RuleId confusion = RuleId('rule.normalise.character-confusion');
}

final RegExp _whitespaceRun = RegExp(r'\s+');
final RegExp _designator = RegExp(r'^[A-Za-z]\d+$');
final RegExp _anyDigit = RegExp(r'\d');

/// **S1 — Normalisation.** The first stage, and the first place text may
/// change.
///
/// FR-OCR-06 forbids altering recognised text before parsing, so every
/// transformation happens here and every one is recorded as a `Substitution`.
///
/// Pure and total: no I/O, no clock, no randomness (FR-PAR-01), and every
/// input yields a `StageResult` rather than an exception (FR-PAR-17).
///
/// Element count and order are always preserved. An element that normalises to
/// empty text is retained, because dropping it would break the source-index
/// mapping every later stage depends on.
StageResult<NormalisedText> normaliseText(
  RecognitionResult recognition, {
  CharacterConfusionTable confusions = CharacterConfusionTable.defaults,
}) {
  if (recognition.elements.isEmpty) {
    return const StageFailure<NormalisedText>(
      ParseFailure(
        kind: ParseFailureKind.noTextRecognised,
        stage: PipelineStage.normalisation,
      ),
    );
  }

  // FR-OCR-05: decline a script we cannot read rather than mis-parsing it.
  // `undetermined` proceeds — it is not evidence of a foreign script, and
  // refusing on it would decline labels the adapter merely failed to classify.
  if (recognition.dominantScript == DominantScript.devanagari ||
      recognition.dominantScript == DominantScript.other) {
    return const StageFailure<NormalisedText>(
      ParseFailure(
        kind: ParseFailureKind.unsupportedScript,
        stage: PipelineStage.normalisation,
      ),
    );
  }

  final List<NormalisedElement> out = <NormalisedElement>[];
  for (int i = 0; i < recognition.elements.length; i++) {
    final RecognitionElement source = recognition.elements[i];
    final List<Substitution> recorded = <Substitution>[];

    final String collapsed = _collapseWhitespace(source.text);
    if (collapsed != source.text) {
      recorded.add(Substitution(
        kind: SubstitutionKind.whitespace,
        before: source.text,
        after: collapsed,
        appliedByRuleId: _S1Rules.whitespace,
      ));
    }

    final String corrected = _correctConfusions(collapsed, confusions);
    if (corrected != collapsed) {
      recorded.add(Substitution(
        kind: SubstitutionKind.characterConfusion,
        before: collapsed,
        after: corrected,
        appliedByRuleId: _S1Rules.confusion,
      ));
    }

    out.add(NormalisedElement(
      sourceIndex: i,
      originalText: source.text,
      text: corrected,
      region: source.region,
      substitutions: recorded,
      ocrConfidence: source.ocrConfidence,
    ));
  }

  return StageSuccess<NormalisedText>(NormalisedText(elements: out));
}

String _collapseWhitespace(String input) =>
    input.replaceAll(_whitespaceRun, ' ').trim();

/// Corrects confusable characters, but only inside tokens that are plausibly
/// numeric.
///
/// Correcting blindly would turn `PROTEIN` into `PR0TEIN` and `SODIUM` into
/// `50DIUM` — damaging the label vocabulary S5 depends on. Two guards prevent
/// that, and both are deliberately conservative: a missed correction costs
/// accuracy, a wrong one costs correctness.
///
/// 1. A token containing no digit is never touched. `PROTEIN` has none.
/// 2. A token that is a single letter followed only by digits is a designator,
///    not a number. `B12` is vitamin B12 and `E211` is an additive reference;
///    neither is `812` or `E211` misread.
String _correctConfusions(String input, CharacterConfusionTable table) {
  if (table.confusions.isEmpty || input.isEmpty) {
    return input;
  }
  final List<String> tokens = input.split(' ');
  final List<String> result = <String>[];
  for (final String token in tokens) {
    if (!_anyDigit.hasMatch(token) || _designator.hasMatch(token)) {
      result.add(token);
      continue;
    }
    String corrected = token;
    for (final CharacterConfusion c in table.confusions) {
      corrected = corrected.replaceAll(c.from, c.to);
    }
    result.add(corrected);
  }
  return result.join(' ');
}
