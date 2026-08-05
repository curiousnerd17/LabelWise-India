import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  NutritionCandidate candidate({
    String label = 'Protein',
    String value = '8',
    String? unit = 'g',
    Qualifier qualifier = Qualifier.exact,
    int? column,
    List<int> indices = const <int>[0],
  }) =>
      NutritionCandidate(
        labelText: label,
        valueText: value,
        unitText: unit,
        qualifier: qualifier,
        columnIndex: column,
        region: box(0, 0, 100, 60),
        sourceIndices: indices,
        parseStrength: ParseStrength.exact,
      );

  IngredientToken token(
    int position,
    String text, {
    List<IngredientToken> children = const <IngredientToken>[],
    List<int> indices = const <int>[0],
    ParseStrength strength = ParseStrength.exact,
  }) =>
      IngredientToken(
        position: position,
        rawText: text,
        region: box(0, 0, 100, 60),
        sourceIndices: indices,
        parseStrength: strength,
        children: children,
      );

  group('QualifierLexicon — a bound is never coerced away (FR-PAR-18)', () {
    test('ADR-0027 the defaults cover every non-exact qualifier', () {
      final Set<Qualifier> covered = QualifierLexicon.defaults.entries
          .map((QualifierEntry e) => e.qualifier)
          .toSet();
      expect(covered, <Qualifier>{
        Qualifier.lessThan,
        Qualifier.greaterThan,
        Qualifier.approximately,
      });
    });

    test('ADR-0027 no marker may declare EXACT', () {
      // Exact is the absence of a marker. A marker for it would make the
      // default reachable two ways and the reading order-dependent.
      expect(
        () => QualifierEntry(marker: '=', qualifier: Qualifier.exact),
        throwsArgumentError,
      );
    });

    test('FR-PAR-17 a blank marker is rejected', () {
      expect(
        () => QualifierEntry(marker: '   ', qualifier: Qualifier.lessThan),
        throwsArgumentError,
      );
    });

    test('ADR-0027 an unqualified value reads as EXACT with text intact', () {
      expect(
        QualifierLexicon.defaults.read('  8.5 g '),
        const QualifierReading(qualifier: Qualifier.exact, remainder: '8.5 g'),
      );
    });

    test('FR-PAR-18 a spaced less-than bound is read, not discarded', () {
      // The trans fat case. Reading this as 0.5 would overstate; reading it
      // as 0 would discard what the label deliberately declared.
      expect(
        QualifierLexicon.defaults.read('< 0.5 g'),
        const QualifierReading(
          qualifier: Qualifier.lessThan,
          remainder: '0.5 g',
        ),
      );
    });

    test('FR-PAR-18 a flush less-than bound is read the same way', () {
      expect(QualifierLexicon.defaults.read('<0.5g').qualifier,
          Qualifier.lessThan);
      expect(QualifierLexicon.defaults.read('<0.5g').remainder, '0.5g');
    });

    test('FR-PAR-18 greater-than is read in both printed forms', () {
      expect(QualifierLexicon.defaults.read('> 10 g').qualifier,
          Qualifier.greaterThan);
      expect(QualifierLexicon.defaults.read('More than 10 g').qualifier,
          Qualifier.greaterThan);
    });

    test('FR-PAR-18 an approximation is read and reported as one', () {
      expect(QualifierLexicon.defaults.read('About 4').qualifier,
          Qualifier.approximately);
      expect(QualifierLexicon.defaults.read('~4').remainder, '4');
    });

    test('FR-PAR-02 matching folds case once, so it cannot vary', () {
      expect(QualifierLexicon.defaults.read('ABOUT 4').qualifier,
          Qualifier.approximately);
      expect(QualifierLexicon.defaults.read('ABOUT 4').remainder, '4');
    });

    test('FR-PAR-18 the longest marker wins', () {
      // "approximately" must not be read as "approx" plus stray text, or the
      // remainder becomes "imately 4" and the value is lost.
      expect(QualifierLexicon.defaults.read('Approximately 4').remainder, '4');
      expect(QualifierLexicon.defaults.read('Approx. 4').remainder, '. 4');
    });

    test('FR-PAR-05 an alphabetic marker must end at a word boundary', () {
      // "Aboutus" is not "about". Matching mid-word would invent a qualifier
      // the label never declared.
      final QualifierReading r = QualifierLexicon.defaults.read('Aboutus 4');
      expect(r.qualifier, Qualifier.exact);
      expect(r.remainder, 'Aboutus 4');
    });

    test('FR-PAR-17 an empty lexicon and empty input are both total', () {
      final QualifierLexicon empty = QualifierLexicon(const <QualifierEntry>[]);
      expect(empty.read('< 0.5 g').qualifier, Qualifier.exact);
      expect(QualifierLexicon.defaults.read('').qualifier, Qualifier.exact);
      expect(QualifierLexicon.defaults.read('   ').remainder, '');
    });

    test('P4 lexicon entries compare by value', () {
      final QualifierEntry a =
          QualifierEntry(marker: '<', qualifier: Qualifier.lessThan);
      final QualifierEntry b = QualifierEntry(
        marker: String.fromCharCodes('<'.codeUnits),
        qualifier: Qualifier.lessThan,
      );
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('NutritionCandidate — a quadruple of text, not a Quantity', () {
    test('FR-PAR-18 records label, value, unit and qualifier', () {
      final NutritionCandidate c = candidate(
        label: 'Trans Fat',
        value: '0.5',
        unit: 'g',
        qualifier: Qualifier.lessThan,
        column: 1,
      );
      expect(c.labelText, 'Trans Fat');
      expect(c.valueText, '0.5');
      expect(c.unitText, 'g');
      expect(c.qualifier, Qualifier.lessThan);
      expect(c.columnIndex, 1);
    });

    test('ADR-0027 an unqualified candidate defaults to EXACT', () {
      expect(candidate().qualifier, Qualifier.exact);
    });

    test('FR-PAR-05 a missing unit is null, never invented', () {
      // S5 turns this into an unresolved field. S4 guessing "g" here would
      // manufacture a declaration the label never made.
      expect(candidate(unit: null).unitText, isNull);
    });

    test('FR-PAR-05 a missing column is null, never guessed', () {
      expect(candidate().columnIndex, isNull);
    });

    test('FR-PAR-17 a candidate with no label is rejected', () {
      expect(() => candidate(label: '  '), throwsArgumentError);
    });

    test('FR-PAR-17 a candidate with no value is rejected', () {
      expect(() => candidate(value: ''), throwsArgumentError);
    });

    test('FR-PAR-13 a candidate tracing to no element is rejected', () {
      // A value with no origin cannot be explained, which ARCHITECTURE 8.3
      // forbids outright.
      expect(
        () => candidate(indices: const <int>[]),
        throwsArgumentError,
      );
    });

    test('P4 compares by value, not identity', () {
      final NutritionCandidate a =
          candidate(label: 'Protein', value: '8', indices: <int>[0, 1]);
      final NutritionCandidate b =
          candidate(label: 'Protein', value: '8', indices: <int>[0, 1]);
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(candidate(label: 'Protein', value: '9')));
      expect(
        a,
        isNot(candidate(qualifier: Qualifier.lessThan)),
        reason: 'the qualifier is part of the value (MI-14)',
      );
    });

    test('FR-PAR-13 toString shows the quadruple', () {
      final NutritionCandidate bounded = candidate(
        label: 'Trans Fat',
        value: '0.5',
        qualifier: Qualifier.lessThan,
      );
      expect(
        bounded.toString(),
        'NutritionCandidate("Trans Fat" = lessThan "0.5" g)',
      );
      expect(candidate(unit: null).toString(),
          'NutritionCandidate("Protein" = exact "8" ?)');
    });
  });

  group('IngredientToken — declaration order is the data (FR-PAR-10)', () {
    test('FR-PAR-12 records position, text and nesting', () {
      final IngredientToken t = token(
        3,
        'Emulsifier (INS 322, INS 471)',
        children: <IngredientToken>[
          token(1, 'INS 322', indices: const <int>[1]),
          token(2, 'INS 471', indices: const <int>[2]),
        ],
      );
      expect(t.position, 3);
      expect(t.children.map((IngredientToken c) => c.rawText),
          <String>['INS 322', 'INS 471']);
      expect(t.depth, 2);
    });

    test('FR-PAR-10 position is 1-based, and zero is rejected', () {
      // Declaration order is legally meaningful — descending by weight — so
      // an off-by-one silently reorders a legal claim.
      expect(() => token(0, 'Sugar'), throwsArgumentError);
      expect(() => token(-1, 'Sugar'), throwsArgumentError);
      expect(token(1, 'Sugar').position, 1);
    });

    test('FR-PAR-17 blank text and empty provenance are rejected', () {
      expect(() => token(1, '   '), throwsArgumentError);
      expect(
        () => token(1, 'Sugar', indices: const <int>[]),
        throwsArgumentError,
      );
    });

    test('FR-PAR-13 allSourceIndices reaches every descendant, ascending', () {
      final IngredientToken t = token(
        1,
        'Emulsifier (INS 322)',
        indices: const <int>[5],
        children: <IngredientToken>[
          token(1, 'INS 322', indices: const <int>[3]),
        ],
      );
      expect(t.sourceIndices, <int>[5]);
      expect(t.allSourceIndices, <int>[3, 5]);
    });

    test('FR-PAR-12 depth counts a plain ingredient as one', () {
      expect(token(1, 'Sugar').depth, 1);
    });

    test('FR-KB-01 children are unmodifiable once built', () {
      final IngredientToken t = token(1, 'Sugar');
      expect(() => t.children.add(token(1, 'x')), throwsUnsupportedError);
    });

    test('P4 compares by value, including nesting', () {
      final IngredientToken a = token(
        1,
        'Emulsifier',
        children: <IngredientToken>[token(1, 'INS 322')],
      );
      final IngredientToken b = token(
        1,
        'Emulsifier',
        children: <IngredientToken>[token(1, 'INS 322')],
      );
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(token(1, 'Emulsifier')),
          reason: 'nesting is part of the value');
      expect(
          a,
          isNot(token(2, 'Emulsifier',
              children: <IngredientToken>[token(1, 'INS 322')])));
    });

    test('FR-PAR-13 toString names position and nesting', () {
      expect(
        token(3, 'Sugar', children: <IngredientToken>[token(1, 'x')])
            .toString(),
        'IngredientToken(3, "Sugar", 1 nested)',
      );
    });
  });

  group('Candidates — the S4 output', () {
    test('FR-PAR-13 the output records the stage that produced it', () {
      expect(Candidates().producedByStage, PipelineStage.tokenisation);
    });

    test('FR-PAR-14 either half may be empty and both report it', () {
      final Candidates only = Candidates(
        ingredientTokens: <IngredientToken>[token(1, 'Sugar')],
      );
      expect(only.hasIngredients, isTrue);
      expect(only.hasNutrition, isFalse);
      expect(Candidates().hasNutrition, isFalse);
      expect(Candidates().hasIngredients, isFalse);
    });

    test('FR-PAR-13 source indices span both halves, ascending', () {
      final Candidates c = Candidates(
        nutritionCandidates: <NutritionCandidate>[
          candidate(indices: const <int>[4]),
        ],
        ingredientTokens: <IngredientToken>[
          token(
            1,
            'Sugar',
            indices: const <int>[9],
            children: <IngredientToken>[
              token(1, 'x', indices: const <int>[1]),
            ],
          ),
        ],
      );
      expect(c.sourceIndices, <int>[1, 4, 9]);
    });

    test('FR-KB-01 both lists are unmodifiable once built', () {
      final Candidates c = Candidates();
      expect(
          () => c.nutritionCandidates.add(candidate()), throwsUnsupportedError);
      expect(
          () => c.ingredientTokens.add(token(1, 'x')), throwsUnsupportedError);
    });

    test('FR-PAR-13 toString reports both halves', () {
      final Candidates c = Candidates(
        nutritionCandidates: <NutritionCandidate>[candidate()],
        ingredientTokens: <IngredientToken>[token(1, 'Sugar')],
      );
      expect(c.toString(), 'Candidates(1 nutrition, 1 ingredients)');
    });
  });
}
