import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  final Version pack = Version(1, 0, 0);

  Provenance extracted() => Provenance.extracted(
        producedByStage: PipelineStage.confidenceAssignment,
        parseRuleId: RuleId('rule.resolve.synonym'),
        parseStrength: ParseStrength.exact,
        sourceRegion: box(0, 0, 100, 60),
        rulePackVersion: pack,
      );

  FieldState value(int hundredths, {Basis basis = Basis.per100g}) =>
      ExtractedField(
        quantity: Quantity.exact(hundredths, Unit.gram),
        basis: basis,
        provenance: extracted(),
        confidence: Confidence.high,
      );

  FieldState unread() => UnresolvedField(
        reason: UnresolvedReason.noMatchingRule,
        provenance: Provenance.derived(
          producedByStage: PipelineStage.fieldResolution,
          parseRuleId: RuleId('rule.assemble.serving-unresolved'),
          rulePackVersion: pack,
        ),
      );

  group('CategoryId — data, not code (FR-CAT-03, ADR-0013)', () {
    test('FR-CAT-03 a well-formed pack identifier is accepted', () {
      // The five ids in rulepack/categories/categories.json.
      for (final String id in <String>[
        'cat.biscuits',
        'cat.chips',
        'cat.namkeen',
        'cat.instant-noodles',
        'cat.beverages',
      ]) {
        expect(CategoryId(id).value, id);
      }
    });

    test('FR-CAT-03 it is not an enum, so a new category needs no code', () {
      // An enum would force a Dart change for every category the rule pack
      // adds, which is exactly what FR-CAT-03 forbids.
      expect(CategoryId('cat.pickles').value, 'cat.pickles');
    });

    test('FR-KB-03 a malformed identifier is rejected at construction', () {
      // A reference that could never resolve in the pack is a defect here,
      // not a dangling reference discovered later.
      for (final String bad in <String>[
        'biscuits',
        'cat.',
        'cat.Biscuits',
        'rule.biscuits',
        '',
        'cat.bis cuits',
      ]) {
        expect(() => CategoryId(bad), throwsFormatException,
            reason: 'must reject "$bad"');
      }
    });

    test('FR-CAT-03 isValid answers without constructing', () {
      expect(CategoryId.isValid('cat.chips'), isTrue);
      expect(CategoryId.isValid('chips'), isFalse);
    });

    test('P4 compares by value, not identity', () {
      final CategoryId a = CategoryId('cat.chips');
      final CategoryId b =
          CategoryId(String.fromCharCodes('cat.chips'.codeUnits));
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(CategoryId('cat.namkeen')));
      expect(a.toString(), 'CategoryId(cat.chips)');
    });
  });

  group('InsNumber — the additive key (ADR-0005)', () {
    test('ADR-0005 an INS number is the primary additive key', () {
      expect(InsNumber(322).value, 322);
      expect(InsNumber(1520).value, 1520);
    });

    test('FR-PAR-17 a non-positive or implausible number is rejected', () {
      expect(() => InsNumber(0), throwsArgumentError);
      expect(() => InsNumber(-1), throwsArgumentError);
      expect(() => InsNumber(100000), throwsArgumentError);
    });

    test('P4 compares by value', () {
      expect(InsNumber(322), InsNumber(322));
      expect(InsNumber(322), isNot(InsNumber(471)));
      expect(InsNumber(322).hashCode, InsNumber(322).hashCode);
      expect(InsNumber(322).toString(), 'InsNumber(322)');
    });
  });

  group('IngredientIdentification — the union, no engine behind it', () {
    test('DATA_MODEL 5.4 exactly four variants exist', () {
      // Sealed, so a switch that forgets one fails to compile. Nothing in the
      // parser constructs any of them: identification is Layer 1 work.
      final List<IngredientIdentification> all = <IngredientIdentification>[
        AdditiveByIns(InsNumber(322)),
        AdditiveByName('lecithin'),
        PlainIngredient('wheat flour'),
        const Unidentified(UnidentifiedReason.notAttempted),
      ];
      expect(all, hasLength(4));
    });

    test('ADR-0005 an INS match may carry its class title', () {
      final AdditiveByIns a =
          AdditiveByIns(InsNumber(322), classTitle: 'Emulsifier');
      expect(a.insNumber, InsNumber(322));
      expect(a.classTitle, 'Emulsifier');
      expect(AdditiveByIns(InsNumber(322)).classTitle, isNull);
    });

    test('ADR-0005 a name match may carry a suspected INS number', () {
      final AdditiveByName a = AdditiveByName('lecithin');
      expect(a.matchedName, 'lecithin');
      expect(a.insNumber, isNull);
      expect(AdditiveByName('lecithin', insNumber: InsNumber(322)).insNumber,
          InsNumber(322));
    });

    test('FR-ERR-03 notAttempted is distinct from a failed attempt', () {
      // The distinction v1.6 turns on: null identification means we have not
      // tried; Unidentified means we tried and could not.
      expect(UnidentifiedReason.values.map((UnidentifiedReason r) => r.name),
          <String>['notAttempted', 'noMatchFound', 'textUnreadable']);
    });

    test('FR-PAR-17 blank text in a variant is rejected', () {
      expect(() => AdditiveByName('  '), throwsArgumentError);
      expect(() => PlainIngredient(''), throwsArgumentError);
    });

    test('P4 the variants compare by value and never across kinds', () {
      expect(PlainIngredient('sugar'), PlainIngredient('sugar'));
      expect(PlainIngredient('sugar'), isNot(AdditiveByName('sugar')));
      expect(AdditiveByIns(InsNumber(322)), AdditiveByIns(InsNumber(322)));
      expect(
          PlainIngredient('sugar').hashCode, PlainIngredient('sugar').hashCode);
      expect(PlainIngredient('sugar').toString(), 'PlainIngredient(sugar)');
      expect(AdditiveByIns(InsNumber(322)).toString(), 'AdditiveByIns(322)');
      expect(AdditiveByName('lecithin').toString(), 'AdditiveByName(lecithin)');
      expect(const Unidentified(UnidentifiedReason.notAttempted).toString(),
          'Unidentified(notAttempted)');
    });
  });

  group('Ingredient — declaration order is the data (FR-PAR-10)', () {
    Ingredient entry(int position, String text,
            {List<Ingredient> children = const <Ingredient>[]}) =>
        Ingredient(
          position: position,
          rawText: text,
          provenance: extracted(),
          subIngredients: children,
        );

    test('DATA_MODEL 5.4 records position, text, nesting and provenance', () {
      final Ingredient i = entry(3, 'Emulsifier (INS 322)',
          children: <Ingredient>[entry(1, 'INS 322')]);
      expect(i.position, 3);
      expect(i.rawText, 'Emulsifier (INS 322)');
      expect(i.subIngredients.single.rawText, 'INS 322');
      expect(i.provenance.origin, FieldOrigin.extracted);
    });

    test('v1.6 identification is null until the Layer 1 engine exists', () {
      // Null is not Unidentified: we have not attempted identification, which
      // is different from having attempted and failed.
      expect(entry(1, 'Sugar').identification, isNull);
    });

    test('FR-PAR-10 position is 1-based and zero is rejected', () {
      expect(() => entry(0, 'Sugar'), throwsArgumentError);
      expect(() => entry(-1, 'Sugar'), throwsArgumentError);
    });

    test('FR-PAR-17 blank text is rejected', () {
      expect(() => entry(1, '   '), throwsArgumentError);
    });

    test('FR-KB-01 sub-ingredients are unmodifiable once built', () {
      final Ingredient i = entry(1, 'Sugar');
      expect(() => i.subIngredients.add(entry(1, 'x')), throwsUnsupportedError);
    });

    test('P4 compares by value, including nesting', () {
      final Ingredient a =
          entry(1, 'Emulsifier', children: <Ingredient>[entry(1, 'INS 322')]);
      final Ingredient b =
          entry(1, 'Emulsifier', children: <Ingredient>[entry(1, 'INS 322')]);
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(entry(1, 'Emulsifier')));
      expect(a.toString(), 'Ingredient(1, "Emulsifier", 1 nested)');
    });
  });

  group('NutrientField — three slots, four bases (D1)', () {
    test('DATA_MODEL 5.2 all three bases are always present', () {
      // Modelled as a fixed triple rather than a list, so FR-PRS-02's
      // "display all three together" is a lookup and not a search.
      final NutrientField f = NutrientField(
        nutrient: NutrientId.protein,
        perHundred: value(800),
        perServe: const NotDeclaredField(),
        perPack: const NotDeclaredField(),
      );
      expect(f.perHundred.quantityOrNull, const Quantity.exact(800, Unit.gram));
      expect(f.perServe, isA<NotDeclaredField>());
      expect(f.perPack, isA<NotDeclaredField>());
    });

    test('D1 perHundred is a slot; the basis is read from the field', () {
      // A beverage declares per 100 ml. The slot name says nothing; the
      // ExtractedField carries the semantic basis, and consumers must read it
      // there rather than infer it from where it sits.
      final NutrientField f = NutrientField(
        nutrient: NutrientId.energy,
        perHundred: value(800, basis: Basis.per100ml),
        perServe: const NotDeclaredField(),
        perPack: const NotDeclaredField(),
      );
      expect(f.perHundred.basisOrNull, Basis.per100ml);
    });

    test('FR-PAR-09 the three outcomes stay distinguishable', () {
      final NutrientField f = NutrientField(
        nutrient: NutrientId.protein,
        perHundred: value(800),
        perServe: unread(),
        perPack: const NotDeclaredField(),
      );
      expect(f.perHundred, isA<ExtractedField>());
      expect(f.perServe, isA<UnresolvedField>());
      expect(f.perPack, isA<NotDeclaredField>());
    });

    test('FR-CNF-01 the strongest declared level is reachable', () {
      final NutrientField f = NutrientField(
        nutrient: NutrientId.protein,
        perHundred: value(800),
        perServe: const NotDeclaredField(),
        perPack: const NotDeclaredField(),
      );
      expect(f.anyDeclared, isTrue);
      expect(
        const NutrientField(
          nutrient: NutrientId.protein,
          perHundred: NotDeclaredField(),
          perServe: NotDeclaredField(),
          perPack: NotDeclaredField(),
        ).anyDeclared,
        isFalse,
      );
    });

    test('P4 compares by value', () {
      NutrientField build(NutrientId n) => NutrientField(
            nutrient: n,
            perHundred: value(800),
            perServe: const NotDeclaredField(),
            perPack: const NotDeclaredField(),
          );
      expect(build(NutrientId.protein), build(NutrientId.protein));
      expect(build(NutrientId.protein), isNot(build(NutrientId.sodium)));
      expect(build(NutrientId.protein).hashCode,
          build(NutrientId.protein).hashCode);
      expect(build(NutrientId.protein).toString(), 'NutrientField(protein)');
    });
  });

  group('ServingInfo — the pack figures (DATA_MODEL 5.3)', () {
    ServingInfo info() => ServingInfo(
          declaredServingSize: unread(),
          servingsPerPack: unread(),
          netQuantity: unread(),
        );

    test('DATA_MODEL 5.3 records the three critical pack figures', () {
      final ServingInfo s = info();
      expect(s.declaredServingSize, isA<UnresolvedField>());
      expect(s.servingsPerPack, isA<UnresolvedField>());
      expect(s.netQuantity, isA<UnresolvedField>());
    });

    test('v1.6 reconciliation is null from the parser', () {
      // It is a Layer 1 output, and Layer 1 consumes the ParsedLabel this
      // sits inside. Requiring it would close a cycle.
      expect(info().reconciliation, isNull);
    });

    test('P4 compares by value', () {
      expect(info(), info());
      expect(info().hashCode, info().hashCode);
      expect(
          info().toString(),
          'ServingInfo(unresolved, unresolved, '
          'unresolved)');
    });
  });

  group('ParsedLabel — the published contract (AR5)', () {
    ParsedLabel label({
      CategoryId? category,
      bool unsupported = false,
      List<NutrientField> nutrients = const <NutrientField>[],
    }) =>
        ParsedLabel(
          nutrients: nutrients,
          servingInfo: ServingInfo(
            declaredServingSize: unread(),
            servingsPerPack: unread(),
            netQuantity: unread(),
          ),
          scanConfidence: ScanConfidence.partial,
          rulePackVersion: pack,
          declaredCategory: category,
          unsupportedScript: unsupported,
        );

    test('DATA_MODEL 5.5 carries every specified field', () {
      final ParsedLabel p = label();
      expect(p.nutrients, isEmpty);
      expect(p.servingInfo, isNotNull);
      expect(p.ingredients, isEmpty);
      expect(p.declaredCategory, isNull);
      expect(p.invariantResults, isEmpty);
      expect(p.scanConfidence, ScanConfidence.partial);
      expect(p.rulePackVersion, pack);
      expect(p.unsupportedScript, isFalse);
    });

    test('FR-CAT-02 category is optional and never required', () {
      expect(label(category: CategoryId('cat.chips')).declaredCategory,
          CategoryId('cat.chips'));
    });

    test('D4 unsupportedScript is stored, never inferred', () {
      // Orchestration state. The parser never sets it: S1 declines a
      // non-Latin script through StageResult, which remains the only failure
      // channel.
      expect(label(unsupported: true).unsupportedScript, isTrue);
    });

    test('FR-PRS-02 a nutrient is reachable without searching', () {
      final ParsedLabel p = label(nutrients: <NutrientField>[
        NutrientField(
          nutrient: NutrientId.protein,
          perHundred: value(800),
          perServe: const NotDeclaredField(),
          perPack: const NotDeclaredField(),
        ),
      ]);
      expect(p.nutrientFor(NutrientId.protein), isNotNull);
      expect(p.nutrientFor(NutrientId.sodium), isNull);
    });

    test('M1 a duplicate nutrient entry is rejected at construction', () {
      // Two entries for one nutrient would make nutrientFor mean "whichever
      // came first" — a silent choice no consumer could see.
      NutrientField f() => NutrientField(
            nutrient: NutrientId.protein,
            perHundred: value(800),
            perServe: const NotDeclaredField(),
            perPack: const NotDeclaredField(),
          );
      expect(() => label(nutrients: <NutrientField>[f(), f()]),
          throwsArgumentError);
    });

    test('FR-KB-01 every carried list is unmodifiable once built', () {
      final ParsedLabel p = label();
      expect(
          () => p.nutrients.add(const NutrientField(
                nutrient: NutrientId.protein,
                perHundred: NotDeclaredField(),
                perServe: NotDeclaredField(),
                perPack: NotDeclaredField(),
              )),
          throwsUnsupportedError);
      expect(
          () => p.ingredients.add(Ingredient(
                position: 1,
                rawText: 'x',
                provenance: extracted(),
              )),
          throwsUnsupportedError);
    });

    test('FR-CNF-10 toString summarises without a percentage', () {
      expect(label().toString(),
          'ParsedLabel(0 nutrients, 0 ingredients, scan partial)');
    });
  });
}
