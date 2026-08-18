import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// **Implementation M13 — the Layer 1 factual engine.**
///
/// Layer 1 restates and computes. It never judges: there is no field in a
/// finding where "high in sodium" could live, and these tests assert the
/// arithmetic, the citations and the refusals — never a verdict (FR-L1-01, P5).
///
/// Analysed against a `ParsedLabel` produced by the real M12 `parseLabel`
/// pipeline, not a hand-built one. M12 existed to prove the composition; using
/// its output here means Layer 1 is tested against what the parser actually
/// emits rather than what a fixture author imagines it emits.
void main() {
  RegionRef box(int l, int t, int r, int b) =>
      RegionRef(left: l, top: t, right: r, bottom: b);

  RecognitionResult label(List<String> lines, {int height = 60}) =>
      RecognitionResult(
        elements: <RecognitionElement>[
          for (int i = 0; i < lines.length; i++)
            RecognitionElement(
              text: lines[i],
              region: box(100, 1000 + i * 100, 900, 1000 + i * 100 + height),
            ),
        ],
        dominantScript: DominantScript.latin,
      );

  /// Fixture A, as established in M12: one band, header row carries the basis.
  const List<String> fixtureA = <String>[
    'Nutritional Information Per 100 g',
    'Serving Size 30 g',
    'Servings Per Pack 10',
    'Net Quantity 300 g',
    'Energy 450 kcal',
    'Protein 6 g',
    'Total Fat 20 g',
    'Carbohydrate 65 g',
    'Total Sugars 22 g',
    'Sodium 400 mg',
  ];

  const String digest =
      'sha256:33177c6c7a71c5650c3a28d05f95d3c83154507d947612e78af312b6e5d84d46';

  SynonymEntry entry(NutrientId nutrient, String text, Unit unit) =>
      SynonymEntry(
        nutrient: nutrient,
        patterns: <SynonymPattern>[
          SynonymPattern(text: text, strength: ParseStrength.exact),
        ],
        expectedUnits: <Unit>[unit],
      );

  final SourceRegistry sources = SourceRegistry(<Source>[
    Source(
      sourceId: SourceId('src.fssai.labelling.2020'),
      title: 'Labelling and Display Regulations',
      publisher: 'FSSAI',
      publicationDate: '2020-12-14',
      accessDate: '2026-08-04',
      sourceType: SourceType.regulation,
      evidenceStrength: EvidenceStrength.established,
    ),
  ]);

  /// The six gazetted denominators, as the pack declares them. Never inlined
  /// into the engine — the whole point of FR-L1-04 is that they arrive as data.
  RdaDenominator denominator(NutrientId n, String id, Quantity value) =>
      RdaDenominator(
        constantId: ConstantId(id),
        nutrient: n,
        value: value,
        sourceRefs: <SourceId>[SourceId('src.fssai.labelling.2020')],
      );

  RdaTable rdaTable() => RdaTable(<RdaDenominator>[
        denominator(NutrientId.energy, 'const.rda.energy',
            const Quantity.exact(20000, Unit.kilocalorie)),
        denominator(NutrientId.totalFat, 'const.rda.total-fat',
            const Quantity.exact(6700, Unit.gram)),
        denominator(NutrientId.saturatedFat, 'const.rda.saturated-fat',
            const Quantity.exact(2200, Unit.gram)),
        denominator(NutrientId.transFat, 'const.rda.trans-fat',
            const Quantity.exact(200, Unit.gram)),
        denominator(NutrientId.addedSugars, 'const.rda.added-sugars',
            const Quantity.exact(5000, Unit.gram)),
        denominator(NutrientId.sodium, 'const.rda.sodium',
            const Quantity.exact(20000, Unit.milligram)),
      ]);

  RulePack rulePack() => RulePack(
        manifest: RulePackManifest(
          schemaVersion: Version(1, 0, 0),
          packVersion: Version(0, 1, 0),
          minAppVersion: Version(0, 1, 0),
          integrityHash: digest,
          contentLicence: 'CC-BY-4.0',
          generatedAt: '2026-08-04',
        ),
        sources: sources,
        synonyms: SynonymTable(<SynonymEntry>[
          entry(NutrientId.energy, 'Energy', Unit.kilocalorie),
          entry(NutrientId.protein, 'Protein', Unit.gram),
          entry(NutrientId.totalFat, 'Total Fat', Unit.gram),
          entry(NutrientId.carbohydrate, 'Carbohydrate', Unit.gram),
          entry(NutrientId.totalSugars, 'Total Sugars', Unit.gram),
          entry(NutrientId.sodium, 'Sodium', Unit.milligram),
        ]),
        rda: rdaTable(),
        categories: CategoryTable(<Category>[
          Category(
            categoryId: CategoryId('cat.biscuits'),
            nameMessageId: MessageId('msg.category.biscuits'),
            defaultBasis: Basis.per100g,
            status: CategoryStatus.priority,
          ),
        ]),
        advisoryRules: AdvisoryRuleTable(const <AdvisoryRule>[]),
        confidencePolicy: ConfidencePolicy.defaults,
        tolerances: ToleranceTable.defaults,
        approximationDeltas: ApproximationDeltas.none,
        messages: MessageCatalogue(
          locale: 'en',
          reviewed: true,
          messages: <MessageId, String>{
            MessageId('msg.category.biscuits'): 'Biscuits',
          },
        ),
      );

  ParsedLabel parsed(List<String> lines, {CategoryId? category}) {
    final StageResult<ParsedLabel> out = parseLabel(
      label(lines),
      pack: rulePack(),
      declaredCategory: category,
    );
    expect(out.isSuccess, isTrue,
        reason: 'fixture must parse: ${out.failureOrNull}');
    return out.valueOrNull!;
  }

  Layer1Result analyse(ParsedLabel l, {RdaTable? rda}) =>
      analyseFactually(l, rda: rda ?? rdaTable(), sources: sources);

  List<FactualFinding> of(Layer1Result r, FactualFindingKind kind) =>
      r.findings.where((FactualFinding f) => f.kind == kind).toList();

  FactualFinding? about(
    Layer1Result r,
    FactualFindingKind kind,
    NutrientId nutrient, {
    String? message,
  }) {
    for (final FactualFinding f in of(r, kind)) {
      if (f.subject == FindingNutrient(nutrient) &&
          (message == null || f.messageId == MessageId(message))) {
        return f;
      }
    }
    return null;
  }

  // ============================================================ normalisation

  group('L1 — normalisation (FR-L1-02)', () {
    test('a per-100 declaration is restated, not recomputed', () {
      // The label already declares per 100 g. Restating it is the finding; a
      // multiplication would be arithmetic the label did not ask for.
      final FactualFinding? f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.normalisation, NutrientId.sodium,
          message: 'msg.l1.normalisation');
      expect(f, isNotNull);
      final ComputedFactualValue v = f!.value as ComputedFactualValue;
      expect(
          v.field.quantityOrNull, const Quantity.exact(4000, Unit.milligram));
      expect(v.field.basisOrNull, Basis.per100g);
    });

    test('every declared nutrient yields a normalisation finding', () {
      final Layer1Result r = analyse(parsed(fixtureA));
      final Set<FindingSubject> subjects =
          of(r, FactualFindingKind.normalisation)
              .map((FactualFinding f) => f.subject)
              .toSet();
      for (final NutrientId id in <NutrientId>[
        NutrientId.energy,
        NutrientId.protein,
        NutrientId.totalFat,
        NutrientId.carbohydrate,
        NutrientId.totalSugars,
        NutrientId.sodium,
      ]) {
        expect(subjects, contains(FindingNutrient(id)));
      }
    });

    test('an undeclared nutrient produces no normalisation finding', () {
      // Absence is not a value to restate. Emitting one would be the
      // fabrication FR-L1-09 forbids.
      final Layer1Result r = analyse(parsed(fixtureA));
      expect(
          about(r, FactualFindingKind.normalisation, NutrientId.dietaryFibre),
          isNull);
    });

    test('normalisation carries the approved message id', () {
      // Whole-pack findings share `FactualFindingKind.normalisation` by ruling
      // — no fourth kind was added — so the kind alone does not identify a
      // restatement. The message id does, and each of the three outcomes a
      // normalisation-kind finding may reach has its own approved entry.
      const Set<String> approved = <String>{
        'msg.l1.normalisation',
        'msg.l1.whole-pack',
        'msg.l1.not-computable',
      };
      for (final FactualFinding f
          in of(analyse(parsed(fixtureA)), FactualFindingKind.normalisation)) {
        expect(approved, contains(f.messageId.value));
      }
      // The restatement itself is still pinned exactly.
      expect(
        about(analyse(parsed(fixtureA)), FactualFindingKind.normalisation,
                NutrientId.sodium,
                message: 'msg.l1.normalisation')!
            .messageId,
        MessageId('msg.l1.normalisation'),
      );
    });

    test('no mass is converted to volume, or the reverse', () {
      // A per-100 g figure is never restated per 100 ml: that needs a density
      // the label does not declare.
      for (final FactualFinding f
          in of(analyse(parsed(fixtureA)), FactualFindingKind.normalisation)) {
        expect((f.value as ComputedFactualValue).field.basisOrNull,
            isNot(Basis.per100ml));
      }
    });
  });

  // =============================================================== whole pack

  group('L1 — whole-pack derivation (FR-L1-03)', () {
    test('400 mg per 100 g across a 300 g pack is 1200 mg', () {
      final FactualFinding? f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.normalisation, NutrientId.sodium,
          message: 'msg.l1.whole-pack');
      expect(f, isNotNull);
      final ComputedFactualValue v = f!.value as ComputedFactualValue;
      expect(
          v.field.quantityOrNull, const Quantity.exact(12000, Unit.milligram));
      expect(v.field.basisOrNull, Basis.perPack);
    });

    test('the derivation names scaleToPack and both its inputs', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.normalisation, NutrientId.sodium,
          message: 'msg.l1.whole-pack')!;
      expect(f.derivation, isNotNull);
      expect(f.derivation!.operation, DerivationOperation.scaleToPack);
      expect(
        f.derivation!.inputs.map((DerivationInput i) => i.field).toList(),
        containsAll(<FindingSubject>[
          const FindingNutrient(NutrientId.sodium),
          const FindingServing(ServingField.netQuantity),
        ]),
      );
    });

    test('scaling applies no gazetted constant', () {
      // It multiplies two declared values. An empty constant list is a fact
      // about the operation.
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.normalisation, NutrientId.sodium,
          message: 'msg.l1.whole-pack')!;
      expect(f.derivation!.constantsUsed, isEmpty);
    });

    test('no net quantity means no whole-pack finding at all', () {
      // Not a zero, not an unresolved value — nothing to state.
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Sodium 400 mg',
      ]);
      expect(
        analyse(l).findings.where((FactualFinding f) =>
            f.messageId == MessageId('msg.l1.whole-pack')),
        isEmpty,
      );
    });

    test('the derived field is marked derived, never extracted (FR-L1-09)', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.normalisation, NutrientId.sodium,
          message: 'msg.l1.whole-pack')!;
      expect((f.value as ComputedFactualValue).field, isA<DerivedField>());
    });
  });

  // ====================================================================== RDA

  group('L1 — %RDA (FR-L1-04)', () {
    test('400 mg against a 2000 mg daily value is 20%', () {
      final FactualFinding? f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.sodium);
      expect(f, isNotNull);
      final ComputedFactualValue v = f!.value as ComputedFactualValue;
      expect(v.field.quantityOrNull!.unit, Unit.percent);
      // `Unit.percent` tracks tenths, so 20.0 % is a scaled value of 200.
      expect(v.field.quantityOrNull!.scaledValue, 200);
    });

    test('the denominator comes from the supplied table, not from code', () {
      // Halving the pack's denominator must double the percentage. If the
      // engine held its own copy of 2000 mg, this would not move.
      final RdaTable halved = RdaTable(<RdaDenominator>[
        denominator(NutrientId.sodium, 'const.rda.sodium',
            const Quantity.exact(10000, Unit.milligram)),
      ]);
      final FactualFinding f = about(analyse(parsed(fixtureA), rda: halved),
          FactualFindingKind.rdaContribution, NutrientId.sodium)!;
      expect(
          (f.value as ComputedFactualValue).field.quantityOrNull!.scaledValue,
          400); // 40.0 %
    });

    test('the derivation carries the constant, its value and its source', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.sodium)!;
      final ConstantUsed c = f.derivation!.constantsUsed.single;
      expect(c.constantId, ConstantId('const.rda.sodium'));
      expect(c.value, const Quantity.exact(20000, Unit.milligram));
      expect(c.sourceRef, SourceId('src.fssai.labelling.2020'));
    });

    test('the cited source resolves in the supplied registry', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.sodium)!;
      expect(sources[f.derivation!.constantsUsed.single.sourceRef], isNotNull);
    });

    test('the derivation names rdaPercent and the declared input', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.sodium)!;
      expect(f.derivation!.operation, DerivationOperation.rdaPercent);
      expect(f.derivation!.inputs.single.field,
          const FindingNutrient(NutrientId.sodium));
      expect(f.derivation!.inputs.single.quantity,
          const Quantity.exact(4000, Unit.milligram));
    });

    test('the message id is the approved contribution entry', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.sodium)!;
      expect(f.messageId, MessageId('msg.l1.rda-contribution'));
    });
  });

  group('L1 — no gazetted denominator (FR-L1-04)', () {
    test('protein has no daily value, and that is stated, not inferred', () {
      // FSSAI gazettes six. Protein is declared on the label and simply has no
      // denominator to divide by.
      final FactualFinding? f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.protein);
      expect(f, isNotNull);
      expect(f!.value, const NoDenominatorFactualValue());
      expect(f.messageId, MessageId('msg.l1.rda-no-denominator'));
    });

    test('it is not NotDeclared and not Unresolved', () {
      // The nutrient was declared and read perfectly. Blaming the label or the
      // parser would be false in both directions (MI-08).
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.protein)!;
      expect(f.value, isNot(isA<ComputedFactualValue>()));
      expect(f.value, isNot(const NotComputableFactualValue()));
    });

    test('no denominator means no derivation to describe', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.protein)!;
      expect(f.derivation, isNull);
    });

    test('an empty RdaTable produces no percentages at all', () {
      final Layer1Result r =
          analyse(parsed(fixtureA), rda: RdaTable(const <RdaDenominator>[]));
      for (final FactualFinding f
          in of(r, FactualFindingKind.rdaContribution)) {
        expect(f.value, const NoDenominatorFactualValue());
      }
    });
  });

  // ================================================== serving reconciliation

  group('L1 — serving reconciliation (FR-L1-05)', () {
    test('30 g x 10 servings against a 300 g pack reconciles', () {
      expect(analyse(parsed(fixtureA)).servingReconciliation.discrepancy,
          ServingDiscrepancy.none);
    });

    test('the declared serve and servings count are carried as read', () {
      final ServingReconciliationResult s =
          analyse(parsed(fixtureA)).servingReconciliation;
      expect((s.declaredServe as ExtractedField).quantity,
          const Quantity.exact(3000, Unit.gram));
      expect((s.servesPerPack as ExtractedField).quantity,
          const Quantity.exact(1000, Unit.count));
    });

    test('whole-pack totals appear beside the serving figures', () {
      final ServingReconciliationResult s =
          analyse(parsed(fixtureA)).servingReconciliation;
      expect(s.wholePackValues, isNotEmpty);
      final NutrientField sodium = s.wholePackValues
          .firstWhere((NutrientField f) => f.nutrient == NutrientId.sodium);
      expect((sodium.perPack as DerivedField).quantity,
          const Quantity.exact(12000, Unit.milligram));
    });

    test('a serve larger than the pack is serveExceedsPack', () {
      // INV-09's verdict, read rather than recomputed.
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Serving Size 400 g',
        'Net Quantity 300 g',
        'Sodium 400 mg',
      ]);
      expect(analyse(l).servingReconciliation.discrepancy,
          ServingDiscrepancy.serveExceedsPack);
    });

    test('a servings count that does not multiply out is servesInconsistent',
        () {
      // INV-10's verdict. 30 g x 4 is 120 g, not 300 g.
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Serving Size 30 g',
        'Servings Per Pack 4',
        'Net Quantity 300 g',
        'Sodium 400 mg',
      ]);
      expect(analyse(l).servingReconciliation.discrepancy,
          ServingDiscrepancy.servesInconsistent);
    });

    test('undeclared serving figures give notComputable', () {
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Sodium 400 mg',
      ]);
      final ServingReconciliationResult s = analyse(l).servingReconciliation;
      expect(s.discrepancy, ServingDiscrepancy.notComputable);
      expect(s.declaredServe, isA<NotDeclaredField>());
    });

    test('a reconciliation finding is emitted alongside the object', () {
      final Layer1Result r = analyse(parsed(fixtureA));
      final List<FactualFinding> f =
          of(r, FactualFindingKind.servingReconciliation);
      expect(f, isNotEmpty);
      expect(f.first.subject, isA<FindingServing>());
      expect(f.first.messageId, MessageId('msg.l1.serving-reconciliation'));
    });

    test('the engine does not recompute INV-09 or INV-10', () {
      // The verdict must agree with S7's, because it *is* S7's. If Layer 1 held
      // its own tolerance, these could disagree.
      final ParsedLabel l = parsed(fixtureA);
      final InvariantResult inv10 = l.invariantResults.firstWhere(
          (InvariantResult r) => r.invariantId == InvariantId.inv10);
      expect(inv10.outcome, InvariantOutcome.passed);
      expect(analyse(l).servingReconciliation.discrepancy,
          ServingDiscrepancy.none);
    });
  });

  // ============================================================== confidence

  group('L1 — confidence propagation (FR-L1-08)', () {
    test('a derived value never exceeds the meet of its inputs', () {
      final Layer1Result r = analyse(parsed(fixtureA));
      for (final FactualFinding f in r.findings) {
        if (f.value is ComputedFactualValue && f.derivation != null) {
          final Confidence expected = Confidence.meetAll(
            f.derivation!.inputs.map((DerivationInput i) => i.confidence),
          );
          expect(f.confidence.index, lessThanOrEqualTo(expected.index),
              reason: 'arithmetic cannot make a value more trustworthy');
        }
      }
    });

    test('the finding confidence equals the meet of its inputs exactly', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.normalisation, NutrientId.sodium,
          message: 'msg.l1.whole-pack')!;
      expect(
        f.confidence,
        Confidence.meetAll(
            f.derivation!.inputs.map((DerivationInput i) => i.confidence)),
      );
    });

    test('the meet is the lesser level, across the lattice', () {
      // The rule itself, stated once. Layer 1 adds no second policy.
      expect(Confidence.high.meet(Confidence.medium), Confidence.medium);
      expect(Confidence.medium.meet(Confidence.low), Confidence.low);
      expect(Confidence.high.meet(Confidence.high), Confidence.high);
      expect(
          Confidence.meetAll(<Confidence>[
            Confidence.high,
            Confidence.medium,
            Confidence.low,
          ]),
          Confidence.low);
    });

    test('the computed value and its finding agree on confidence', () {
      final FactualFinding f = about(analyse(parsed(fixtureA)),
          FactualFindingKind.rdaContribution, NutrientId.sodium)!;
      final DerivedField d =
          (f.value as ComputedFactualValue).field as DerivedField;
      expect(d.confidence, f.confidence);
    });
  });

  // ============================================== derivation and provenance

  group('L1 — derivation metadata (FR-EXP-09)', () {
    test('every computed finding exposes a derivation', () {
      for (final FactualFinding f in analyse(parsed(fixtureA)).findings) {
        if (f.value is ComputedFactualValue) {
          expect(f.derivation, isNotNull,
              reason: '${f.messageId.value} computed without showing its work');
        }
      }
    });

    test('the derivation result matches the value it explains', () {
      for (final FactualFinding f in analyse(parsed(fixtureA)).findings) {
        if (f.value is ComputedFactualValue && f.derivation != null) {
          expect(f.derivation!.result,
              (f.value as ComputedFactualValue).field.quantityOrNull);
        }
      }
    });

    test('every derivation names at least one input', () {
      for (final FactualFinding f in analyse(parsed(fixtureA)).findings) {
        expect(f.derivation?.inputs ?? const <DerivationInput>[],
            anyOf(isEmpty, isNotEmpty));
        if (f.derivation != null) {
          expect(f.derivation!.inputs, isNotEmpty);
        }
      }
    });
  });

  group('L1 — provenance (ADR-0009)', () {
    test('derived fields carry factual provenance, with no pipeline stage', () {
      for (final FactualFinding f in analyse(parsed(fixtureA)).findings) {
        if (f.value is ComputedFactualValue) {
          final FieldState s = (f.value as ComputedFactualValue).field;
          if (s is DerivedField) {
            expect(s.provenance.origin, FieldOrigin.derived);
            expect(s.provenance.producedByStage, isNull,
                reason: 'Layer 1 is analysis, not a parser stage');
          }
        }
      }
    });

    test('each Layer 1 rule id follows the pack convention', () {
      for (final FactualFinding f in analyse(parsed(fixtureA)).findings) {
        if (f.value is ComputedFactualValue) {
          final FieldState s = (f.value as ComputedFactualValue).field;
          if (s is DerivedField) {
            expect(s.provenance.parseRuleId!.value, startsWith('rule.l1.'));
          }
        }
      }
    });

    test('the rule pack version is carried onto every derived value', () {
      final ParsedLabel l = parsed(fixtureA);
      for (final FactualFinding f in analyse(l).findings) {
        if (f.value is ComputedFactualValue) {
          final FieldState s = (f.value as ComputedFactualValue).field;
          if (s is DerivedField) {
            expect(s.provenance.rulePackVersion, l.rulePackVersion);
          }
        }
      }
    });
  });

  // ================================================================ overflow

  group('L1 — arithmetic refusal (M11b)', () {
    test('an absurd magnitude yields NotComputable, never a number', () {
      // OCR reading a smudged digit run. The label parses; the pack-scaling
      // multiplication cannot be performed safely.
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Net Quantity 999999999999 g',
        'Sodium 999999999999 mg',
      ]);
      final Layer1Result r = analyse(l);
      // Nutrient findings only. The reconciliation finding also refuses here —
      // the serving figures cannot be reconciled either — but it keeps
      // `msg.l1.serving-reconciliation`, because that is which figure could not
      // be stated. Letting its id stand in for a nutrient's would lose that.
      final Iterable<FactualFinding> refused = r.findings.where(
          (FactualFinding f) =>
              f.value is NotComputableFactualValue &&
              f.subject is FindingNutrient);
      expect(refused, isNotEmpty, reason: 'the fixture must actually overflow');
      for (final FactualFinding f in refused) {
        expect(f.messageId, MessageId('msg.l1.not-computable'));
        expect(f.derivation, isNull,
            reason: 'no arithmetic completed, so there is nothing to describe');
      }
    });

    test('a refusal never becomes an invariant failure', () {
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Net Quantity 999999999999 g',
        'Sodium 999999999999 mg',
      ]);
      expect(() => analyse(l), returnsNormally);
    });

    test('an ordinary label is unaffected by the guards', () {
      final Layer1Result r = analyse(parsed(fixtureA));
      expect(
        r.findings
            .where((FactualFinding f) => f.value is NotComputableFactualValue),
        isEmpty,
      );
    });
  });

  // =========================================================== partial input

  group('L1 — partial input (FR-PAR-14, FR-L1-09)', () {
    test('a panel with no serving figures still yields nutrient findings', () {
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Sodium 400 mg',
      ]);
      final Layer1Result r = analyse(l);
      expect(of(r, FactualFindingKind.normalisation), isNotEmpty);
      expect(r.servingReconciliation.discrepancy,
          ServingDiscrepancy.notComputable);
    });

    test('a label with no nutrients yields no nutrient findings', () {
      final ParsedLabel l = parsed(<String>[
        'Ingredients: Wheat Flour, Sugar, Salt',
      ]);
      final Layer1Result r = analyse(l);
      expect(of(r, FactualFindingKind.normalisation), isEmpty);
      expect(of(r, FactualFindingKind.rdaContribution), isEmpty);
    });

    test('not-declared never becomes zero', () {
      final Layer1Result r = analyse(parsed(<String>[
        'Ingredients: Wheat Flour, Sugar, Salt',
      ]));
      for (final FactualFinding f in r.findings) {
        expect(f.value, isNot(isA<ComputedFactualValue>()));
      }
    });
  });

  // =========================================== category, determinism, safety

  group('L1 — category independence (FR-L1-10)', () {
    test('the same label analyses identically with and without a category', () {
      final Layer1Result none = analyse(parsed(fixtureA));
      final Layer1Result biscuits =
          analyse(parsed(fixtureA, category: CategoryId('cat.biscuits')));
      expect(none.findings, biscuits.findings);
      expect(none.servingReconciliation, biscuits.servingReconciliation);
    });

    test('analyseFactually takes no category parameter at all', () {
      // Structural, not behavioural: there is nowhere to pass one.
      expect(analyse(parsed(fixtureA)), isA<Layer1Result>());
    });
  });

  group('L1 — determinism (FR-PAR-02)', () {
    test('the same inputs analysed twice produce equal results', () {
      final ParsedLabel l = parsed(fixtureA);
      final RdaTable rda = rdaTable();
      final Layer1Result first =
          analyseFactually(l, rda: rda, sources: sources);
      final Layer1Result second =
          analyseFactually(l, rda: rda, sources: sources);
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('finding order is stable across runs', () {
      final ParsedLabel l = parsed(fixtureA);
      expect(
          analyse(l).findings.map((FactualFinding f) => f.messageId).toList(),
          analyse(l).findings.map((FactualFinding f) => f.messageId).toList());
    });

    test('the comparison is not vacuous — different labels differ', () {
      expect(
          analyse(parsed(fixtureA)).findings,
          isNot(analyse(parsed(<String>[
            'Nutritional Information Per 100 g',
            'Sodium 200 mg',
          ])).findings));
    });
  });

  group('L1 — factual only (FR-L1-01)', () {
    test('every finding kind is a statement of fact or arithmetic', () {
      for (final FactualFinding f in analyse(parsed(fixtureA)).findings) {
        expect(FactualFindingKind.values, contains(f.kind));
      }
    });

    test('every message id is one of the eight committed Layer 1 entries', () {
      const Set<String> approved = <String>{
        'msg.l1.normalisation',
        'msg.l1.whole-pack',
        'msg.l1.rda-contribution',
        'msg.l1.rda-no-denominator',
        'msg.l1.serving-reconciliation',
        'msg.l1.serves-inconsistent',
        'msg.l1.serve-exceeds-pack',
        'msg.l1.not-computable',
      };
      for (final FactualFinding f in analyse(parsed(fixtureA)).findings) {
        expect(approved, contains(f.messageId.value));
      }
    });

    test('no finding carries a severity, classification or recommendation', () {
      // Structural: the type has no such field. Asserted so a future field
      // addition is a deliberate act, not a drift.
      final FactualFinding f = analyse(parsed(fixtureA)).findings.first;
      expect(f.toString(), isNot(contains('HIGH_IN')));
      expect(f.toString(), isNot(contains('severity')));
    });
  });

  group('L1 — it does not touch what the parser decided', () {
    test('the ParsedLabel is unchanged by analysis', () {
      final ParsedLabel l = parsed(fixtureA);
      final List<NutrientField> before = List<NutrientField>.of(l.nutrients);
      analyse(l);
      expect(l.nutrients, before);
      expect(l.servingInfo, l.servingInfo);
    });

    test('an unresolved parser field is not reported as arithmetic failure',
        () {
      // Fixture H from M12: `6 g 1.8 g` leaves the unit unresolvable. That is a
      // parse outcome and must not be restated as a Layer 1 refusal.
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Protein 6 g 1.8 g',
        'Sodium 400 mg',
      ]);
      final Layer1Result r = analyse(l);
      expect(
          about(r, FactualFindingKind.normalisation, NutrientId.protein,
              message: 'msg.l1.not-computable'),
          isNull);
    });

    test('invariant results are read, never rewritten', () {
      final ParsedLabel l = parsed(fixtureA);
      final List<InvariantResult> before =
          List<InvariantResult>.of(l.invariantResults);
      analyse(l);
      expect(l.invariantResults, before);
    });
  });

  group('L1 — deferred requirements are genuinely absent', () {
    test('FR-L1-06 no declaration-gap finding is emitted', () {
      // The pack carries no authoritative mandatory-declaration list, so the
      // engine must not invent one.
      final Layer1Result r = analyse(parsed(<String>[
        'Nutritional Information Per 100 g',
        'Sodium 400 mg',
      ]));
      expect(FactualFindingKind.values, hasLength(3));
      for (final FactualFinding f in r.findings) {
        expect(f.messageId.value, isNot(contains('gap')));
      }
    });

    test('FR-L1-07 no additive is identified', () {
      final Layer1Result r = analyse(parsed(<String>[
        'Nutritional Information Per 100 g',
        'Sodium 400 mg',
        'Ingredients: Wheat Flour, Emulsifier (INS 322), Salt',
      ]));
      for (final FactualFinding f in r.findings) {
        expect(
            f.subject,
            isNot(isA<FindingServing>().having(
                (FindingServing s) => s.field.name, 'field', contains('ins'))));
        expect(f.messageId.value, isNot(contains('additive')));
      }
    });

    test('ingredient identification stays null after analysis', () {
      final ParsedLabel l = parsed(<String>[
        'Nutritional Information Per 100 g',
        'Sodium 400 mg',
        'Ingredients: Wheat Flour, Emulsifier (INS 322), Salt',
      ]);
      analyse(l);
      for (final Ingredient i in l.ingredients) {
        expect(i.identification, isNull);
      }
    });
  });
}
