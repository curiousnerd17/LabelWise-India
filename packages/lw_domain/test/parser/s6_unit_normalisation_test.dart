import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  SynonymTable table() => SynonymTable(<SynonymEntry>[
        SynonymEntry(
          nutrient: NutrientId.energy,
          patterns: const <SynonymPattern>[
            SynonymPattern(text: 'Energy', strength: ParseStrength.exact),
          ],
          expectedUnits: const <Unit>[Unit.kilocalorie, Unit.kilojoule],
        ),
        SynonymEntry(
          nutrient: NutrientId.protein,
          patterns: const <SynonymPattern>[
            SynonymPattern(text: 'Protein', strength: ParseStrength.exact),
          ],
          expectedUnits: const <Unit>[Unit.gram],
        ),
      ]);

  ResolvedField field(
    NutrientId nutrient,
    String value, {
    String? unit = 'g',
    Qualifier qualifier = Qualifier.exact,
    Basis basis = Basis.per100g,
    List<int> at = const <int>[0],
  }) =>
      ResolvedField(
        nutrient: nutrient,
        valueText: value,
        unitText: unit,
        qualifier: qualifier,
        basis: basis,
        labelStrength: ParseStrength.exact,
        basisStrength: ParseStrength.exact,
        region: box(0, 0, 100, 60),
        sourceIndices: at,
        matchedBy: RuleId('rule.resolve.synonym'),
      );

  ResolvedFields input(List<ResolvedField> fs) => ResolvedFields(
        fields: fs,
        nutritionPanelPresent: true,
      );

  TypedFields run(ResolvedFields r, {UnitLexicon? units}) {
    final StageResult<TypedFields> out =
        normaliseUnits(r, synonyms: table(), units: units);
    expect(out.isSuccess, isTrue, reason: 'expected S6 success');
    return out.valueOrNull!;
  }

  group('S6 — failure paths are values, not exceptions (FR-PAR-17)', () {
    test('FR-PAR-17 nothing supplied yields regionNotFound', () {
      final StageResult<TypedFields> out =
          normaliseUnits(ResolvedFields(), synonyms: table());
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
      expect(out.failureOrNull!.stage, PipelineStage.unitNormalisation);
    });
  });

  group('S6 — unit normalisation (FR-PAR-06)', () {
    test('FR-PAR-06 a canonical unit types without a substitution', () {
      final TypedFields t =
          run(input(<ResolvedField>[field(NutrientId.protein, '8')]));
      expect(t.fields.single.quantity, const Quantity.exact(800, Unit.gram));
      expect(t.fields.single.substitutions, isEmpty);
    });

    test('FR-PAR-06 every declared gram variant maps to grams', () {
      for (final String printed in <String>['gm', 'gms', 'gram', 'grams']) {
        final TypedFields t = run(
          input(<ResolvedField>[field(NutrientId.protein, '8', unit: printed)]),
        );
        expect(t.fields.single.quantity.unit, Unit.gram,
            reason: 'must normalise "$printed"');
      }
    });

    test('FR-PAR-06 a normalisation is recorded, never silent', () {
      // FR-OCR-06 forbids altering recognised text untraceably. Every change
      // between the printed form and the typed value is an audit entry.
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.protein, '8', unit: 'gm')]),
      );
      final Substitution s = t.fields.single.substitutions.single;
      expect(s.kind, SubstitutionKind.unitNormalisation);
      expect(s.before, 'gm');
      expect(s.after, 'g');
    });

    test('FR-PAR-06 unit matching is case-insensitive', () {
      for (final String printed in <String>['KCAL', 'kCal', 'Kcal']) {
        final TypedFields t = run(
          input(<ResolvedField>[
            field(NutrientId.energy, '400', unit: printed),
          ]),
        );
        expect(t.fields.single.quantity.unit, Unit.kilocalorie);
      }
    });

    test('FR-PAR-05 a missing unit is unresolved, never assumed', () {
      // Inventing "g" would manufacture a declaration the label never made.
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.protein, '8', unit: null)]),
      );
      expect(t.fields, isEmpty);
      expect(t.unresolved.single.reason, UnresolvedReason.unitNotDetermined);
    });

    test('FR-PAR-05 an unrecognised unit is unresolved', () {
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.protein, '8', unit: 'furlong')]),
      );
      expect(t.unresolved.single.reason, UnresolvedReason.unitNotDetermined);
    });

    test('ADR-0013 a caller-supplied lexicon replaces the default', () {
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.protein, '8', unit: 'gramm')]),
        units: UnitLexicon(<UnitVariant>[
          UnitVariant(
            text: 'gramm',
            unit: Unit.gram,
            strength: ParseStrength.normalised,
          ),
        ]),
      );
      expect(t.fields.single.quantity.unit, Unit.gram);
    });
  });

  group('S6 — quantity construction (DATA_MODEL 2.1, MI-11)', () {
    test('MI-11 a whole number becomes a scaled integer, never a double', () {
      final TypedFields t =
          run(input(<ResolvedField>[field(NutrientId.protein, '8')]));
      expect(t.fields.single.quantity.scaledValue, 800);
    });

    test('MI-11 a decimal scales exactly to the unit precision', () {
      final TypedFields t =
          run(input(<ResolvedField>[field(NutrientId.protein, '0.5')]));
      expect(t.fields.single.quantity, const Quantity.exact(50, Unit.gram));
    });

    test('DATA_MODEL 2.4 excess precision rounds half away from zero', () {
      // Grams track hundredths, so 0.005 g rounds to 0.01 g under the single
      // rounding policy rather than being silently truncated to zero.
      final TypedFields t =
          run(input(<ResolvedField>[field(NutrientId.protein, '0.005')]));
      expect(t.fields.single.quantity.scaledValue, 1);
    });

    test('FR-PAR-04 a thousands separator is read, not rejected', () {
      final TypedFields t = run(
        input(<ResolvedField>[
          field(NutrientId.energy, '1,000', unit: 'kcal'),
        ]),
      );
      expect(t.fields.single.quantity.scaledValue, 10000);
    });

    test('FR-PAR-05 text that is not a number is unresolved', () {
      // A blank value is not tested here: ResolvedField rejects one at
      // construction, so it cannot reach S6 at all.
      for (final String bad in <String>['abc', '1.2.3', '-5', '8.', '1e3']) {
        final TypedFields t =
            run(input(<ResolvedField>[field(NutrientId.protein, bad)]));
        expect(t.unresolved.single.reason, UnresolvedReason.valueNotParseable,
            reason: 'must decline "$bad"');
      }
    });

    test('ADR-0027 the qualifier survives typing untouched', () {
      // A bound must never be coerced to a point value (MI-16).
      final TypedFields t = run(input(<ResolvedField>[
        field(NutrientId.protein, '0.5', qualifier: Qualifier.lessThan),
      ]));
      expect(t.fields.single.quantity, const Quantity.lessThan(50, Unit.gram));
      expect(t.fields.single.quantity.qualifier, Qualifier.lessThan);
    });
  });

  group('S6 — energy conversion (FR-PAR-07)', () {
    test('FR-PAR-07 kilojoules convert to kilocalories', () {
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.energy, '1000', unit: 'kJ')]),
      );
      // 1000 kJ = 239.0 kcal under the thermochemical calorie.
      expect(t.fields.single.quantity,
          const Quantity.exact(2390, Unit.kilocalorie));
    });

    test('FR-PAR-07 the declared value is retained, not discarded', () {
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.energy, '1000', unit: 'kJ')]),
      );
      expect(t.fields.single.declaredAs,
          const Quantity.exact(10000, Unit.kilojoule));
    });

    test('FR-PAR-07 the conversion is recorded as a substitution', () {
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.energy, '1000', unit: 'kJ')]),
      );
      final Substitution s = t.fields.single.substitutions.firstWhere(
          (Substitution x) => x.kind == SubstitutionKind.energyConversion);
      expect(s.before, '10000 kilojoule');
      expect(s.after, '2390 kilocalorie');
    });

    test('FR-PAR-07 kilocalories are left alone and retain no original', () {
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.energy, '400', unit: 'kcal')]),
      );
      expect(t.fields.single.declaredAs, isNull);
      expect(t.fields.single.substitutions, isEmpty);
    });

    test('ADR-0027 conversion preserves a declared bound direction', () {
      final TypedFields t = run(input(<ResolvedField>[
        field(
          NutrientId.energy,
          '1000',
          unit: 'kJ',
          qualifier: Qualifier.lessThan,
        ),
      ]));
      expect(t.fields.single.quantity.qualifier, Qualifier.lessThan);
      expect(t.fields.single.declaredAs!.qualifier, Qualifier.lessThan);
    });

    test('DATA_MODEL 2.3 mass is never converted between g and mg', () {
      // Converting 250 mg to grams would round to the gram scale and lose
      // precision the label declared. Canonicalising variants is FR-PAR-06;
      // converting magnitudes is not.
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.protein, '250', unit: 'mg')]),
      );
      expect(t.fields.single.quantity.unit, Unit.milligram);
      expect(t.fields.single.quantity.scaledValue, 2500);
    });
  });

  group('S6 — the unit expectation signal for S8 (ADR-0010)', () {
    test('FR-CNF-01 a unit inside the expected set is flagged expected', () {
      final TypedFields t =
          run(input(<ResolvedField>[field(NutrientId.protein, '8')]));
      expect(t.fields.single.unitWasExpected, isTrue);
    });

    test(
        'FR-CNF-01 a unit outside the expected set lowers a signal, not the '
        'parse', () {
      // DATA_MODEL 7.4: an unexpected unit lowers confidence rather than
      // failing the parse. S6 records the signal; S8 acts on it.
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.protein, '250', unit: 'mg')]),
      );
      expect(t.fields, hasLength(1));
      expect(t.fields.single.unitWasExpected, isFalse);
    });

    test('FR-CNF-01 a nutrient with no stated expectation is not penalised',
        () {
      final TypedFields t = run(
        input(<ResolvedField>[field(NutrientId.sodium, '250', unit: 'mg')]),
      );
      expect(t.fields.single.unitWasExpected, isTrue);
    });

    test('ADR-0010 no confidence is assigned at S6', () {
      // Confidence assignment is S8 and its function is rule pack data. A
      // confidence set here would be a second source of truth.
      final TypedFields t =
          run(input(<ResolvedField>[field(NutrientId.protein, '8')]));
      expect(t.fields.single.labelStrength, ParseStrength.exact);
      expect(t.fields.single.basisStrength, ParseStrength.exact);
    });
  });

  group('S6 — provenance and traceability (M6 owner requirement)', () {
    test('FR-PAR-13 the output records the stage that produced it', () {
      expect(
        run(input(<ResolvedField>[field(NutrientId.protein, '8')]))
            .producedByStage,
        PipelineStage.unitNormalisation,
      );
    });

    test('FR-PAR-13 nutrient, basis and source indices survive typing', () {
      final TypedFields t = run(input(<ResolvedField>[
        field(
          NutrientId.protein,
          '8',
          basis: Basis.perServe,
          at: const <int>[3, 4],
        ),
      ]));
      expect(t.fields.single.nutrient, NutrientId.protein);
      expect(t.fields.single.basis, Basis.perServe);
      expect(t.fields.single.sourceIndices, <int>[3, 4]);
      expect(t.fields.single.region, box(0, 0, 100, 60));
      expect(t.fields.single.matchedBy, RuleId('rule.resolve.synonym'));
    });

    test('FR-ERR-03 S5 failures pass through S6 unchanged', () {
      final UnresolvedCandidate u = UnresolvedCandidate(
        reason: UnresolvedReason.noMatchingRule,
        labelText: 'Riboflavin',
        region: box(0, 0, 10, 10),
        sourceIndices: const <int>[9],
      );
      final TypedFields t = run(ResolvedFields(
        unresolved: <UnresolvedCandidate>[u],
        nutritionPanelPresent: true,
      ));
      expect(t.unresolved, <UnresolvedCandidate>[u]);
    });

    test('FR-PAR-10 ingredient tokens pass through untouched', () {
      final IngredientToken tok = IngredientToken(
        position: 1,
        rawText: 'Wheat flour',
        region: box(0, 0, 10, 10),
        sourceIndices: const <int>[5],
        parseStrength: ParseStrength.exact,
      );
      final TypedFields t = run(ResolvedFields(
        ingredientTokens: <IngredientToken>[tok],
        ingredientListPresent: true,
      ));
      expect(t.ingredientTokens, <IngredientToken>[tok]);
    });

    test('FR-PAR-02 repeated normalisation of one input is identical', () {
      final ResolvedFields r = input(<ResolvedField>[
        field(NutrientId.protein, '8', at: const <int>[0]),
        field(NutrientId.energy, '1000', unit: 'kJ', at: const <int>[1]),
      ]);
      expect(run(r).fields, run(r).fields);
      expect(run(r).sourceIndices, run(r).sourceIndices);
    });
  });

  group('TypedField — value semantics (P4)', () {
    TypedField build({
      int scaled = 800,
      Basis basis = Basis.per100g,
      bool expected = true,
    }) =>
        TypedField(
          nutrient: NutrientId.protein,
          quantity: Quantity.exact(scaled, Unit.gram),
          basis: basis,
          labelStrength: ParseStrength.exact,
          basisStrength: ParseStrength.normalised,
          unitStrength: ParseStrength.exact,
          unitWasExpected: expected,
          region: box(0, 0, 100, 60),
          sourceIndices: const <int>[3, 4],
          matchedBy: RuleId('rule.resolve.synonym'),
        );

    test('P4 compares by value, not identity', () {
      // S7 evaluates invariants over these and S8 assigns confidence to them.
      // Both compare typed values across stage boundaries, so equality must
      // rest on the declaration rather than on object identity.
      final TypedField a = build();
      final TypedField b = build(scaled: int.parse('800'));
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('P4 a different declaration is a different value', () {
      final TypedField a = build();
      expect(a, isNot(build(scaled: 900)),
          reason: 'the typed quantity is part of the field');
      expect(a, isNot(build(basis: Basis.perServe)),
          reason: 'the same quantity on another basis is another declaration');
      expect(a, isNot(build(expected: false)),
          reason: 'the unit-expectation signal S8 reads is part of the value');
    });
  });
}
