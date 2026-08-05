import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  SynonymTable table() => SynonymTable(<SynonymEntry>[
        SynonymEntry(
          nutrient: NutrientId.energy,
          patterns: const <SynonymPattern>[
            SynonymPattern(text: 'Energy', strength: ParseStrength.exact),
            SynonymPattern(
                text: 'Energy Value', strength: ParseStrength.normalised),
            SynonymPattern(text: 'Calories', strength: ParseStrength.heuristic),
          ],
          expectedUnits: const <Unit>[Unit.kilocalorie, Unit.kilojoule],
        ),
        SynonymEntry(
          nutrient: NutrientId.sodium,
          patterns: const <SynonymPattern>[
            SynonymPattern(text: 'Sodium', strength: ParseStrength.exact),
          ],
          expectedUnits: const <Unit>[Unit.milligram, Unit.gram],
        ),
      ]);

  group('SynonymTable — a domain type, never JSON (ARCHITECTURE 2.2)', () {
    test('FR-KB-12 mirrors the rule pack schema shape', () {
      // rulepack/schema/synonyms.schema.json: nutrient, patterns[{text,
      // strength, caseSensitive}], expectedUnits. lw_rulepack builds this; the
      // domain never parses it.
      final SynonymEntry e = table().entries.first;
      expect(e.nutrient, NutrientId.energy);
      expect(e.patterns.first.text, 'Energy');
      expect(e.patterns.first.strength, ParseStrength.exact);
      expect(e.expectedUnits, <Unit>[Unit.kilocalorie, Unit.kilojoule]);
    });

    test('FR-PAR-13 lookup returns the nutrient and the matching strength', () {
      final SynonymMatch? m = table().match('Energy');
      expect(m, isNotNull);
      expect(m!.nutrient, NutrientId.energy);
      expect(m.strength, ParseStrength.exact);
      expect(m.pattern.text, 'Energy');
    });

    test('FR-PAR-13 a normalised pattern reports NORMALISED strength', () {
      expect(table().match('Energy Value')!.strength, ParseStrength.normalised);
    });

    test('FR-PAR-13 a heuristic pattern reports HEURISTIC strength', () {
      expect(table().match('Calories')!.strength, ParseStrength.heuristic);
    });

    test('FR-PAR-13 matching is case-insensitive by default', () {
      // The rule pack marks caseSensitive false by default, so "ENERGY" and
      // "energy" resolve without needing separate patterns.
      expect(table().match('ENERGY')!.nutrient, NutrientId.energy);
      expect(table().match('energy')!.nutrient, NutrientId.energy);
    });

    test('FR-PAR-13 a case-sensitive pattern does not match other casings', () {
      final SynonymTable t = SynonymTable(<SynonymEntry>[
        SynonymEntry(
          nutrient: NutrientId.protein,
          patterns: const <SynonymPattern>[
            SynonymPattern(
              text: 'Protein',
              strength: ParseStrength.exact,
              caseSensitive: true,
            ),
          ],
          expectedUnits: const <Unit>[Unit.gram],
        ),
      ]);
      expect(t.match('Protein'), isNotNull);
      expect(t.match('PROTEIN'), isNull);
    });

    test('FR-PAR-05 unknown text resolves to nothing, never a guess', () {
      // Returning a best-effort nutrient here would produce a confident wrong
      // answer, which FR-PAR-05 and P1 both forbid.
      expect(table().match('Riboflavin'), isNull);
      expect(table().match(''), isNull);
    });

    test('FR-PAR-06 expected units are retrievable per nutrient', () {
      // A unit outside this set lowers confidence rather than failing the
      // parse; S6 and S8 consume this.
      expect(table().expectedUnitsFor(NutrientId.sodium),
          <Unit>[Unit.milligram, Unit.gram]);
      expect(table().expectedUnitsFor(NutrientId.cholesterol), isEmpty);
    });

    test('FR-PAR-02 a duplicate pattern across nutrients is rejected', () {
      // An ambiguous table would make resolution order-dependent and break
      // byte-identical determinism.
      expect(
        () => SynonymTable(<SynonymEntry>[
          SynonymEntry(
            nutrient: NutrientId.energy,
            patterns: const <SynonymPattern>[
              SynonymPattern(text: 'Energy', strength: ParseStrength.exact),
            ],
            expectedUnits: const <Unit>[Unit.kilocalorie],
          ),
          SynonymEntry(
            nutrient: NutrientId.protein,
            patterns: const <SynonymPattern>[
              SynonymPattern(text: 'energy', strength: ParseStrength.exact),
            ],
            expectedUnits: const <Unit>[Unit.gram],
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('FR-PAR-13 an empty table matches nothing and does not throw', () {
      final SynonymTable empty = SynonymTable(const <SynonymEntry>[]);
      expect(empty.match('Energy'), isNull);
      expect(empty.entries, isEmpty);
    });

    test('FR-KB-01 the entry list is unmodifiable once built', () {
      final SynonymTable t = table();
      expect(
        () => t.entries.add(
          SynonymEntry(
            nutrient: NutrientId.protein,
            patterns: const <SynonymPattern>[
              SynonymPattern(text: 'x', strength: ParseStrength.exact),
            ],
            expectedUnits: const <Unit>[Unit.gram],
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('P4 SynonymPattern compares by value, not identity', () {
      // The duplicate-wording check above compares patterns built from
      // different entries. It only works if two patterns describing the same
      // wording are interchangeable regardless of where they were built.
      const SynonymPattern a = SynonymPattern(
        text: 'Energy',
        strength: ParseStrength.exact,
      );
      final SynonymPattern b = SynonymPattern(
        text: String.fromCharCodes('Energy'.codeUnits),
        strength: ParseStrength.exact,
      );
      const SynonymPattern otherStrength = SynonymPattern(
        text: 'Energy',
        strength: ParseStrength.heuristic,
      );
      const SynonymPattern otherCasing = SynonymPattern(
        text: 'Energy',
        strength: ParseStrength.exact,
        caseSensitive: true,
      );
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(otherStrength), reason: 'strength is part of the value');
      expect(a, isNot(otherCasing), reason: 'casing is part of the value');
    });

    test('FR-PAR-13 toString identifies the wording, match and table', () {
      // A wording that failed to resolve is diagnosed by reading these. A
      // type name alone would make that impossible.
      const SynonymPattern p =
          SynonymPattern(text: 'Energy', strength: ParseStrength.exact);
      expect(p.toString(), 'SynonymPattern("Energy", exact)');
      expect(
        table().match('Calories')!.toString(),
        'SynonymMatch(energy, heuristic)',
      );
      expect(table().toString(), 'SynonymTable(2 entries)');
    });

    test('FR-KB-04 an entry with no pattern is rejected', () {
      // The rule pack schema sets minItems 1; the domain type must not accept
      // what the schema forbids.
      expect(
        () => SynonymEntry(
          nutrient: NutrientId.energy,
          patterns: const <SynonymPattern>[],
          expectedUnits: const <Unit>[Unit.kilocalorie],
        ),
        throwsArgumentError,
      );
    });
  });
}
