import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **Three outcomes, because two of them are not `FieldState`s.**
///
/// The union exists because "the arithmetic was refused" and "the pack
/// gazettes no denominator" are states in which the label was read perfectly.
/// `FieldState` can only say a value is extracted, derived, user-supplied,
/// unresolved or not declared — and every `UnresolvedReason` blames the
/// parser. Saying either of these in that vocabulary would be a lie about
/// where the limitation lies.
void main() {
  final Version pack = Version(0, 1, 0);

  FieldState derived(int scaled, {Basis basis = Basis.per100g}) => DerivedField(
        quantity: Quantity.exact(scaled, Unit.gram),
        basis: basis,
        provenance: Provenance.factual(
          parseRuleId: RuleId('rule.l1.scale-to-pack'),
          rulePackVersion: pack,
        ),
        confidence: Confidence.high,
      );

  group('ComputedFactualValue — wraps, never re-represents', () {
    test('it holds the FieldState it was given', () {
      final FieldState f = derived(600);
      expect(ComputedFactualValue(f).field, same(f));
    });

    test('the wrapped field keeps its own quantity, basis and confidence', () {
      // The point of wrapping rather than copying: a consumer that already
      // understands FieldState needs no second vocabulary.
      final ComputedFactualValue v =
          ComputedFactualValue(derived(600, basis: Basis.perPack));
      final DerivedField f = v.field as DerivedField;
      expect(f.quantity, const Quantity.exact(600, Unit.gram));
      expect(f.basis, Basis.perPack);
      expect(f.confidence, Confidence.high);
    });

    test('the wrapped provenance is factual, with no pipeline stage', () {
      final DerivedField f =
          (ComputedFactualValue(derived(600)).field) as DerivedField;
      expect(f.provenance.origin, FieldOrigin.derived);
      expect(f.provenance.producedByStage, isNull);
    });

    test('any FieldState variant may be wrapped, not only DerivedField', () {
      // A normalisation finding that merely restates a declared value wraps
      // the ExtractedField as it stands.
      final FieldState extracted = ExtractedField(
        quantity: const Quantity.exact(4000, Unit.milligram),
        basis: Basis.per100g,
        provenance: Provenance.extracted(
          producedByStage: PipelineStage.fieldResolution,
          parseRuleId: RuleId('rule.resolve.synonym'),
          parseStrength: ParseStrength.exact,
          sourceRegion: RegionRef(left: 0, top: 0, right: 10, bottom: 10),
          rulePackVersion: pack,
        ),
        confidence: Confidence.high,
      );
      expect(ComputedFactualValue(extracted).field, extracted);
    });

    test('two computed values wrapping equal fields compare equal', () {
      expect(ComputedFactualValue(derived(600)),
          ComputedFactualValue(derived(600)));
      expect(ComputedFactualValue(derived(600)).hashCode,
          ComputedFactualValue(derived(600)).hashCode);
    });

    test('a different wrapped field compares unequal', () {
      expect(ComputedFactualValue(derived(600)),
          isNot(ComputedFactualValue(derived(700))));
      expect(ComputedFactualValue(derived(600)),
          isNot(ComputedFactualValue(derived(600, basis: Basis.perServe))));
    });
  });

  group('NotComputableFactualValue — the arithmetic declined', () {
    test('all instances compare equal', () {
      expect(
          const NotComputableFactualValue(), const NotComputableFactualValue());
      expect(const NotComputableFactualValue().hashCode,
          const NotComputableFactualValue().hashCode);
    });

    test('it carries no reason code, by design', () {
      // The finding's messageId names the figure. A taxonomy of arithmetic
      // refusals would be vocabulary no corpus has justified.
      expect(const NotComputableFactualValue().toString(),
          'NotComputableFactualValue()');
    });

    test('it is const-constructible', () {
      const FactualValue v = NotComputableFactualValue();
      expect(v, isA<NotComputableFactualValue>());
    });
  });

  group('NoDenominatorFactualValue — the pack gazettes none', () {
    test('all instances compare equal', () {
      expect(
          const NoDenominatorFactualValue(), const NoDenominatorFactualValue());
      expect(const NoDenominatorFactualValue().hashCode,
          const NoDenominatorFactualValue().hashCode);
    });

    test('it is const-constructible', () {
      const FactualValue v = NoDenominatorFactualValue();
      expect(v, isA<NoDenominatorFactualValue>());
    });
  });

  group('FactualValue — the union', () {
    test('the three variants never compare equal to one another', () {
      // The distinction that earns the union: "could not compute" and "no
      // denominator exists" are different sentences, and neither is a value.
      expect(const NotComputableFactualValue(),
          isNot(const NoDenominatorFactualValue()));
      expect(ComputedFactualValue(derived(600)),
          isNot(const NotComputableFactualValue()));
      expect(ComputedFactualValue(derived(600)),
          isNot(const NoDenominatorFactualValue()));
    });

    test('all three are FactualValue', () {
      expect(ComputedFactualValue(derived(600)), isA<FactualValue>());
      expect(const NotComputableFactualValue(), isA<FactualValue>());
      expect(const NoDenominatorFactualValue(), isA<FactualValue>());
    });

    test('a switch over the union is exhaustive at compile time', () {
      String describe(FactualValue v) => switch (v) {
            ComputedFactualValue() => 'computed',
            NotComputableFactualValue() => 'not-computable',
            NoDenominatorFactualValue() => 'no-denominator',
          };
      expect(describe(ComputedFactualValue(derived(600))), 'computed');
      expect(describe(const NotComputableFactualValue()), 'not-computable');
      expect(describe(const NoDenominatorFactualValue()), 'no-denominator');
    });

    test('no variant is a FieldState, and FieldState is untouched', () {
      // The narrowing is localised: Layer 1 wraps the existing vocabulary and
      // does not join it.
      expect(const NotComputableFactualValue(), isNot(isA<FieldState>()));
      expect(const NotDeclaredField(), isNot(isA<FactualValue>()));
      expect(UnresolvedReason.values, hasLength(5),
          reason: 'M13 added no parser failure reason');
    });
  });
}
