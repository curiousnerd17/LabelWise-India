import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

// always_use_package_imports is scoped to files under lib/. Test helpers live
// under test/ and have no package: URI, so a relative import is correct here
// and is not flagged.
import 'support/generators.dart';

/// Property tests PT-01…PT-04, PT-08, PT-15, PT-17, PT-18, PT-19
/// (`TEST_STRATEGY.md` §3.1).
///
/// Examples catch the cases you thought of. Properties catch the ones you did
/// not — which, for a lattice and an interval algebra, is most of them.
void main() {
  group('PT-01…04 the confidence lattice obeys its laws', () {
    test('PT-01 meet never exceeds either operand (MI-04, FR-CNF-06)', () {
      forAll('meet is a lower bound', (Gen gen) {
        final Confidence a = gen.confidence();
        final Confidence b = gen.confidence();
        final Confidence met = a.meet(b);
        expect(met.index, lessThanOrEqualTo(a.index));
        expect(met.index, lessThanOrEqualTo(b.index));
      });
    });

    test('PT-02 meet is commutative', () {
      forAll('meet is commutative', (Gen gen) {
        final Confidence a = gen.confidence();
        final Confidence b = gen.confidence();
        expect(a.meet(b), b.meet(a));
      });
    });

    test('PT-03 meet is associative', () {
      // Associativity plus commutativity is what makes propagation order
      // irrelevant, which is what makes FR-CNF-06 determinism provable rather
      // than merely intended.
      forAll('meet is associative', (Gen gen) {
        final Confidence a = gen.confidence();
        final Confidence b = gen.confidence();
        final Confidence c = gen.confidence();
        expect(a.meet(b).meet(c), a.meet(b.meet(c)));
      });
    });

    test('PT-04 meet is idempotent', () {
      forAll('meet is idempotent', (Gen gen) {
        final Confidence a = gen.confidence();
        expect(a.meet(a), a);
      });
    });

    test('PT-01 meetAll never exceeds its least member', () {
      forAll('meetAll is a lower bound', (Gen gen) {
        final List<Confidence> levels = <Confidence>[
          for (int i = 0; i < gen.intInRange(1, 6); i++) gen.confidence(),
        ];
        final Confidence met = Confidence.meetAll(levels);
        for (final Confidence level in levels) {
          expect(met.index, lessThanOrEqualTo(level.index));
        }
      });
    });
  });

  group('PT-08 unit conversion', () {
    test('PT-08 coarse to fine and back is lossless', () {
      // Converting to a finer unit loses nothing, so the round trip is exact.
      // Converting to a coarser one rounds — that is what scale means, and the
      // property deliberately does not claim otherwise.
      forAll('coarse-fine round trip', (Gen gen) {
        final Dimension dimension = <Dimension>[
          Dimension.mass,
          Dimension.volume,
        ][gen.intInRange(0, 1)];
        final Quantity original = gen.quantityOfDimension(dimension);
        final Unit finer = Unit.values
            .where((Unit u) => u.dimension == dimension)
            .reduce((Unit a, Unit b) =>
                a.baseUnitsPerIncrement <= b.baseUnitsPerIncrement ? a : b);
        final Quantity roundTripped =
            original.convertTo(finer).convertTo(original.unit);
        expect(roundTripped, original);
      });
    });

    test('PT-08 conversion within a dimension is total', () {
      forAll('conversion is total', (Gen gen) {
        final Quantity q = gen.quantity();
        for (final Unit target in Unit.values) {
          if (q.unit.isConvertibleTo(target)) {
            expect(q.convertTo(target).unit, target);
          } else {
            expect(() => q.convertTo(target), throwsA(isA<ArgumentError>()));
          }
        }
      });
    });

    test('PT-08 conversion preserves the qualifier', () {
      forAll('conversion preserves qualifier', (Gen gen) {
        final Quantity q = gen.quantity();
        final Unit target = gen.unitOfDimension(q.unit.dimension);
        expect(q.convertTo(target).qualifier, q.qualifier);
      });
    });
  });

  group('PT-15 Version ordering is a total order', () {
    test('PT-15 ordering is antisymmetric and transitive', () {
      forAll('version total order', (Gen gen) {
        final Version a = gen.version();
        final Version b = gen.version();
        final Version c = gen.version();

        expect(a.compareTo(b).sign, -b.compareTo(a).sign);
        if (a <= b && b <= c) {
          expect(a <= c, isTrue);
        }
        if (a == b) {
          expect(a.compareTo(b), 0);
          expect(a.hashCode, b.hashCode);
        }
      });
    });
  });

  group('PT-17 equality distinguishes qualifiers (MI-14, ADR-0027)', () {
    test('PT-17 LESS_THAN v is never equal to EXACT v', () {
      forAll('qualifier participates in equality', (Gen gen) {
        final int value = gen.scaledValue();
        final Unit unit = gen.unit();
        expect(
          Quantity.lessThan(value, unit),
          isNot(Quantity.exact(value, unit)),
        );
        expect(
          Quantity.greaterThan(value, unit),
          isNot(Quantity.exact(value, unit)),
        );
      });
    });

    test('PT-17 equal quantities agree on hashCode', () {
      forAll('hashCode agrees with equality', (Gen gen) {
        final Quantity a = gen.quantity();
        final Quantity b =
            Quantity.qualified(a.scaledValue, a.unit, a.qualifier);
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });
    });
  });

  group('PT-18 interval comparison is sound (MI-16)', () {
    const ApproximationDeltas none = ApproximationDeltas.none;

    test('PT-18 a definite verdict is never returned for overlapping bounds',
        () {
      // Soundness: whenever comparison claims a definite outcome, that outcome
      // must hold for every pair of values the two intervals admit. Sampling
      // representative members is enough to catch a boundary error.
      forAll('comparison soundness', (Gen gen) {
        final Dimension dimension = Dimension.mass;
        final Quantity a = gen.boundableQuantity(dimension);
        final Quantity b = gen.boundableQuantity(dimension);
        final Trilean verdict = a.isAtMost(b, none);
        final Interval ia = a.boundsIn(none);
        final Interval ib = b.boundsIn(none);

        if (verdict == Trilean.definitelyTrue) {
          // Every member of a is at most every member of b, so in particular
          // the largest of a is at most the smallest of b.
          expect(ia.supremum, isNotNull);
          expect(ia.supremum!, lessThanOrEqualTo(ib.infimum));
        } else if (verdict == Trilean.definitelyFalse) {
          // Every member of a exceeds every member of b.
          expect(ib.supremum, isNotNull);
          expect(ia.infimum, greaterThanOrEqualTo(ib.supremum!));
        }
        // Indeterminate asserts nothing: an unresolvable comparison is the
        // correct outcome, not a weaker one.
      });
    });

    test('PT-18 comparing a value with itself is definitely true', () {
      forAll('reflexivity of isAtMost', (Gen gen) {
        final Quantity q = gen.boundableQuantity(Dimension.mass);
        if (q.qualifier == Qualifier.exact) {
          expect(q.isAtMost(q, none), Trilean.definitelyTrue);
        }
      });
    });

    test('PT-18 isAtLeast is the mirror of isAtMost', () {
      forAll('isAtLeast mirrors isAtMost', (Gen gen) {
        final Quantity a = gen.boundableQuantity(Dimension.mass);
        final Quantity b = gen.boundableQuantity(Dimension.mass);
        expect(a.isAtLeast(b, none), b.isAtMost(a, none));
      });
    });

    test('PT-18 Trilean negation leaves indeterminate untouched', () {
      // An unresolvable comparison stays unresolvable. Negating it into a
      // definite answer would be exactly the coercion ADR-0027 forbids.
      expect(Trilean.indeterminate.negated, Trilean.indeterminate);
      expect(Trilean.definitelyTrue.negated, Trilean.definitelyFalse);
      expect(Trilean.definitelyFalse.negated, Trilean.definitelyTrue);
    });
  });

  group('PT-19 scaling preserves the bound direction', () {
    test('PT-19 a positive scale never changes the qualifier', () {
      forAll('scaling preserves qualifier', (Gen gen) {
        final Quantity q = gen.quantity();
        final Quantity scaled = q.scaledBy(
          numerator: gen.intInRange(1, 500),
          denominator: gen.intInRange(1, 500),
        );
        expect(scaled.qualifier, q.qualifier);
        expect(scaled.unit, q.unit);
      });
    });

    test('PT-19 scaling by one is the identity', () {
      forAll('scaling identity', (Gen gen) {
        final Quantity q = gen.quantity();
        expect(q.scaledBy(numerator: 1, denominator: 1), q);
      });
    });

    test('PT-19 scaling is monotonic in the declared value', () {
      forAll('scaling monotonicity', (Gen gen) {
        final Quantity q = gen.quantity();
        final int factor = gen.intInRange(2, 50);
        final Quantity larger = q.scaledBy(numerator: factor, denominator: 1);
        expect(larger.scaledValue, greaterThanOrEqualTo(q.scaledValue));
      });
    });
  });

  milestone3Properties();
  milestone4Properties();
  milestone5Properties();
}

