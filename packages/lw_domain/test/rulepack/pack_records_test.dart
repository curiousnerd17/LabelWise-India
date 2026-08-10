import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  Source source(String id, {EvidenceStrength? strength}) => Source(
        sourceId: SourceId(id),
        title: 'A title',
        publisher: 'A publisher',
        publicationDate: '2020-12-14',
        accessDate: '2026-08-04',
        sourceType: SourceType.regulation,
        evidenceStrength: strength ?? EvidenceStrength.established,
      );

  Category category(
    String id, {
    CategoryStatus status = CategoryStatus.priority,
    List<InvariantId> excluded = const <InvariantId>[],
  }) =>
      Category(
        categoryId: CategoryId(id),
        nameMessageId: MessageId('msg.category.x'),
        defaultBasis: Basis.per100g,
        status: status,
        inapplicableInvariants: excluded,
      );

  RdaDenominator denominator(NutrientId n, int scaled, Unit unit) =>
      RdaDenominator(
        constantId: ConstantId('const.rda.${n.name}'),
        nutrient: n,
        value: Quantity.exact(scaled, unit),
        sourceRefs: <SourceId>[SourceId('src.fssai.labelling.2020')],
      );

  group('Source — FR-KB-05 records who said it and when we looked', () {
    test('FR-KB-05 the minimum record is present', () {
      final Source s = source('src.fssai.labelling.2020');
      expect(s.sourceId.value, 'src.fssai.labelling.2020');
      expect(s.title, isNotEmpty);
      expect(s.publisher, isNotEmpty);
      expect(s.publicationDate, isNotEmpty);
      expect(s.accessDate, isNotEmpty);
    });

    test('MI-07 dates are recorded strings, not wall-clock values', () {
      // A DateTime here would be a clock value in a domain type, which the
      // static check forbids outright. It would also invent a day and a
      // timezone for sources printed with a year alone.
      expect(source('src.a').publicationDate, isA<String>());
      expect(source('src.a').accessDate, isA<String>());
    });

    test('FR-KB-07 evidence strength has exactly three levels', () {
      expect(EvidenceStrength.values, hasLength(3));
      expect(
        EvidenceStrength.values.map((EvidenceStrength e) => e.name),
        <String>['established', 'limited', 'contested'],
      );
    });

    test('B6 source type distinguishes regulation from study', () {
      // Layer 1 may rest only on the former. A regulation states what is
      // required; a study states what was observed.
      expect(SourceType.values, hasLength(4));
      expect(SourceType.values, contains(SourceType.regulation));
      expect(SourceType.values, contains(SourceType.peerReviewed));
    });

    test('P4 compares by value across every field', () {
      expect(source('src.a'), source('src.a'));
      expect(source('src.a').hashCode, source('src.a').hashCode);
      expect(source('src.a'), isNot(source('src.b')));
      expect(source('src.a'),
          isNot(source('src.a', strength: EvidenceStrength.contested)));
    });

    test('toString names the source and its type', () {
      expect(source('src.a').toString(), contains('src.a'));
      expect(source('src.a').toString(), contains('regulation'));
    });
  });

  group('SourceRegistry — the resolution target for MI-05', () {
    test('MI-05 a registered source resolves', () {
      final SourceRegistry r =
          SourceRegistry(<Source>[source('src.a'), source('src.b')]);
      expect(r[SourceId('src.a')]!.sourceId.value, 'src.a');
      expect(r.contains(SourceId('src.b')), isTrue);
      expect(r.length, 2);
    });

    test('MI-05 an unregistered source does not resolve', () {
      final SourceRegistry r = SourceRegistry(<Source>[source('src.a')]);
      expect(r[SourceId('src.zz')], isNull);
      expect(r.contains(SourceId('src.zz')), isFalse);
    });

    test('a duplicate source identifier is refused', () {
      // Two entries under one key make every citation mean "whichever came
      // first" — a silent choice, and silent choices about evidence are the
      // worst kind.
      expect(
        () => SourceRegistry(<Source>[source('src.a'), source('src.a')]),
        throwsArgumentError,
      );
    });

    test('FR-PAR-02 pack order is preserved, not sorted', () {
      final SourceRegistry r = SourceRegistry(<Source>[
        source('src.z'),
        source('src.a'),
      ]);
      expect(
        r.sources.map((Source s) => s.sourceId.value),
        <String>['src.z', 'src.a'],
      );
    });

    test('FR-KB-01 the list is unmodifiable once built', () {
      final SourceRegistry r = SourceRegistry(<Source>[source('src.a')]);
      expect(() => r.sources.add(source('src.b')), throwsUnsupportedError);
    });
  });

  group('Category — FR-CAT-02 an attribute, never a precondition', () {
    test('FR-CAT-04 inapplicable invariants are declarative data', () {
      // The mechanism by which INV-06 stops applying to beverages with no
      // category branch anywhere in Dart.
      final Category c = category('cat.beverages',
          status: CategoryStatus.verificationOnly,
          excluded: <InvariantId>[InvariantId.inv06]);
      expect(c.excludes(InvariantId.inv06), isTrue);
      expect(c.excludes(InvariantId.inv02), isFalse);
    });

    test('FR-CAT-04 a category with no exclusions excludes nothing', () {
      expect(category('cat.biscuits').inapplicableInvariants, isEmpty);
      expect(category('cat.biscuits').excludes(InvariantId.inv06), isFalse);
    });

    test('ADR-0024 the fifth category is marked, not hidden', () {
      // VERIFICATION_ONLY is not held to the accuracy bar, and saying so in
      // data is what keeps the published figure honest.
      expect(CategoryStatus.values, hasLength(3));
      expect(
        category('cat.beverages', status: CategoryStatus.verificationOnly)
            .status,
        CategoryStatus.verificationOnly,
      );
    });

    test('B8 the display name is an identifier, not text', () {
      expect(category('cat.biscuits').nameMessageId, isA<MessageId>());
    });

    test('P4 compares by value, including the exclusion list', () {
      expect(category('cat.a'), category('cat.a'));
      expect(category('cat.a').hashCode, category('cat.a').hashCode);
      expect(category('cat.a'), isNot(category('cat.b')));
      expect(
        category('cat.a'),
        isNot(category('cat.a', excluded: <InvariantId>[InvariantId.inv06])),
      );
      expect(
        category('cat.a', excluded: <InvariantId>[InvariantId.inv06]),
        isNot(category('cat.a', excluded: <InvariantId>[InvariantId.inv07])),
      );
    });

    test('FR-KB-01 the exclusion list is unmodifiable once built', () {
      final Category c = category('cat.a');
      expect(() => c.inapplicableInvariants.add(InvariantId.inv01),
          throwsUnsupportedError);
    });
  });

  group('CategoryTable — FR-CAT-03 adding one is a data change', () {
    test('a declared category resolves', () {
      final CategoryTable t = CategoryTable(<Category>[
        category('cat.biscuits'),
        category('cat.chips'),
      ]);
      expect(t[CategoryId('cat.chips')]!.categoryId.value, 'cat.chips');
      expect(t.contains(CategoryId('cat.biscuits')), isTrue);
      expect(t.length, 2);
    });

    test('FR-CAT-05 an unknown category resolves to null, not a failure', () {
      // A product of unknown category must still produce a complete result.
      // Null here is a normal answer the caller carries on from.
      final CategoryTable t = CategoryTable(<Category>[category('cat.a')]);
      expect(t[CategoryId('cat.unheard-of')], isNull);
      expect(t.contains(CategoryId('cat.unheard-of')), isFalse);
    });

    test('a duplicate category identifier is refused', () {
      expect(
        () => CategoryTable(<Category>[category('cat.a'), category('cat.a')]),
        throwsArgumentError,
      );
    });

    test('FR-KB-01 the list is unmodifiable once built', () {
      final CategoryTable t = CategoryTable(<Category>[category('cat.a')]);
      expect(() => t.categories.add(category('cat.b')), throwsUnsupportedError);
    });
  });

  group('RdaTable — NFR-MNT-06 gazetted figures are data', () {
    test('FR-L1-04 a denominator resolves by nutrient', () {
      final RdaTable t = RdaTable(<RdaDenominator>[
        denominator(NutrientId.sodium, 20000, Unit.milligram),
        denominator(NutrientId.energy, 20000, Unit.kilocalorie),
      ]);
      expect(t[NutrientId.sodium]!.value,
          const Quantity.exact(20000, Unit.milligram));
      expect(t.contains(NutrientId.energy), isTrue);
      expect(t.length, 2);
    });

    test('FR-ERR-03 a nutrient with no gazetted value resolves to null', () {
      // "No daily value is gazetted for this nutrient" and "this nutrient is
      // absent from the label" are different facts one level apart.
      final RdaTable t = RdaTable(<RdaDenominator>[
        denominator(NutrientId.sodium, 20000, Unit.milligram),
      ]);
      expect(t[NutrientId.cholesterol], isNull);
      expect(t.contains(NutrientId.cholesterol), isFalse);
    });

    test('two denominators for one nutrient are refused', () {
      // Not a preference to resolve — a pack defect that would make every
      // percentage silently depend on ordering.
      expect(
        () => RdaTable(<RdaDenominator>[
          denominator(NutrientId.sodium, 20000, Unit.milligram),
          denominator(NutrientId.sodium, 24000, Unit.milligram),
        ]),
        throwsArgumentError,
      );
    });

    test('FR-KB-04 a denominator with no citation is refused', () {
      // A gazetted constant with no source is indistinguishable from a number
      // somebody remembered.
      expect(
        () => RdaDenominator(
          constantId: ConstantId('const.rda.sodium'),
          nutrient: NutrientId.sodium,
          value: const Quantity.exact(20000, Unit.milligram),
          sourceRefs: const <SourceId>[],
        ),
        throwsArgumentError,
      );
    });

    test('MI-11 the value is a scaled integer, never a double', () {
      expect(denominator(NutrientId.sodium, 20000, Unit.milligram).value,
          isA<Quantity>());
    });

    test('P4 compares by value', () {
      expect(denominator(NutrientId.sodium, 20000, Unit.milligram),
          denominator(NutrientId.sodium, 20000, Unit.milligram));
      expect(denominator(NutrientId.sodium, 20000, Unit.milligram).hashCode,
          denominator(NutrientId.sodium, 20000, Unit.milligram).hashCode);
      expect(denominator(NutrientId.sodium, 20000, Unit.milligram),
          isNot(denominator(NutrientId.sodium, 24000, Unit.milligram)));
    });

    test('FR-KB-01 both lists are unmodifiable once built', () {
      final RdaDenominator d =
          denominator(NutrientId.sodium, 20000, Unit.milligram);
      expect(() => d.sourceRefs.add(SourceId('src.x')), throwsUnsupportedError);
      final RdaTable t = RdaTable(<RdaDenominator>[d]);
      expect(() => t.denominators.add(d), throwsUnsupportedError);
    });
  });
}
