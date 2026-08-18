import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **What a Layer 1 finding, or one input to a derivation, is *about*.**
///
/// Structurally identical to `InvariantSubject`, and deliberately not the same
/// type. S7's union answers "which fields participated in this invariant";
/// this one answers "which figure is this factual statement about". They agree
/// today by coincidence of the domain having two kinds of subject, not by
/// contract — and when FR-L1-07 lands, Layer 1 gains an additive variant that
/// no invariant will ever carry. Sharing the type now would make that a change
/// to S7.
void main() {
  group('FindingNutrient', () {
    test('it records the nutrient it is about', () {
      expect(
          const FindingNutrient(NutrientId.sodium).nutrient, NutrientId.sodium);
    });

    test('two subjects for the same nutrient compare equal', () {
      expect(const FindingNutrient(NutrientId.protein),
          const FindingNutrient(NutrientId.protein));
      expect(const FindingNutrient(NutrientId.protein).hashCode,
          const FindingNutrient(NutrientId.protein).hashCode);
    });

    test('different nutrients compare unequal', () {
      expect(const FindingNutrient(NutrientId.protein),
          isNot(const FindingNutrient(NutrientId.sodium)));
    });

    test('every nutrient can be named', () {
      // No nutrient is unreachable as a subject: Layer 1 restates whatever the
      // label declared, and the label chooses.
      for (final NutrientId id in NutrientId.values) {
        expect(FindingNutrient(id).nutrient, id);
      }
    });

    test('toString names the nutrient, for diagnostics only', () {
      expect(const FindingNutrient(NutrientId.sodium).toString(),
          contains('sodium'));
    });
  });

  group('FindingServing', () {
    test('it records the pack figure it is about', () {
      expect(const FindingServing(ServingField.netQuantity).field,
          ServingField.netQuantity);
    });

    test('two subjects for the same figure compare equal', () {
      expect(const FindingServing(ServingField.servingSize),
          const FindingServing(ServingField.servingSize));
      expect(const FindingServing(ServingField.servingSize).hashCode,
          const FindingServing(ServingField.servingSize).hashCode);
    });

    test('different figures compare unequal', () {
      expect(const FindingServing(ServingField.servingSize),
          isNot(const FindingServing(ServingField.servingsPerPack)));
    });

    test('all three serving figures can be named', () {
      for (final ServingField f in ServingField.values) {
        expect(FindingServing(f).field, f);
      }
    });

    test('toString names the figure, for diagnostics only', () {
      expect(const FindingServing(ServingField.netQuantity).toString(),
          contains('netQuantity'));
    });
  });

  group('FindingSubject — the union', () {
    test('the two variants never compare equal to each other', () {
      // A nutrient and a pack figure are different kinds of thing even when
      // both are "about sodium-sized numbers".
      expect(const FindingNutrient(NutrientId.sodium),
          isNot(const FindingServing(ServingField.netQuantity)));
    });

    test('both variants are FindingSubject', () {
      expect(const FindingNutrient(NutrientId.sodium), isA<FindingSubject>());
      expect(const FindingServing(ServingField.netQuantity),
          isA<FindingSubject>());
    });

    test('a switch over the union is exhaustive at compile time', () {
      // The reason the hierarchy is sealed. When FR-L1-07 adds an additive
      // variant, every site like this one stops compiling until it decides
      // what to do — which is the failure mode we want, rather than a silent
      // fallthrough.
      String describe(FindingSubject s) => switch (s) {
            FindingNutrient(nutrient: final NutrientId n) => n.name,
            FindingServing(field: final ServingField f) => f.name,
          };
      expect(describe(const FindingNutrient(NutrientId.energy)), 'energy');
      expect(describe(const FindingServing(ServingField.netQuantity)),
          'netQuantity');
    });

    test('it is distinct from the invariant subject union (M7 untouched)', () {
      // The duplication is intentional and recorded. This asserts the two
      // vocabularies stayed separate rather than one quietly replacing the
      // other.
      expect(const FindingNutrient(NutrientId.sodium),
          isNot(isA<InvariantSubject>()));
      expect(const NutrientSubject(NutrientId.sodium),
          isNot(isA<FindingSubject>()));
    });

    test('subjects are usable as map keys and set members', () {
      // Value equality plus a stable hashCode is what makes grouping findings
      // by subject possible without an identity surprise.
      //
      // Built from a list rather than a set literal: two equal const elements
      // in a literal are a compile-time warning, and the duplicate is the
      // whole point of the test.
      final List<FindingSubject> collected = <FindingSubject>[
        const FindingNutrient(NutrientId.sodium),
        const FindingNutrient(NutrientId.sodium),
        const FindingServing(ServingField.netQuantity),
      ];
      expect(collected.toSet(), hasLength(2));
    });
  });
}