/// Property tests added by Milestone 5 — PT-06 and PT-16 extended to S3 and
/// S4, and PT-10 implemented for the first time.
///
/// PT-10 has been specified since Phase 1 with nothing to test: ingredient
/// order could not be checked until a stage produced ingredients.
void milestone5Properties() {
  /// Runs S1 → S2 → S3 → S4 over generated input, returning null at the first
  /// stage that declines. Declining is a valid outcome for every stage, so a
  /// null here is not a failure.
  Candidates? pipeline(Gen gen) {
    final StageResult<NormalisedText> s1 =
        normaliseText(gen.recognitionResult(minElements: 1));
    if (!s1.isSuccess) {
      return null;
    }
    final StageResult<LabelLayout> s2 = reconstructLayout(s1.valueOrNull!);
    if (!s2.isSuccess) {
      return null;
    }
    final StageResult<ClassifiedRegions> s3 =
        classifyRegions(s2.valueOrNull!, markers: gen.markerTable());
    if (!s3.isSuccess) {
      return null;
    }
    final StageResult<Candidates> s4 = tokenise(s3.valueOrNull!);
    return s4.isSuccess ? s4.valueOrNull : null;
  }

  group('PT-16 S3 and S4 are total (FR-PAR-17, ARCHITECTURE 6.2)', () {
    test('no generated layout makes S3 throw', () {
      forAll('S3 totality', (Gen gen) {
        final StageResult<NormalisedText> s1 =
            normaliseText(gen.recognitionResult());
        if (!s1.isSuccess) {
          return;
        }
        final StageResult<LabelLayout> s2 = reconstructLayout(s1.valueOrNull!);
        if (!s2.isSuccess) {
          return;
        }
        expect(
          () => classifyRegions(s2.valueOrNull!, markers: gen.markerTable()),
          returnsNormally,
        );
      });
    });

    test('no generated classification makes S4 throw', () {
      forAll('S4 totality', (Gen gen) {
        expect(() => pipeline(gen), returnsNormally);
      });
    });
  });

  group('PT-06 S3 and S4 are deterministic (FR-PAR-02)', () {
    test('the same input classifies and tokenises identically twice', () {
      forAll('S3/S4 determinism', (Gen gen) {
        final Candidates? first = pipeline(Gen(gen.seed));
        final Candidates? second = pipeline(Gen(gen.seed));
        if (first == null || second == null) {
          expect(first == null, second == null);
          return;
        }
        expect(first.nutritionCandidates, second.nutritionCandidates);
        expect(first.ingredientTokens, second.ingredientTokens);
        expect(first.sourceIndices, second.sourceIndices);
      });
    });
  });

  group('PT-10 ingredient declaration order survives (MI-12)', () {
    test('positions are 1-based and contiguous at every nesting level', () {
      // Declaration order is descending by weight and legally meaningful. A
      // gap or a repeat would silently reorder a legal claim.
      void checkLevel(List<IngredientToken> tokens) {
        for (int i = 0; i < tokens.length; i++) {
          expect(tokens[i].position, i + 1);
          checkLevel(tokens[i].children);
        }
      }

      forAll('ingredient order', (Gen gen) {
        final Candidates? c = pipeline(gen);
        if (c == null) {
          return;
        }
        checkLevel(c.ingredientTokens);
      });
    });
  });

  group('M5 provenance chain is never broken (owner requirement)', () {
    test('every candidate and token traces to a real source index', () {
      forAll('provenance chain', (Gen gen) {
        final Candidates? c = pipeline(gen);
        if (c == null) {
          return;
        }
        for (final NutritionCandidate n in c.nutritionCandidates) {
          expect(n.sourceIndices, isNotEmpty);
          expect(n.sourceIndices.every((int i) => i >= 0), isTrue);
        }
        for (final IngredientToken t in c.ingredientTokens) {
          expect(t.allSourceIndices, isNotEmpty);
        }
      });
    });
  });
}

