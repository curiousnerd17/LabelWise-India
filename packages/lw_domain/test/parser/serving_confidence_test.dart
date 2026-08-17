import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// M11a — **S5b resolves, S8 scores, assembly assembles.**
///
/// These tests exist to hold that boundary. Serving figures reach S8 carrying a
/// `ParseStrength` and nothing else; S8 turns that into a `Confidence` through
/// the *same* `ConfidencePolicy` the nutrient loop uses. Nothing downstream may
/// recompute it, and no serving-specific rule exists anywhere.
void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  final Version pack = Version(1, 0, 0);
  int nextIndex = 0;

  ServingCandidate candidate(
    ServingField field,
    Quantity value, {
    ParseStrength strength = ParseStrength.exact,
    List<int>? indices,
  }) =>
      ServingCandidate(
        field: field,
        quantity: value,
        parseStrength: strength,
        region: box(0, 0, 100, 20),
        sourceIndices: indices ?? <int>[nextIndex++],
        matchedBy: RuleId('rule.serving.marker'),
      );

  ServingResolution resolution({
    ServingOutcome? size,
    ServingOutcome? perPack,
    ServingOutcome? net,
  }) {
    final Map<ServingField, ServingOutcome> outcomes =
        <ServingField, ServingOutcome>{
      ServingField.servingSize: size ?? const ServingNotDeclared(),
      ServingField.servingsPerPack: perPack ?? const ServingNotDeclared(),
      ServingField.netQuantity: net ?? const ServingNotDeclared(),
    };
    Quantity? valueOf(ServingField f) {
      final ServingOutcome o = outcomes[f]!;
      return o is ServingResolved ? o.candidate.quantity : null;
    }

    return ServingResolution(
      facts: ServingFacts(
        servingSize: valueOf(ServingField.servingSize),
        servingsPerPack: valueOf(ServingField.servingsPerPack),
        netQuantity: valueOf(ServingField.netQuantity),
      ),
      outcomes: outcomes,
    );
  }

  TypedField typed(NutrientId nutrient, {Basis basis = Basis.per100g}) =>
      TypedField(
        nutrient: nutrient,
        quantity: const Quantity.exact(800, Unit.gram),
        basis: basis,
        labelStrength: ParseStrength.exact,
        basisStrength: ParseStrength.exact,
        unitStrength: ParseStrength.exact,
        unitWasExpected: true,
        region: box(0, 30, 100, 60),
        sourceIndices: <int>[900 + nextIndex++],
        matchedBy: RuleId('rule.resolve.synonym'),
      );

  ValidatedFields validated({
    List<TypedField> fields = const <TypedField>[],
    List<InvariantResult> results = const <InvariantResult>[],
    ServingFacts serving = ServingFacts.none,
  }) =>
      ValidatedFields(
        fields: fields,
        results: results,
        serving: serving,
        nutritionPanelPresent: true,
      );

  ScoredFields score(
    ValidatedFields v, {
    ServingResolution? serving,
    ConfidencePolicy? policy,
  }) {
    final StageResult<ScoredFields> out = assignConfidence(
      v,
      rulePackVersion: pack,
      policy: policy,
      servingResolution: serving,
    );
    expect(out.isSuccess, isTrue, reason: 'expected S8 success');
    return out.valueOrNull!;
  }

  FieldState stateFor(ScoredFields s, ServingField f) =>
      s.servingStates[f] ?? const NotDeclaredField();

  InvariantResult servingInvariant(
    InvariantId id,
    InvariantOutcome outcome,
    List<ServingField> participants,
  ) =>
      InvariantResult(
        invariantId: id,
        outcome: outcome,
        participatingFields: <InvariantSubject>[
          for (final ServingField f in participants) ServingSubject(f),
        ],
      );

  setUp(() => nextIndex = 0);

  group('S8 — a resolved serving figure becomes an ExtractedField', () {
    test('FR-PAR-08 an exact serving size is extracted and scored', () {
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          size: ServingResolved(
            candidate(
              ServingField.servingSize,
              const Quantity.exact(3000, Unit.gram),
            ),
          ),
        ),
      );
      final FieldState state = stateFor(s, ServingField.servingSize);
      expect(state, isA<ExtractedField>());
      final ExtractedField f = state as ExtractedField;
      expect(f.quantity, const Quantity.exact(3000, Unit.gram));
      expect(f.confidence, Confidence.high);
    });

    test('FR-PAR-08 an exact servings-per-pack is extracted and scored', () {
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          perPack: ServingResolved(
            candidate(
              ServingField.servingsPerPack,
              const Quantity.exact(400, Unit.count),
            ),
          ),
        ),
      );
      final FieldState state = stateFor(s, ServingField.servingsPerPack);
      expect(state, isA<ExtractedField>());
      expect((state as ExtractedField).confidence, Confidence.high);
    });

    test('FR-PAR-08 an exact net quantity is extracted and scored', () {
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          net: ServingResolved(
            candidate(
              ServingField.netQuantity,
              const Quantity.exact(12000, Unit.gram),
            ),
          ),
        ),
      );
      expect(stateFor(s, ServingField.netQuantity), isA<ExtractedField>());
    });

    test('the basis names what the figure is expressed against', () {
      // A serve size is one serve; a net quantity and a pack count are per
      // pack. Verified against Basis's own definition — "the reference
      // quantity a value is expressed against" — not assumed.
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          size: ServingResolved(candidate(
              ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
          perPack: ServingResolved(candidate(ServingField.servingsPerPack,
              const Quantity.exact(400, Unit.count))),
          net: ServingResolved(candidate(ServingField.netQuantity,
              const Quantity.exact(12000, Unit.gram))),
        ),
      );
      expect(stateFor(s, ServingField.servingSize).basisOrNull, Basis.perServe);
      expect(
          stateFor(s, ServingField.servingsPerPack).basisOrNull, Basis.perPack);
      expect(stateFor(s, ServingField.netQuantity).basisOrNull, Basis.perPack);
    });
  });

  group('S8 — the existing policy scores serving, with no new rule', () {
    test('ADR-0010 a weaker parse strength cannot reach HIGH', () {
      // The same table that scores nutrients. A heuristic marker match is a
      // heuristic read whatever it read.
      for (final (ParseStrength strength, Confidence expected)
          in <(ParseStrength, Confidence)>[
        (ParseStrength.exact, Confidence.high),
        (ParseStrength.normalised, Confidence.medium),
        (ParseStrength.heuristic, Confidence.low),
      ]) {
        final ScoredFields s = score(
          validated(),
          serving: resolution(
            size: ServingResolved(
              candidate(
                ServingField.servingSize,
                const Quantity.exact(3000, Unit.gram),
                strength: strength,
              ),
            ),
          ),
        );
        expect(
          (stateFor(s, ServingField.servingSize) as ExtractedField).confidence,
          expected,
          reason: '${strength.name} must score ${expected.name}',
        );
      }
    });

    test('ADR-0012 a caller-supplied policy governs serving too', () {
      // Proof there is no second, serving-specific policy hiding anywhere: an
      // empty policy falls back to its own fail-safe for serving exactly as it
      // does for nutrients.
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          size: ServingResolved(candidate(
              ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
        ),
        policy: ConfidencePolicy(const <ConfidenceRule>[]),
      );
      expect(
        (stateFor(s, ServingField.servingSize) as ExtractedField).confidence,
        Confidence.low,
      );
    });
  });

  group('S8 — FR-CNF-05 applies to serving through the existing S3 signal', () {
    test('a FAILED INV-09 caps the serving size', () {
      // INV-09 names ServingSubject(servingSize) and ServingSubject(
      // netQuantity) as participants, so the existing participation mechanism
      // supplies S3 with no new signal.
      final ScoredFields s = score(
        validated(results: <InvariantResult>[
          servingInvariant(
            InvariantId.inv09,
            InvariantOutcome.failed,
            <ServingField>[ServingField.servingSize, ServingField.netQuantity],
          ),
        ]),
        serving: resolution(
          size: ServingResolved(candidate(
              ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
        ),
      );
      expect(
        (stateFor(s, ServingField.servingSize) as ExtractedField).confidence,
        Confidence.low,
        reason: 'a serve larger than the pack is not a HIGH-confidence read',
      );
    });

    test('a FAILED INV-10 caps the servings-per-pack count', () {
      final ScoredFields s = score(
        validated(results: <InvariantResult>[
          servingInvariant(
            InvariantId.inv10,
            InvariantOutcome.failed,
            <ServingField>[ServingField.servingsPerPack],
          ),
        ]),
        serving: resolution(
          perPack: ServingResolved(candidate(ServingField.servingsPerPack,
              const Quantity.exact(400, Unit.count))),
        ),
      );
      expect(
        (stateFor(s, ServingField.servingsPerPack) as ExtractedField)
            .confidence,
        Confidence.low,
      );
    });

    test('FR-CNF-05 only the participating field is capped', () {
      // A failure naming the count must not punish a cleanly read net weight.
      final ScoredFields s = score(
        validated(results: <InvariantResult>[
          servingInvariant(
            InvariantId.inv10,
            InvariantOutcome.failed,
            <ServingField>[ServingField.servingsPerPack],
          ),
        ]),
        serving: resolution(
          perPack: ServingResolved(candidate(ServingField.servingsPerPack,
              const Quantity.exact(400, Unit.count))),
          net: ServingResolved(candidate(ServingField.netQuantity,
              const Quantity.exact(12000, Unit.gram))),
        ),
      );
      expect(
        (stateFor(s, ServingField.servingsPerPack) as ExtractedField)
            .confidence,
        Confidence.low,
      );
      expect(
        (stateFor(s, ServingField.netQuantity) as ExtractedField).confidence,
        Confidence.high,
      );
    });

    test('PT-21 an INDETERMINATE invariant neither caps nor supports HIGH', () {
      final ScoredFields s = score(
        validated(results: <InvariantResult>[
          servingInvariant(
            InvariantId.inv09,
            InvariantOutcome.indeterminate,
            <ServingField>[ServingField.servingSize],
          ),
        ]),
        serving: resolution(
          size: ServingResolved(candidate(
              ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
        ),
      );
      expect(
        (stateFor(s, ServingField.servingSize) as ExtractedField).confidence,
        Confidence.high,
        reason: 'an unresolvable comparison is not evidence of error',
      );
    });

    test('a PASSED invariant leaves the parse strength governing', () {
      final ScoredFields s = score(
        validated(results: <InvariantResult>[
          servingInvariant(
            InvariantId.inv09,
            InvariantOutcome.passed,
            <ServingField>[ServingField.servingSize],
          ),
        ]),
        serving: resolution(
          size: ServingResolved(candidate(
            ServingField.servingSize,
            const Quantity.exact(3000, Unit.gram),
            strength: ParseStrength.normalised,
          )),
        ),
      );
      expect(
        (stateFor(s, ServingField.servingSize) as ExtractedField).confidence,
        Confidence.medium,
      );
    });
  });

  group('S8 — confidence never promotes an unresolved figure', () {
    test('MI-08 an absent figure stays NotDeclared', () {
      final ScoredFields s = score(validated(), serving: resolution());
      expect(stateFor(s, ServingField.servingSize), isA<NotDeclaredField>());
      expect(stateFor(s, ServingField.netQuantity), isA<NotDeclaredField>());
    });

    test('MI-08 a conflicting figure stays Unresolved, with its reason', () {
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          size: ServingUnresolved(
            reason: UnresolvedReason.ambiguousMatch,
            candidates: <ServingCandidate>[
              candidate(ServingField.servingSize,
                  const Quantity.exact(3000, Unit.gram)),
              candidate(ServingField.servingSize,
                  const Quantity.exact(4000, Unit.gram)),
            ],
          ),
        ),
      );
      final FieldState state = stateFor(s, ServingField.servingSize);
      expect(state, isA<UnresolvedField>());
      expect(
          (state as UnresolvedField).reason, UnresolvedReason.ambiguousMatch);
      expect(state.quantityOrNull, isNull,
          reason: 'an unresolved figure carries no value to be trusted');
      expect(state.confidenceOrNull, isNull,
          reason: 'confidence must never make an unresolved value resolved');
    });

    test('an unresolved figure with no candidate still records provenance', () {
      // S5b saw a line naming the field and could not read it at all, so there
      // is no marker candidate to attribute the outcome to. The provenance is
      // derived rather than extracted, because nothing was successfully read
      // from a region.
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          net: ServingUnresolved(
            reason: UnresolvedReason.ambiguousMatch,
            candidates: const <ServingCandidate>[],
          ),
        ),
      );
      final UnresolvedField f =
          stateFor(s, ServingField.netQuantity) as UnresolvedField;
      expect(f.reason, UnresolvedReason.ambiguousMatch);
      expect(f.provenance.origin, FieldOrigin.derived);
      expect(f.provenance.parseRuleId, RuleId('rule.serving.unread'));
      expect(f.provenance.sourceRegion, isNull);
    });

    test('an unresolved figure with candidates points at where it was read',
        () {
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          net: ServingUnresolved(
            reason: UnresolvedReason.ambiguousMatch,
            candidates: <ServingCandidate>[
              candidate(ServingField.netQuantity,
                  const Quantity.exact(12000, Unit.gram)),
            ],
          ),
        ),
      );
      final UnresolvedField f =
          stateFor(s, ServingField.netQuantity) as UnresolvedField;
      expect(f.provenance.origin, FieldOrigin.extracted,
          reason: 'a figure we found and could not use was still found');
      expect(f.provenance.sourceRegion, box(0, 0, 100, 20));
    });

    test('FR-ERR-03 NotDeclared and Unresolved stay distinguishable', () {
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          size: ServingUnresolved(
            reason: UnresolvedReason.ambiguousMatch,
            candidates: <ServingCandidate>[
              candidate(ServingField.servingSize,
                  const Quantity.exact(3000, Unit.gram)),
            ],
          ),
        ),
      );
      expect(stateFor(s, ServingField.servingSize), isA<UnresolvedField>());
      expect(stateFor(s, ServingField.netQuantity), isA<NotDeclaredField>());
    });
  });

  group('S8 — provenance survives S5b to S8', () {
    test('ADR-0009 the source region and marker rule are preserved', () {
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          size: ServingResolved(candidate(
              ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
        ),
      );
      final Provenance p =
          (stateFor(s, ServingField.servingSize) as ExtractedField).provenance;
      expect(p.origin, FieldOrigin.extracted,
          reason: 'a figure read from a region is extracted, not derived');
      expect(p.sourceRegion, box(0, 0, 100, 20));
      expect(p.parseRuleId, RuleId('rule.serving.marker'));
      expect(p.parseStrength, ParseStrength.exact);
      expect(p.rulePackVersion, pack);
    });

    test('the qualifier survives unchanged', () {
      // MI-15: a qualifier never changes confidence, and it must not be lost
      // on the way through scoring either.
      final ScoredFields s = score(
        validated(),
        serving: resolution(
          perPack: ServingResolved(candidate(
            ServingField.servingsPerPack,
            const Quantity.approximately(400, Unit.count),
          )),
        ),
      );
      final ExtractedField f =
          stateFor(s, ServingField.servingsPerPack) as ExtractedField;
      expect(f.quantity.qualifier, Qualifier.approximately);
      expect(f.confidence, Confidence.high,
          reason: 'precision about imprecision is still a good read');
    });
  });

  group('S8 — nothing that worked before changes', () {
    test('nutrient scoring is untouched when serving is supplied', () {
      final ScoredFields with_ = score(
        validated(fields: <TypedField>[typed(NutrientId.protein)]),
        serving: resolution(
          size: ServingResolved(candidate(
              ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
        ),
      );
      expect(with_.confidenceFor(NutrientId.protein, Basis.per100g),
          Confidence.high);
    });

    test('omitting the resolution leaves servingStates empty', () {
      // Every pre-M11 caller gets exactly today's behaviour.
      final ScoredFields s =
          score(validated(fields: <TypedField>[typed(NutrientId.protein)]));
      expect(s.servingStates, isEmpty);
      expect(
          s.confidenceFor(NutrientId.protein, Basis.per100g), Confidence.high);
    });

    test('ScoredFields.serving is unchanged — S7 input contract intact', () {
      final ScoredFields s = score(
        validated(
            serving: const ServingFacts(
          servingSize: Quantity.exact(3000, Unit.gram),
        )),
      );
      expect(s.serving.servingSize, const Quantity.exact(3000, Unit.gram));
    });

    test('FR-PAR-02 scoring is deterministic', () {
      final ServingResolution r = resolution(
        size: ServingResolved(candidate(
            ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
        net: ServingResolved(candidate(
            ServingField.netQuantity, const Quantity.exact(12000, Unit.gram))),
      );
      final ValidatedFields v = validated();
      expect(
        score(v, serving: r).servingStates,
        score(v, serving: r).servingStates,
      );
    });
  });

  group('assembly — passes the S8 state through, computing nothing', () {
    ParsedLabel assemble(ScoredFields s) {
      final StageResult<ParsedLabel> out =
          assembleParsedLabel(s, rulePackVersion: pack);
      expect(out.isSuccess, isTrue, reason: '${out.failureOrNull}');
      return out.valueOrNull!;
    }

    test('a resolved figure arrives as the same ExtractedField', () {
      final ScoredFields s = score(
        validated(fields: <TypedField>[typed(NutrientId.protein)]),
        serving: resolution(
          size: ServingResolved(candidate(
              ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
        ),
      );
      final ParsedLabel p = assemble(s);
      expect(
        p.servingInfo.declaredServingSize,
        same(s.servingStates[ServingField.servingSize]),
        reason: 'assembly selects a state; it does not build one',
      );
    });

    test('an absent figure arrives as NotDeclaredField', () {
      final ParsedLabel p = assemble(score(
        validated(fields: <TypedField>[typed(NutrientId.protein)]),
        serving: resolution(),
      ));
      expect(p.servingInfo.declaredServingSize, isA<NotDeclaredField>());
      expect(p.servingInfo.servingsPerPack, isA<NotDeclaredField>());
      expect(p.servingInfo.netQuantity, isA<NotDeclaredField>());
    });

    test('an unresolved figure keeps its reason', () {
      final ParsedLabel p = assemble(score(
        validated(fields: <TypedField>[typed(NutrientId.protein)]),
        serving: resolution(
          net: ServingUnresolved(
            reason: UnresolvedReason.valueNotParseable,
            candidates: <ServingCandidate>[
              candidate(ServingField.netQuantity,
                  const Quantity.exact(12000, Unit.gram)),
            ],
          ),
        ),
      ));
      final FieldState state = p.servingInfo.netQuantity;
      expect(state, isA<UnresolvedField>());
      expect((state as UnresolvedField).reason,
          UnresolvedReason.valueNotParseable);
    });

    test('M9 fallback survives when S5b did not run', () {
      // The pre-M11 path: no resolution supplied, so assembly keeps reporting
      // the three figures as unresolved rather than inventing absence.
      final ParsedLabel p = assemble(
          score(validated(fields: <TypedField>[typed(NutrientId.protein)])));
      expect(p.servingInfo.declaredServingSize, isA<UnresolvedField>());
    });

    test('v1.6 reconciliation stays null — it is a Layer 1 output', () {
      final ParsedLabel p = assemble(score(
        validated(fields: <TypedField>[typed(NutrientId.protein)]),
        serving: resolution(
          size: ServingResolved(candidate(
              ServingField.servingSize, const Quantity.exact(3000, Unit.gram))),
        ),
      ));
      expect(p.servingInfo.reconciliation, isNull);
    });
  });
}
