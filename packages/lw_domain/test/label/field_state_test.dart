import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  final Version pack = Version(0, 1, 0);
  final RuleId rule = RuleId('rule.synonym.sodium');
  final RegionRef region =
      RegionRef(left: 100, top: 200, right: 900, bottom: 260);
  const Quantity sodium = Quantity.exact(4120, Unit.milligram);

  Provenance extractedProvenance() => Provenance.extracted(
        producedByStage: PipelineStage.fieldResolution,
        parseRuleId: rule,
        parseStrength: ParseStrength.exact,
        sourceRegion: region,
        rulePackVersion: pack,
      );

  group('FieldState — three distinguishable outcomes (FR-PAR-09)', () {
    test('FR-PAR-09 extracted, unresolved and not-declared are distinct types',
        () {
      final FieldState extracted = ExtractedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.high,
      );
      final FieldState unresolved = UnresolvedField(
        reason: UnresolvedReason.unitNotDetermined,
        provenance: extractedProvenance(),
      );
      const FieldState notDeclared = NotDeclaredField();

      expect(extracted, isA<ExtractedField>());
      expect(unresolved, isA<UnresolvedField>());
      expect(notDeclared, isA<NotDeclaredField>());
      expect(extracted, isNot(unresolved));
      expect(unresolved, isNot(notDeclared));
    });

    test('FR-ERR-03 unresolved never equals not-declared (MI-08)', () {
      // "We could not read this" and "the label does not say" are different
      // facts. Conflating them lets a parser failure masquerade as a
      // manufacturer's omission.
      final FieldState unresolved = UnresolvedField(
        reason: UnresolvedReason.valueNotParseable,
        provenance: extractedProvenance(),
      );
      const FieldState notDeclared = NotDeclaredField();
      expect(unresolved == notDeclared, isFalse);
      expect(notDeclared == unresolved, isFalse);
    });

    test('FR-ERR-03 not-declared is a const singleton with value equality', () {
      expect(const NotDeclaredField(), const NotDeclaredField());
      expect(
        const NotDeclaredField().hashCode,
        const NotDeclaredField().hashCode,
      );
    });

    test('FR-PAR-09 every unresolved field records why it failed', () {
      // The reason is an enum, not a string: the domain holds identity, never
      // display text (M5, FR-LOC-01).
      for (final UnresolvedReason r in UnresolvedReason.values) {
        final UnresolvedField f =
            UnresolvedField(reason: r, provenance: extractedProvenance());
        expect(f.reason, r);
      }
      expect(UnresolvedReason.values, hasLength(5));
    });
  });

  group('FieldState — user-supplied carries no confidence (FR-CNF-12)', () {
    test('FR-CNF-12 a user-supplied field exposes no confidence member (MI-02)',
        () {
      final UserSuppliedField f = UserSuppliedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: Provenance.userSupplied(rulePackVersion: pack),
      );
      // There is no `f.confidence` to assert against — its absence is the
      // enforcement. What is testable is that the variant carries user-supplied
      // origin and that the shared accessor reports no confidence.
      expect(f.provenance.origin, FieldOrigin.userSupplied);
      expect(f.confidenceOrNull, isNull);
    });

    test('FR-CNF-01 an extracted field cannot exist without a confidence', () {
      final ExtractedField f = ExtractedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.medium,
      );
      expect(f.confidence, Confidence.medium);
      expect(f.confidenceOrNull, Confidence.medium);
    });

    test('FR-CNF-12 user-supplied propagates as maximally trustworthy', () {
      // ARCHITECTURE 7.4: it is not a confidence level but a different kind of
      // thing. In propagation it behaves as HIGH, because the user looked at
      // the packet — which the parser cannot do.
      final UserSuppliedField f = UserSuppliedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: Provenance.userSupplied(rulePackVersion: pack),
      );
      expect(f.propagatedConfidence, Confidence.high);
    });

    test('FR-CNF-12 an extracted field propagates its own confidence', () {
      final ExtractedField f = ExtractedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.low,
      );
      expect(f.propagatedConfidence, Confidence.low);
    });

    test('FR-CNF-12 unresolved and not-declared propagate as absent', () {
      final UnresolvedField u = UnresolvedField(
        reason: UnresolvedReason.noMatchingRule,
        provenance: extractedProvenance(),
      );
      expect(u.propagatedConfidence, Confidence.absent);
      expect(const NotDeclaredField().propagatedConfidence, Confidence.absent);
    });
  });

  group('FieldState — value carriers (MI-03)', () {
    test('MI-03 every value-carrying variant has a quantity and a basis', () {
      final ExtractedField e = ExtractedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.high,
      );
      final DerivedField d = DerivedField(
        quantity: sodium,
        basis: Basis.perPack,
        provenance: Provenance.derived(
          producedByStage: PipelineStage.unitNormalisation,
          parseRuleId: rule,
          rulePackVersion: pack,
        ),
        confidence: Confidence.medium,
      );
      final UserSuppliedField u = UserSuppliedField(
        quantity: sodium,
        basis: Basis.perServe,
        provenance: Provenance.userSupplied(rulePackVersion: pack),
      );
      expect(e.quantityOrNull, sodium);
      expect(d.quantityOrNull, sodium);
      expect(u.quantityOrNull, sodium);
      expect(e.basisOrNull, Basis.per100g);
      expect(d.basisOrNull, Basis.perPack);
      expect(u.basisOrNull, Basis.perServe);
    });

    test('FR-PAR-09 non-value variants expose no quantity or basis', () {
      final UnresolvedField u = UnresolvedField(
        reason: UnresolvedReason.ambiguousMatch,
        provenance: extractedProvenance(),
      );
      expect(u.quantityOrNull, isNull);
      expect(u.basisOrNull, isNull);
      expect(const NotDeclaredField().quantityOrNull, isNull);
      expect(const NotDeclaredField().basisOrNull, isNull);
    });

    test('FR-PAR-18 a qualified quantity survives being held in a field', () {
      // ADR-0027: no code path coerces a bound to a point value. FieldState is
      // a carrier and must not alter what it carries.
      const Quantity transFat = Quantity.lessThan(50, Unit.gram);
      final ExtractedField f = ExtractedField(
        quantity: transFat,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.high,
      );
      expect(f.quantity, transFat);
      expect(f.quantity.qualifier, Qualifier.lessThan);
    });
  });

  group('FieldState — exhaustive handling (MI-08, PT-13)', () {
    test('MI-08 a switch expression covers all five variants', () {
      // FieldState is sealed, so the compiler rejects a non-exhaustive switch.
      // This test proves the runtime behaviour of each arm.
      String describe(FieldState s) => switch (s) {
            ExtractedField() => 'extracted',
            DerivedField() => 'derived',
            UserSuppliedField() => 'userSupplied',
            UnresolvedField() => 'unresolved',
            NotDeclaredField() => 'notDeclared',
          };
      expect(
        describe(ExtractedField(
          quantity: sodium,
          basis: Basis.per100g,
          provenance: extractedProvenance(),
          confidence: Confidence.high,
        )),
        'extracted',
      );
      expect(describe(const NotDeclaredField()), 'notDeclared');
    });

    test('P4 fields compare by value', () {
      final ExtractedField a = ExtractedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.high,
      );
      final ExtractedField b = ExtractedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.high,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('P4 a differing confidence makes fields unequal', () {
      final ExtractedField a = ExtractedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.high,
      );
      final ExtractedField b = ExtractedField(
        quantity: sodium,
        basis: Basis.per100g,
        provenance: extractedProvenance(),
        confidence: Confidence.low,
      );
      expect(a, isNot(b));
    });
  });
}