/// Property tests added by Milestone 3 — PT-05, PT-13, PT-14, PT-20.
///
/// Declared separately from `main` above so the Milestone 1 properties remain
/// untouched. `dart test` runs every top-level `main`; this file has one, so
/// these groups are appended to it by the loader below.
void milestone3Properties() {
  final Version pack = Version(0, 1, 0);

  Provenance extractedProv(ParseStrength s) => Provenance.extracted(
        producedByStage: PipelineStage.fieldResolution,
        parseRuleId: RuleId('rule.synonym.test'),
        parseStrength: s,
        sourceRegion: RegionRef(left: 0, top: 0, right: 100, bottom: 100),
        rulePackVersion: pack,
      );

  group('PT-13 no operation crashes on any FieldState variant (MI-08)', () {
    test('PT-13 every variant answers every accessor without throwing', () {
      forAll('FieldState totality', (Gen gen) {
        final List<FieldState> all = <FieldState>[
          ExtractedField(
            quantity: gen.quantity(),
            basis: gen.basis(),
            provenance: extractedProv(gen.parseStrength()),
            confidence: gen.confidence(),
          ),
          DerivedField(
            quantity: gen.quantity(),
            basis: gen.basis(),
            provenance: Provenance.derived(
              producedByStage: PipelineStage.unitNormalisation,
              parseRuleId: RuleId('rule.derive.test'),
              rulePackVersion: pack,
            ),
            confidence: gen.confidence(),
          ),
          UserSuppliedField(
            quantity: gen.quantity(),
            basis: gen.basis(),
            provenance: Provenance.userSupplied(rulePackVersion: pack),
          ),
          UnresolvedField(
            reason: gen.unresolvedReason(),
            provenance: extractedProv(gen.parseStrength()),
          ),
          const NotDeclaredField(),
        ];
        for (final FieldState s in all) {
          expect(() => s.quantityOrNull, returnsNormally);
          expect(() => s.basisOrNull, returnsNormally);
          expect(() => s.confidenceOrNull, returnsNormally);
          expect(() => s.propagatedConfidence, returnsNormally);
          expect(() => s.toString(), returnsNormally);
          expect(() => s.hashCode, returnsNormally);
          expect(s == s, isTrue);
        }
      });
    });

    test('PT-13 unresolved and not-declared are never equal (FR-ERR-03)', () {
      forAll('unresolved != notDeclared', (Gen gen) {
        final FieldState u = UnresolvedField(
          reason: gen.unresolvedReason(),
          provenance: extractedProv(gen.parseStrength()),
        );
        expect(u == const NotDeclaredField(), isFalse);
        expect(const NotDeclaredField() == u, isFalse);
      });
    });
  });

  group('PT-14 a user-supplied field survives re-analysis (FR-COR-04)', () {
    test('PT-14 identity and confidence are unchanged by a round trip', () {
      // Re-analysis reconstructs a field from its own parts. A user-supplied
      // field must come back bit-identical and must still carry no confidence.
      forAll('user-supplied round trip', (Gen gen) {
        final UserSuppliedField original = UserSuppliedField(
          quantity: gen.quantity(),
          basis: gen.basis(),
          provenance: Provenance.userSupplied(rulePackVersion: pack),
        );
        final UserSuppliedField reanalysed = UserSuppliedField(
          quantity: original.quantity,
          basis: original.basis,
          provenance: original.provenance,
        );
        expect(reanalysed, original);
        expect(reanalysed.confidenceOrNull, isNull);
        expect(reanalysed.provenance.origin, FieldOrigin.userSupplied);
        expect(reanalysed.provenance.parseStrength, isNull);
        expect(reanalysed.propagatedConfidence, Confidence.high);
      });
    });
  });

  group('PT-20 a qualifier never changes confidence (MI-15)', () {
    test('PT-20 changing only the qualifier leaves confidence untouched', () {
      // ADR-0027: a label printing "< 0.5 g" is being precise about its
      // imprecision. Reading that correctly is a HIGH-confidence read.
      // Confidence measures how sure we are we read the label right, not how
      // precise the label chose to be.
      forAll('qualifier does not touch confidence', (Gen gen) {
        final int value = gen.scaledValue();
        final Unit unit = gen.unit();
        final Basis basis = gen.basis();
        final Confidence c = gen.confidence();
        final Provenance p = extractedProv(gen.parseStrength());

        final List<Confidence> observed = <Confidence>[
          for (final Qualifier q in Qualifier.values)
            ExtractedField(
              quantity: Quantity.qualified(value, unit, q),
              basis: basis,
              provenance: p,
              confidence: c,
            ).confidence,
        ];
        expect(observed, everyElement(c));
      });
    });

    test('PT-20 provenance records no qualifier at all', () {
      // The structural guarantee behind MI-15: there is no path from Qualifier
      // into Provenance, so a qualifier cannot reach confidence assignment.
      final Provenance p = extractedProv(ParseStrength.exact);
      expect(p.toString().toLowerCase(), isNot(contains('qualifier')));
      expect(p.toString().toLowerCase(), isNot(contains('less_than')));
    });
  });

  group('PT-05 propagation never increases confidence (partial)', () {
    // The full property needs derivation chains, which arrive with Layer 1.
    // What is testable now: a derived field's confidence never exceeds the meet
    // of the confidences it was derived from.
    test('PT-05 a derived field never exceeds the meet of its inputs', () {
      forAll('derived <= meet(inputs)', (Gen gen) {
        final List<FieldState> inputs = <FieldState>[
          for (int i = 0; i < gen.intInRange(1, 4); i++)
            ExtractedField(
              quantity: gen.quantity(),
              basis: gen.basis(),
              provenance: extractedProv(gen.parseStrength()),
              confidence: gen.confidence(),
            ),
        ];
        final Confidence meet = Confidence.meetAll(
          inputs.map((FieldState f) => f.propagatedConfidence),
        );
        final DerivedField derived = DerivedField(
          quantity: gen.quantity(),
          basis: gen.basis(),
          provenance: Provenance.derived(
            producedByStage: PipelineStage.unitNormalisation,
            parseRuleId: RuleId('rule.derive.test'),
            rulePackVersion: pack,
          ),
          confidence: meet,
        );
        for (final FieldState input in inputs) {
          expect(
            derived.propagatedConfidence.index,
            lessThanOrEqualTo(input.propagatedConfidence.index),
          );
        }
      });
    });

    test('PT-05 a user-supplied input never drags the meet below its peers',
        () {
      // User-supplied propagates as HIGH, so it is never the limiting factor.
      forAll('user-supplied is not limiting', (Gen gen) {
        final Confidence other = gen.confidence();
        final UserSuppliedField user = UserSuppliedField(
          quantity: gen.quantity(),
          basis: gen.basis(),
          provenance: Provenance.userSupplied(rulePackVersion: pack),
        );
        final Confidence meet = Confidence.meetAll(<Confidence>[
          user.propagatedConfidence,
          other,
        ]);
        expect(meet, other);
      });
    });
  });
}

