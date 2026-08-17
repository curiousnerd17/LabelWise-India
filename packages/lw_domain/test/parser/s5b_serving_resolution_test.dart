import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **S5b resolves; it never chooses.**
///
/// A wrong serving size scales every per-serve figure downstream, so this stage
/// is deliberately conservative: no first-wins, no nearest-wins, no midpoint,
/// no inference from arithmetic. Where a label is ambiguous it says so.
void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  int nextIndex = 0;

  /// One line of text, split into elements the way S1/S2 would leave it.
  LayoutLine line(String text, {int? top}) {
    final int y = top ?? 0;
    final List<NormalisedElement> elements = <NormalisedElement>[
      for (final String word in text.split(' '))
        NormalisedElement(
          sourceIndex: nextIndex++,
          originalText: word,
          text: word,
          region: box(0, y, 100, y + 10),
        ),
    ];
    return LayoutLine(elements: elements, region: box(0, y, 100, y + 10));
  }

  ClassifiedRegions regions(
    List<String> lines, {
    RegionKind kind = RegionKind.other,
  }) {
    int y = 0;
    final List<LayoutLine> built = <LayoutLine>[
      for (final String t in lines) line(t, top: y += 20),
    ];
    return ClassifiedRegions(
      regions: <ClassifiedRegion>[
        ClassifiedRegion(
          kind: kind,
          lines: built,
          region: box(0, 0, 100, y + 10),
          matchStrength: ParseStrength.exact,
        ),
      ],
    );
  }

  ServingResolution resolve(
    List<String> lines, {
    RegionKind kind = RegionKind.other,
  }) {
    final StageResult<ServingResolution> out =
        resolveServing(regions(lines, kind: kind));
    expect(out.isSuccess, isTrue, reason: 'expected S5b success');
    return out.valueOrNull!;
  }

  ServingOutcome outcome(List<String> lines, ServingField field) =>
      resolve(lines).outcomeFor(field);

  Quantity? valueOf(List<String> lines, ServingField field) {
    final ServingOutcome o = outcome(lines, field);
    return o is ServingResolved ? o.candidate.quantity : null;
  }

  setUp(() => nextIndex = 0);

  group('S5b — FR-PAR-17 failure is a value, not an exception', () {
    test('no region at all yields regionNotFound', () {
      final StageResult<ServingResolution> out = resolveServing(
        ClassifiedRegions(regions: const <ClassifiedRegion>[]),
      );
      expect(out.isSuccess, isFalse);
      expect(out.failureOrNull!.kind, ParseFailureKind.regionNotFound);
      expect(out.failureOrNull!.stage, PipelineStage.servingResolution);
    });
  });

  group('S5b — exact declarations', () {
    test('FR-PAR-08 a serving size is read with its unit', () {
      expect(valueOf(<String>['Serving Size: 30 g'], ServingField.servingSize),
          const Quantity.exact(3000, Unit.gram));
    });

    test('FR-PAR-08 a servings-per-pack count is dimensionless', () {
      // No unit is printed beside a count, so Unit.count is definitional
      // rather than assumed.
      expect(
        valueOf(<String>['Servings per pack: 4'], ServingField.servingsPerPack),
        const Quantity.exact(400, Unit.count),
      );
    });

    test('FR-PAR-08 a net quantity is read with its unit', () {
      expect(valueOf(<String>['Net Quantity: 120 g'], ServingField.netQuantity),
          const Quantity.exact(12000, Unit.gram));
    });

    test('a millilitre net quantity keeps its dimension', () {
      expect(
        valueOf(<String>['Net Quantity: 250 ml'], ServingField.netQuantity),
        const Quantity.exact(2500, Unit.millilitre),
      );
    });

    test('a decimal value is read at the unit\'s precision', () {
      expect(
        valueOf(<String>['Serving Size: 32.5 g'], ServingField.servingSize),
        const Quantity.exact(3250, Unit.gram),
      );
    });

    test('all three fields resolve from one label', () {
      final ServingResolution r = resolve(<String>[
        'Serving Size: 30 g',
        'Servings per pack: 4',
        'Net Quantity: 120 g',
      ]);
      expect(r.facts.servingSize, const Quantity.exact(3000, Unit.gram));
      expect(r.facts.servingsPerPack, const Quantity.exact(400, Unit.count));
      expect(r.facts.netQuantity, const Quantity.exact(12000, Unit.gram));
    });
  });

  group('S5b — aliases, heuristics and OCR noise', () {
    test('a compatibility alias resolves at reduced strength', () {
      final ServingOutcome o =
          outcome(<String>['Net Wt. 120 g'], ServingField.netQuantity);
      expect(o, isA<ServingResolved>());
      expect((o as ServingResolved).candidate.parseStrength,
          ParseStrength.normalised);
    });

    test('the heuristic plural reads "About 4 servings"', () {
      final ServingOutcome o =
          outcome(<String>['About 4 servings'], ServingField.servingsPerPack);
      expect(o, isA<ServingResolved>());
      final ServingCandidate c = (o as ServingResolved).candidate;
      expect(c.parseStrength, ParseStrength.heuristic);
      expect(c.quantity.qualifier, Qualifier.approximately,
          reason: '"About" is read by the existing QualifierLexicon');
    });

    test('a qualifier survives into the resolved value', () {
      final Quantity? q = valueOf(
          <String>['Serving Size: approx 30 g'], ServingField.servingSize);
      expect(q, const Quantity.approximately(3000, Unit.gram));
      expect(q, isNot(const Quantity.exact(3000, Unit.gram)),
          reason: 'equality includes the qualifier (MI-14)');
    });

    test('trailing punctuation on the unit does not defeat the read', () {
      expect(valueOf(<String>['Net Wt. 120 g.'], ServingField.netQuantity),
          const Quantity.exact(12000, Unit.gram));
    });

    test('a marker inside the nutrition panel is read too', () {
      // Serving text is commonly printed in the panel header.
      expect(
        valueOf(<String>['Serving Size: 30 g'], ServingField.servingSize),
        isNotNull,
      );
      final ServingResolution r = resolve(
        <String>['Serving Size: 30 g'],
        kind: RegionKind.nutritionPanel,
      );
      expect(r.facts.servingSize, const Quantity.exact(3000, Unit.gram));
    });

    test('the ingredient list is never scanned', () {
      // A serving figure is never declared there, and scanning it would only
      // create opportunities to misread.
      final ServingResolution r = resolve(
        <String>['Serving Size: 30 g'],
        kind: RegionKind.ingredientList,
      );
      expect(r.outcomeFor(ServingField.servingSize), isA<ServingNotDeclared>());
    });
  });

  group('S5b — the value is read before or after the marker', () {
    test('a suffix marker reads the number before it', () {
      // The defect this group exists for: taking the substring *after* the
      // marker reads "About 4 servings" as empty, losing both the count and
      // the qualifier.
      final ServingOutcome o =
          outcome(<String>['About 4 servings'], ServingField.servingsPerPack);
      expect(o, isA<ServingResolved>());
      expect((o as ServingResolved).candidate.quantity,
          const Quantity.approximately(400, Unit.count));
    });

    test('a prefix marker still reads the number after it', () {
      expect(valueOf(<String>['Serving Size: 30 g'], ServingField.servingSize),
          const Quantity.exact(3000, Unit.gram));
    });

    test('every qualifier in the existing lexicon survives', () {
      // Reuses QualifierLexicon.defaults — no second qualifier parser. The
      // lexicon matches a qualifier only as a PREFIX, so the separator
      // punctuation must be stripped before it is consulted.
      for (final (String printed, Qualifier expected) in <(String, Qualifier)>[
        ('Serving Size: ~30 g', Qualifier.approximately),
        ('Serving Size: about 30 g', Qualifier.approximately),
        ('Serving Size: approx 30 g', Qualifier.approximately),
        ('Serving Size: 30 g', Qualifier.exact),
      ]) {
        expect(
          valueOf(<String>[printed], ServingField.servingSize)?.qualifier,
          expected,
          reason: printed,
        );
      }
    });

    test('MI-14 a qualified figure is not equal to an unqualified one', () {
      expect(
        valueOf(<String>['Serving Size: ~30 g'], ServingField.servingSize),
        isNot(const Quantity.exact(3000, Unit.gram)),
      );
    });

    test('separators between wording and value do not defeat the read', () {
      for (final String printed in <String>[
        'Serving Size: 30 g',
        'Serving Size - 30 g',
        'Serving Size = 30 g',
        'Serving Size 30 g',
        'Serving Size:30 g',
      ]) {
        expect(
          valueOf(<String>[printed], ServingField.servingSize),
          const Quantity.exact(3000, Unit.gram),
          reason: printed,
        );
      }
    });
  });

  group('S5b — MI-08, absent is not unresolved', () {
    test('a label with no serving text declares nothing', () {
      final ServingResolution r =
          resolve(<String>['Ingredients: Wheat flour, Sugar']);
      for (final ServingField f in ServingField.values) {
        expect(r.outcomeFor(f), isA<ServingNotDeclared>(), reason: f.name);
      }
      expect(r.facts.servingSize, isNull);
    });

    test('an unsupported phrase declares nothing rather than guessing', () {
      for (final String phrase in <String>[
        'Pack of 4',
        '4 x 30 g',
        '250 ml bottle',
      ]) {
        final ServingResolution r = resolve(<String>[phrase]);
        for (final ServingField f in ServingField.values) {
          expect(r.outcomeFor(f), isA<ServingNotDeclared>(),
              reason: '$phrase / ${f.name}');
        }
      }
    });

    test('one field resolving leaves the others NotDeclared', () {
      final ServingResolution r = resolve(<String>['Net Quantity: 120 g']);
      expect(r.outcomeFor(ServingField.netQuantity), isA<ServingResolved>());
      expect(r.outcomeFor(ServingField.servingSize), isA<ServingNotDeclared>());
      expect(r.outcomeFor(ServingField.servingsPerPack),
          isA<ServingNotDeclared>());
    });
  });

  group('S5b — malformed readings become Unresolved, never a value', () {
    ServingUnresolved unresolved(List<String> lines, ServingField field) {
      final ServingOutcome o = outcome(lines, field);
      expect(o, isA<ServingUnresolved>(), reason: lines.join(' | '));
      return o as ServingUnresolved;
    }

    test('a marked line with no number is not a declaration', () {
      // "Serving Size: see back" names the field and declares nothing.
      expect(
          outcome(<String>['Serving Size: see back'], ServingField.servingSize),
          isA<ServingNotDeclared>());
    });

    test('two numbers on one marked line are ambiguous', () {
      // "30 g x 4 servings" may declare a serve size, a pack count, a
      // multipack count, or two of them. Nothing in the text settles which.
      expect(
        unresolved(<String>['30 g x 4 servings'], ServingField.servingsPerPack)
            .reason,
        UnresolvedReason.ambiguousMatch,
      );
    });

    test('a serving size with no unit is unresolved', () {
      expect(
          unresolved(<String>['Serving Size: 30'], ServingField.servingSize)
              .reason,
          UnresolvedReason.ambiguousMatch);
    });

    test('a serving size in a wrong dimension is refused', () {
      // A serve declared in kilocalories is not a mass or a volume, and
      // assuming one would invent a reading.
      unresolved(<String>['Serving Size: 30 kcal'], ServingField.servingSize);
    });

    test('a unit printed beside a count means the line is not a count', () {
      unresolved(
          <String>['Servings per pack: 30 g'], ServingField.servingsPerPack);
    });

    test('zero and negative are not declarations a pack can make', () {
      // A zero serve divides by nothing; a negative one is a misread.
      unresolved(<String>['Serving Size: 0 g'], ServingField.servingSize);
    });

    test('a comma-separated literal is refused rather than guessed', () {
      // A comma is a thousands separator on Indian packs as often as a decimal
      // mark. Refusing to read either is safer than choosing.
      unresolved(<String>['Net Quantity: 1,200 g'], ServingField.netQuantity);
    });

    test('an unresolved outcome carries no value into the facts', () {
      final ServingResolution r = resolve(<String>['30 g x 4 servings']);
      expect(r.facts.servingsPerPack, isNull,
          reason: 'the invariants must never see a figure we declined to read');
    });
  });

  group('S5b — R2 duplicate reconciliation, never first-wins', () {
    test('two equivalent declarations reconcile', () {
      final ServingOutcome o = outcome(
        <String>['Serving Size: 30 g', 'Serve size 30 g'],
        ServingField.servingSize,
      );
      expect(o, isA<ServingResolved>());
      expect((o as ServingResolved).candidate.quantity,
          const Quantity.exact(3000, Unit.gram));
    });

    test('the strongest wording wins the strength', () {
      // The alias is NORMALISED, the specified wording EXACT. Reconciling must
      // not discard the better evidence.
      final ServingResolved o = outcome(
        <String>['Serve size 30 g', 'Serving Size: 30 g'],
        ServingField.servingSize,
      ) as ServingResolved;
      expect(o.candidate.parseStrength, ParseStrength.exact);
    });

    test('reconciled provenance merges every source index, sorted', () {
      final ServingResolved o = outcome(
        <String>['Serving Size: 30 g', 'Serve size 30 g'],
        ServingField.servingSize,
      ) as ServingResolved;
      final List<int> merged = o.candidate.sourceIndices;
      expect(merged.length, greaterThan(3),
          reason: 'both lines contributed elements');
      expect(merged, orderedEquals(<int>[...merged]..sort()));
    });

    test('equivalence is checked after same-dimension conversion', () {
      // 120 g and 120000 mg are the same declaration printed two ways.
      final ServingOutcome o = outcome(
        <String>['Net Quantity: 120 g', 'Net Wt. 120000 mg'],
        ServingField.netQuantity,
      );
      expect(o, isA<ServingResolved>());
    });

    test('disagreeing magnitudes stay unresolved with both retained', () {
      final ServingOutcome o = outcome(
        <String>['Serving Size: 30 g', 'Serve size 40 g'],
        ServingField.servingSize,
      );
      expect(o, isA<ServingUnresolved>());
      final ServingUnresolved u = o as ServingUnresolved;
      expect(u.reason, UnresolvedReason.ambiguousMatch);
      expect(u.candidates, hasLength(2),
          reason: 'a correction UI must be able to show what was found');
    });

    test('a qualifier mismatch is a disagreement, not a match', () {
      // "about 30 g" and "30 g" are different declarations (MI-14). Merging
      // them would silently discard the manufacturer's stated imprecision.
      final ServingOutcome o = outcome(
        <String>['Serving Size: 30 g', 'Serve size approx 30 g'],
        ServingField.servingSize,
      );
      expect(o, isA<ServingUnresolved>());
    });

    test('a cross-dimension pair never reconciles', () {
      // Converting grams to millilitres would invent a density.
      final ServingOutcome o = outcome(
        <String>['Net Quantity: 120 g', 'Net Wt. 120 ml'],
        ServingField.netQuantity,
      );
      expect(o, isA<ServingUnresolved>());
    });

    test('a good reading beside an unreadable one is not trusted', () {
      // The agreement may be a coincidence of the ones we could read.
      final ServingOutcome o = outcome(
        <String>['Serving Size: 30 g', 'Serving size 30 g x 2'],
        ServingField.servingSize,
      );
      expect(o, isA<ServingUnresolved>());
    });
  });

  group('S5b — provenance and determinism', () {
    test('ADR-0009 the region, indices and marker rule are recorded', () {
      final ServingResolved o =
          outcome(<String>['Serving Size: 30 g'], ServingField.servingSize)
              as ServingResolved;
      expect(o.candidate.region, isA<RegionRef>());
      expect(o.candidate.sourceIndices, isNotEmpty);
      expect(o.candidate.matchedBy, RuleId('rule.serving.marker'));
      expect(o.candidate.field, ServingField.servingSize);
    });

    test('FR-PAR-02 the same input resolves to an equal value twice', () {
      // Determinism is "same input, same output", so the regions are built
      // ONCE and resolved twice. Rebuilding them per call would hand the stage
      // fresh source indices each time — different input, and therefore not a
      // determinism test at all.
      final ClassifiedRegions input = regions(<String>[
        'Serving Size: 30 g',
        'Servings per pack: 4',
        'Net Quantity: 120 g',
      ]);
      final ServingResolution a = resolveServing(input).valueOrNull!;
      final ServingResolution b = resolveServing(input).valueOrNull!;

      // Whole-value equality, not a field-by-field spot check and not toString.
      expect(a, b);
      expect(a.hashCode, b.hashCode,
          reason: 'a == b must imply equal hash codes');
      for (final ServingField f in ServingField.values) {
        expect(a.outcomeFor(f), b.outcomeFor(f), reason: f.name);
      }
      expect(a.facts, b.facts);
    });

    test('FR-PAR-02 differing source indices are a real difference', () {
      // The counterpart: two resolutions of the *same wording* read from
      // different elements are not equal, because provenance is part of the
      // value. Without this, the equality above could pass vacuously.
      final ServingResolution a = resolve(<String>['Net Quantity: 120 g']);
      final ServingResolution b = resolve(<String>['Net Quantity: 120 g']);
      expect(a.facts, b.facts, reason: 'the figures read are identical');
      expect(a, isNot(b),
          reason: 'but they were read from different source elements');
    });

    test('FR-PAR-02 output does not depend on declaration order', () {
      final ServingResolution a = resolve(<String>[
        'Serving Size: 30 g',
        'Net Quantity: 120 g',
      ]);
      final ServingResolution b = resolve(<String>[
        'Net Quantity: 120 g',
        'Serving Size: 30 g',
      ]);
      expect(a.facts.servingSize, b.facts.servingSize);
      expect(a.facts.netQuantity, b.facts.netQuantity);
    });

    test('every field always has an outcome', () {
      final ServingResolution r = resolve(<String>['Serving Size: 30 g']);
      expect(r.outcomes.keys, containsAll(ServingField.values));
    });
  });

  group('ServingResolution and its outcomes — value semantics', () {
    ServingCandidate candidate({int scaled = 3000}) => ServingCandidate(
          field: ServingField.servingSize,
          quantity: Quantity.exact(scaled, Unit.gram),
          parseStrength: ParseStrength.exact,
          region: box(0, 0, 10, 10),
          sourceIndices: const <int>[1, 2],
          matchedBy: RuleId('rule.serving.marker'),
        );

    test('P4 candidates compare by value', () {
      expect(candidate(), candidate());
      expect(candidate().hashCode, candidate().hashCode);
      expect(candidate(), isNot(candidate(scaled: 4000)));
      expect(
        candidate(),
        isNot(ServingCandidate(
          field: ServingField.servingSize,
          quantity: const Quantity.exact(3000, Unit.gram),
          parseStrength: ParseStrength.exact,
          region: box(0, 0, 10, 10),
          sourceIndices: const <int>[1],
          matchedBy: RuleId('rule.serving.marker'),
        )),
        reason: 'source indices participate in equality',
      );
    });

    test('P4 outcomes compare by value', () {
      expect(ServingResolved(candidate()), ServingResolved(candidate()));
      expect(ServingResolved(candidate()).hashCode,
          ServingResolved(candidate()).hashCode);
      expect(const ServingNotDeclared(), const ServingNotDeclared());
      expect(const ServingNotDeclared().hashCode,
          const ServingNotDeclared().hashCode);
      expect(ServingResolved(candidate()), isNot(const ServingNotDeclared()));

      ServingUnresolved u(
              {UnresolvedReason r = UnresolvedReason.ambiguousMatch}) =>
          ServingUnresolved(
              reason: r, candidates: <ServingCandidate>[candidate()]);
      expect(u(), u());
      expect(u().hashCode, u().hashCode);
      expect(u(), isNot(u(r: UnresolvedReason.valueNotParseable)));
      expect(
        u(),
        isNot(ServingUnresolved(
          reason: UnresolvedReason.ambiguousMatch,
          candidates: <ServingCandidate>[candidate(), candidate(scaled: 40)],
        )),
      );
    });

    test('FR-KB-01 collections are unmodifiable once built', () {
      expect(() => candidate().sourceIndices.add(9), throwsUnsupportedError);
      final ServingUnresolved u = ServingUnresolved(
        reason: UnresolvedReason.ambiguousMatch,
        candidates: <ServingCandidate>[candidate()],
      );
      expect(() => u.candidates.add(candidate()), throwsUnsupportedError);
      expect(
        () => ServingResolution.none.outcomes[ServingField.servingSize] =
            const ServingNotDeclared(),
        throwsUnsupportedError,
      );
    });

    test('the none resolution declares every field absent', () {
      expect(ServingResolution.none.facts.servingSize, isNull);
      for (final ServingField f in ServingField.values) {
        expect(ServingResolution.none.outcomeFor(f), isA<ServingNotDeclared>());
      }
    });

    test('outcomeFor is total even for an incomplete map', () {
      final ServingResolution partial = ServingResolution(
        facts: ServingFacts.none,
        outcomes: <ServingField, ServingOutcome>{},
      );
      expect(partial.outcomeFor(ServingField.netQuantity),
          isA<ServingNotDeclared>());
    });

    test('toString summarises without dumping', () {
      expect(candidate().toString(), contains('servingSize'));
      expect(ServingResolved(candidate()).toString(), contains('Resolved'));
      expect(const ServingNotDeclared().toString(), contains('NotDeclared'));
      expect(
        ServingUnresolved(
          reason: UnresolvedReason.ambiguousMatch,
          candidates: <ServingCandidate>[candidate()],
        ).toString(),
        contains('ambiguousMatch'),
      );
      expect(ServingResolution.none.toString(), contains('0 of 3'));
    });
  });
}