/// Property tests added by Milestone 4 — PT-06, PT-16, and two parser
/// invariants provable for the first time now that stages exist.
void milestone4Properties() {
  group('PT-06 stages are deterministic (FR-PAR-02)', () {
    test('PT-06 S1 run twice on identical input yields identical output', () {
      // The property most likely to break by accident — a Set built from
      // unordered input, or grouping by hash, passes CI-03 and still produces
      // input-order-dependent results. Written first for that reason.
      forAll('S1 determinism', (Gen gen) {
        final RecognitionResult input = gen.recognitionResult();
        final StageResult<NormalisedText> a = normaliseText(input);
        final StageResult<NormalisedText> b = normaliseText(input);
        expect(a.isSuccess, b.isSuccess);
        if (a.isSuccess) {
          final NormalisedText x = a.valueOrNull!;
          final NormalisedText y = b.valueOrNull!;
          expect(x.elements.length, y.elements.length);
          for (int i = 0; i < x.elements.length; i++) {
            expect(x.elements[i], y.elements[i]);
          }
        } else {
          expect(a.failureOrNull, b.failureOrNull);
        }
      });
    });

    test('PT-06 S2 is independent of the order elements arrive in', () {
      // Reversing the input must not change the layout. If it does, the
      // clustering depends on arrival order rather than on geometry.
      forAll('S2 order independence', (Gen gen) {
        final NormalisedText forward =
            normaliseText(gen.parseableResult()).valueOrNull!;
        final NormalisedText reversed =
            NormalisedText(elements: forward.elements.reversed.toList());

        final StageResult<LabelLayout> a = reconstructLayout(forward);
        final StageResult<LabelLayout> b = reconstructLayout(reversed);
        expect(a.isSuccess, b.isSuccess);
        if (a.isSuccess) {
          final List<List<int>> x = a.valueOrNull!.lines
              .map((LayoutLine l) => l.sourceIndices)
              .toList();
          final List<List<int>> y = b.valueOrNull!.lines
              .map((LayoutLine l) => l.sourceIndices)
              .toList();
          expect(x.length, y.length);
          for (int i = 0; i < x.length; i++) {
            expect(x[i], y[i]);
          }
        }
      });
    });
  });

  group('PT-16 every stage is total (ARCHITECTURE 6.2)', () {
    test('PT-16 S1 never throws, whatever the input', () {
      forAll('S1 totality', (Gen gen) {
        final RecognitionResult input = gen.recognitionResult();
        expect(() => normaliseText(input), returnsNormally);
        final StageResult<NormalisedText> r = normaliseText(input);
        expect(r.isSuccess ? r.valueOrNull : r.failureOrNull, isNotNull);
      });
    });

    test('PT-16 S2 never throws, whatever S1 produced', () {
      forAll('S2 totality', (Gen gen) {
        final StageResult<NormalisedText> s1 =
            normaliseText(gen.recognitionResult());
        if (!s1.isSuccess) {
          return;
        }
        expect(() => reconstructLayout(s1.valueOrNull!), returnsNormally);
        final StageResult<LabelLayout> r = reconstructLayout(s1.valueOrNull!);
        expect(r.isSuccess ? r.valueOrNull : r.failureOrNull, isNotNull);
      });
    });

    test('PT-16 a failure is never an empty success (FR-PAR-17)', () {
      forAll('no empty success', (Gen gen) {
        final StageResult<NormalisedText> r =
            normaliseText(gen.recognitionResult());
        expect(r.isSuccess, isNot(r.failureOrNull != null));
      });
    });
  });

  group('S1 invariants (FR-PAR-06, FR-OCR-06)', () {
    test('S1 preserves element count and source order', () {
      // Normalisation may change text. It must never add, remove or reorder,
      // because sourceIndex is the mapping every later stage relies on.
      forAll('S1 structure preservation', (Gen gen) {
        final RecognitionResult input = gen.parseableResult();
        final NormalisedText out = normaliseText(input).valueOrNull!;
        expect(out.elements.length, input.elements.length);
        for (int i = 0; i < out.elements.length; i++) {
          expect(out.elements[i].sourceIndex, i);
          expect(out.elements[i].originalText, input.elements[i].text);
          expect(out.elements[i].region, input.elements[i].region);
        }
      });
    });

    test('S1 records a substitution exactly when text changed', () {
      // FR-PAR-06 as an invariant rather than an example: a changed element
      // always carries evidence, and an unchanged one never carries noise.
      forAll('substitution iff changed', (Gen gen) {
        final NormalisedText out =
            normaliseText(gen.parseableResult()).valueOrNull!;
        for (final NormalisedElement e in out.elements) {
          if (e.wasChanged) {
            expect(e.substitutions, isNotEmpty,
                reason: '"\${e.originalText}" -> "\${e.text}" unrecorded');
          } else {
            expect(e.substitutions, isEmpty,
                reason: 'unchanged element carries a substitution');
          }
        }
      });
    });
  });

  group('S2 invariants (FR-PAR-03)', () {
    test('S2 assigns every positioned element to exactly one line', () {
      forAll('line partition', (Gen gen) {
        final NormalisedText s1 =
            normaliseText(gen.parseableResult()).valueOrNull!;
        final StageResult<LabelLayout> s2 = reconstructLayout(s1);
        if (!s2.isSuccess) {
          return;
        }
        final List<int> assigned = <int>[
          for (final LayoutLine l in s2.valueOrNull!.lines) ...l.sourceIndices,
        ];
        final Set<int> unique = assigned.toSet();
        expect(unique.length, assigned.length,
            reason: 'an element appears on two lines');
        final int positioned = s1.elements
            .where((NormalisedElement e) => e.region.height > 0)
            .length;
        expect(assigned.length, positioned);
      });
    });

    test('S2 emits lines top to bottom and columns left to right', () {
      forAll('layout ordering', (Gen gen) {
        final NormalisedText s1 =
            normaliseText(gen.parseableResult()).valueOrNull!;
        final StageResult<LabelLayout> s2 = reconstructLayout(s1);
        if (!s2.isSuccess) {
          return;
        }
        final LabelLayout l = s2.valueOrNull!;
        for (int i = 1; i < l.lines.length; i++) {
          expect(l.lines[i].region.top,
              greaterThanOrEqualTo(l.lines[i - 1].region.top));
        }
        for (int i = 1; i < l.columns.length; i++) {
          expect(l.columns[i].left, greaterThan(l.columns[i - 1].left));
          expect(l.columns[i].index, l.columns[i - 1].index + 1);
        }
      });
    });
  });
}
