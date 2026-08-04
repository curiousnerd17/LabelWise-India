# LabelWise India — Test Strategy

| Field | Value |
|---|---|
| **Document** | `docs/TEST_STRATEGY.md` |
| **Version** | 1.3 |
| **Status** | **Approved** |
| **Phase** | Phase 1: Architecture & Planning |
| **Author** | Chief Software Architect |
| **Date** | 4 August 2026 |
| **Parents** | `PROJECT_VISION.md` v1.1, `REQUIREMENTS.md` v1.2, `ARCHITECTURE.md` v1.0, `DATA_MODEL.md` v1.3 |
| **Decision log** | [`docs/adr/`](adr/README.md) |
| **Successor** | `ROADMAP.md` |
| **Resolves** | **Q7** (fifth category), **Q8** (definition of "correct"), **Q14** (corpus methodology and calibration) |

**Permanent rules confirmed at approval** — recorded as **ADR-0023** and **ADR-0024**, and binding beyond this document:

1. **Critical Error Rate is the primary release-quality metric.** Where it conflicts with Field Accuracy, the error rate takes precedence.
2. **Exact match is the permanent definition of parser correctness.** Tolerance must never enter parser accuracy measurement.
3. **The golden corpus is append-only.** Ground truth is never modified to satisfy parser behaviour.
4. **The fifth validation category remains architectural verification only** and must not silently expand MVP scope.

---

## 0. Purpose

This document defines how the project proves its claims. It exists mainly to settle three things **before any measurement exists**, because each of them is a definition that would otherwise be quietly relaxed once a disappointing number appeared:

- What counts as a correct parse (§4).
- How the corpus is built, annotated and protected from being edited to fit the parser (§5).
- What the confidence levels must empirically mean (§7).

Deciding a measurement rule while ignorant of the result it will produce is the only way to keep the rule honest. Everything else here is conventional testing practice arranged around those three commitments.

---

## 1. Testing Philosophy

### 1.1 The shape of the pyramid

The architecture's pure domain (ADR-0007, ADR-0008) makes an unusual distribution both possible and correct:

```
                    ╱╲          Manual device verification
                   ╱  ╲         (performance, UI, gate-time)
                  ╱────╲
                 ╱      ╲       Widget tests
                ╱        ╲      (presentation contracts)
               ╱──────────╲
              ╱            ╲    Golden corpus tests
             ╱              ╲   (55 real labels — the accuracy evidence)
            ╱────────────────╲
           ╱                  ╲ Property tests
          ╱                    ╲(lattice laws, determinism, invariants)
         ╱──────────────────────╲
        ╱                        ╲  Unit tests
       ╱                          ╲ (domain: stages, rules, arithmetic)
      ╱────────────────────────────╲
```

Most projects treat golden/integration tests as an expensive middle band to be minimised. Here the golden corpus is the **primary evidence for the project's headline claim** (ADR-0020) and is therefore deliberately large relative to the codebase.

### 1.2 What we do not test, and why

Being explicit about this prevents effort leaking into work that proves nothing.

| Not tested | Reason |
|---|---|
| Flutter framework behaviour | Not our code; testing it measures Google's CI, not ours |
| The OCR engine's recognition accuracy | Third party behind a port (B2). We test *our* handling of its output, including bad output. |
| Adapter internals with heavy mocking | A test that asserts a mock was called proves the test was written, not that the code works |
| End-to-end UI automation | Deferred. Expensive to maintain, slow, and the domain already carries the risk. Revisit post-MVP. |
| Third-party licence compliance by test | Enforced at dependency selection (CON-11), not at runtime |

> **⚠ Architect's Note — the absence of E2E UI automation is a real gap and should be acknowledged as one.**
>
> Nothing in this strategy catches "the button does not navigate." The mitigation is that the domain holds essentially all of the risk, widget tests cover presentation contracts, and gate-time manual verification on the reference device covers flows.
>
> That is an acceptable trade for a solo developer at MVP. It stops being acceptable if the UI grows past a handful of screens, and the decision should be revisited at v1.0 rather than inherited indefinitely.

---

## 2. Unit Testing Strategy

### 2.1 Scope and target

Domain-core line coverage **≥ 90%** (NFR-TST-01, E2), measured on `lw_domain` only. Coverage of presentation and adapters is not a target — a coverage number that averages a well-tested domain with a thin UI shell tells you nothing about either.

All domain tests run without a Flutter binding (NFR-TST-02). A domain test that needs one indicates a layering violation and should fail the build for that reason, not be accommodated.

### 2.2 What gets unit tested

| Area | Focus |
|---|---|
| **Pipeline stages S1–S8** | Each stage independently, with hand-built inputs. Stage boundaries are contracts. |
| **Quantity arithmetic** | Scaled-integer arithmetic, unit conversion, the single rounding policy (§2.4 of `DATA_MODEL.md`) |
| **Confidence assignment** | Signal combination, the FR-CNF-05 absolute rule, S1-absent degradation (FR-CNF-03) |
| **Invariant evaluation** | Each of INV-01…10 in isolation: pass, fail, and inapplicable |
| **Rule evaluation** | Table-driven from rule pack fixtures |
| **Layer 1 arithmetic** | Normalisation, %RDA, serving reconciliation |
| **Layer 2 classification** | Threshold comparison, margin computation, severity |
| **Explanation construction** | Completeness, reference resolution |
| **FieldState handling** | Every operation against all five variants |
| **`Version` comparison** | Ordering, especially `1.10.0` vs `1.9.0` (ADR-0022) |

### 2.3 Test data discipline

Fixtures live beside the tests, not in the rule pack. A test that reads the production rule pack tests the content, not the code — and will break every time a nutrition reviewer adds an additive. Rule-engine tests use small purpose-built fixture packs; the real pack has its own validation (§9).

### 2.4 Naming

Tests state a behaviour, not a method name: *"a field participating in a failed invariant is never HIGH"*, not *"testAssignConfidence3"*. A test suite should read as a specification of the domain. When a test fails at 2 a.m. in Phase 2, its name is the entire diagnostic message.

---

## 3. Property-Based Testing Strategy

Properties catch what examples miss: they express what must be true for *all* inputs, and shrink failures to a minimal case. Given how much of this system is defined by algebraic properties, this is unusually high-value here.

### 3.1 The property set

| # | Property | Discharges |
|---|---|---|
| PT-01 | `meet(a,b) ≤ a` and `meet(a,b) ≤ b` | MI-04, FR-CNF-06 |
| PT-02 | `meet` is commutative | Propagation order irrelevance |
| PT-03 | `meet` is associative | Same |
| PT-04 | `meet` is idempotent | Lattice well-formedness |
| PT-05 | Confidence propagation never increases confidence along any derivation chain | MI-04, ADR-0010 |
| PT-06 | Parsing the same input twice yields byte-identical output, including confidence and explanations | FR-PAR-02, E3 |
| PT-07 | Quantity round-trips through serialisation unchanged | MI-11 |
| PT-08 | Unit conversion within a dimension is total and loses no precision beyond the unit's scale | §2.3 of `DATA_MODEL.md` |
| PT-09 | Basis scaling round-trips within one rounding step | INV-08 |
| PT-10 | Ingredient declaration order is preserved through every transformation | MI-12 |
| PT-11 | Every constructed `AdvisoryFinding` has a complete Explanation with resolvable references | MI-01, FR-EXP-01 |
| PT-12 | A field in a FAILED invariant is never HIGH | MI-09, FR-CNF-05 |
| PT-13 | No operation crashes on any `FieldState` variant, including `Unresolved` and `NotDeclared` | MI-08 |
| PT-14 | A `USER_SUPPLIED` field survives re-analysis unchanged | FR-COR-04, FR-CNF-12 |
| PT-15 | `Version` ordering is a total order consistent with semantic versioning | ADR-0022 |
| PT-16 | Every pipeline stage is total — no input produces an exception rather than a failure value | FR-PAR-17 |
| PT-17 | Quantity equality distinguishes qualifiers: `LESS_THAN v ≠ EXACT v` for all `v` | MI-14, ADR-0027 |
| PT-18 | Interval comparison is sound — never returns definite when the intervals overlap | MI-16 |
| PT-19 | Scaling a qualified quantity by a positive constant preserves the bound direction | §2.2a of `DATA_MODEL.md` |
| PT-20 | A qualifier never changes the confidence assigned to a field | MI-15 |
| PT-21 | An `INDETERMINATE` invariant neither caps nor supports `HIGH` confidence | §4.3a of `DATA_MODEL.md` |
| PT-22 | No Layer 2 evaluation reaches a `DEFINITE` outcome from a straddling interval | MI-16, FR-L2-14 |
| PT-23 | Quantity round-trips through canonical serialisation unchanged, and `EXACT` is never emitted | MI-17, ADR-0027 |

### 3.2 Generator design

Generators must produce **hostile** inputs, not plausible ones: empty recognition results, single elements, elements with zero-area geometry, overlapping boxes, values with absurd magnitudes, unit strings that nearly match, ingredient lists with unbalanced parentheses, and nesting deeper than any real label.

> **⚠ Architect's Note — PT-06 deserves to be written first, before the parser exists.**
>
> Determinism is the property most likely to be broken accidentally and least likely to be noticed: a map iteration order, a set that serialises differently, a hash-based grouping. These produce output that is correct on every run *except* when compared byte-for-byte across runs or platforms.
>
> Writing PT-06 first means the parser is born under the constraint rather than retrofitted to it. Retrofitting determinism onto a codebase that assumed it is materially harder than building with it.

---

## 4. Q8 Resolved — What "Correct" Means

**This definition is fixed now, before any accuracy number exists.**

### 4.1 The governing principle

Label reading is a **transcription** task, not a measurement task. The label prints a specific symbol; we either read it or we did not. There is no physically meaningful sense in which reading `2.5 g` as `2.4 g` is "close" — it is a different declaration.

**Therefore: correctness is exact match. Tolerance has no role in accuracy measurement.**

Tolerance bands (§4.4 of `DATA_MODEL.md`) exist for a different purpose — testing whether *independently rounded* values on a label are internally consistent. Those are checks on the manufacturer's arithmetic, not on our reading.

> **⚠ Architect's Note — keeping tolerance out of the accuracy metric is the single most important integrity decision in this document.**
>
> If tolerance leaks into accuracy measurement, the headline number becomes tunable: widen the band, accuracy improves, no code changes, nothing looks wrong. The pressure to do exactly that will arrive around the time the first corpus run disappoints.
>
> **The two must remain structurally separate: tolerance lives in the rule pack and governs invariants; accuracy comparison is exact and lives in the test harness.** They must not share a configuration value.

### 4.2 Field-level comparison rules

| Field class | Rule |
|---|---|
| Nutrient value | Exact match on `scaledValue`, `unit` **and `qualifier`** after canonical normalisation |
| Basis | Exact. A right value on the wrong basis is wrong — usually by a factor of 3 or more. |
| Serving size, servings per pack, net quantity | Exact on value and unit |
| INS numbers | Exact set equality against the ground-truth set |
| Ingredient sequence | Exact ordered match of normalised names (order is legally meaningful) |
| `NotDeclared` | Correct when ground truth confirms the label does not declare it |

**Canonical normalisation before comparison** covers only representational equivalence — `2.5 g` equals `2500 mg`; `Preservative (INS 211)` equals `INS 211` — never numeric proximity.

**Qualifiers participate in equality** (ADR-0027). `LESS_THAN 0.5 g` is not equal to `EXACT 0.5 g`. A parser that reads `< 0.5` as `0.5` therefore records an **Error**, not a Correct.

This raises the bar slightly, and correctly so: the two declarations mean different things, and confusing them changes what Layer 2 can conclude about trans fat. Expect a modest accuracy cost on labels carrying bound declarations — which, in the biscuits and namkeen categories, is many of them.

Label edge cases are canonicalised in the annotation guide, not in the comparator: `"Nil"`, `"0"`, `"< 0.5 g"` and `"traces"` each have one defined ground-truth representation, decided once (§5.4).

### 4.3 Three outcome classes, not two

A single accuracy percentage would let two very different failures hide behind one number. P1 (honesty over completeness) says they are not equally bad, so the metric must separate them.

| Outcome | Definition | User experience |
|---|---|---|
| **Correct** | Value matches ground truth, or `NotDeclared` correctly identified | Right answer |
| **Miss** | We returned `Unresolved` or `NotDeclared` but the label declares it | Honest failure. User sees a gap and can correct it. |
| **Error** | We returned a value that differs from ground truth | **Silent wrong answer.** The user has no signal that anything is amiss. |

An Error is categorically worse than a Miss. A Miss is the system obeying P1; an Error is the system violating it.

### 4.4 The metrics

| Metric | Definition | Bar |
|---|---|---|
| **Field Accuracy** | Correct ÷ (critical fields the label actually declares) | **≥ 85%** (FR-PAR-15, E4) |
| **Critical Error Rate** | Error ÷ (critical fields declared) | **≤ 3%** |
| **HIGH-confidence Error Rate** | Errors among fields classified HIGH | **≤ 2%** (FR-CNF-11) |
| **Miss Rate** | Miss ÷ (critical fields declared) | Reported, not capped |

The denominator is **fields the label declares**, not all critical fields. A label that legitimately omits added sugars must not count against the parser; that is a declaration gap and Layer 1's job to report.

All four are reported **overall and per category** (FR-CAT-08).

> **⚠ Architect's Note — the Critical Error Rate is the real quality bar, not Field Accuracy.**
>
> A parser at 85% accuracy with 15% misses and 0% errors is a trustworthy product that admits what it cannot read. A parser at 90% accuracy with 10% errors is a dangerous one that confidently reports wrong sodium values.
>
> **Field Accuracy is the published headline because it is comparable and legible. Critical Error Rate is the number that should govern whether we ship.** If the two ever conflict, the error rate wins.

### 4.5 Scan-level reporting

Per-scan outcomes are also reported, because a user experiences scans rather than fields: proportion of corpus labels that are fully correct, that have ≥1 miss and no errors, and that have ≥1 error. The third figure is the one to watch.

---

## 5. Q14 Resolved — Golden Corpus Methodology

### 5.1 Composition

| Set | Size | Purpose |
|---|---|---|
| **Development set** | 40 labels — 10 per priority category | Parser iteration, debugging, tolerance calibration |
| **Holdout set** | 10 labels — spread across the four categories | Measured **only at phase gates**; never used for debugging |
| **Fifth-category set** | 5 labels (§6) | Architecture verification only; not held to the accuracy bar |
| **Total** | **55 labels** | Satisfies NFR-TST-03 (≥50) and FR-CAT-07 (≥10 per priority category) |

> **⚠ Architect's Note — the holdout is small, and I want to be honest about what it can and cannot tell you.**
>
> Ten labels give a wide confidence interval. A holdout accuracy of 85% on ten labels is compatible with a true rate anywhere from roughly 55% to 98%. It cannot certify the parser.
>
> What it *can* do is detect gross overfitting. If development accuracy is 88% and holdout is 50%, the parser has been tuned to memorise forty specific labels. That is a real and likely failure mode for a hand-written parser iterated many times against a fixed set, and it is invisible without a holdout.
>
> **Recommendation: keep the holdout, report its interval honestly rather than as a point estimate, and grow it before v1.0.** A small holdout used honestly beats a large one used as a debugging set.

### 5.2 Sourcing protocol

Each entry records provenance so a reviewer can obtain the same packet:

| Field | Notes |
|---|---|
| Product name, manufacturer, variant, pack size | |
| Purchase location and date | |
| Batch/lot code where legible | Labels change between print runs; this dates the ground truth |
| Category | One of the four, or fifth-category |
| Difficulty tags | `metallised`, `curved`, `low_light`, `poor_print`, `two_column`, `multi_component`, `small_text` |

**Adversarial sampling is mandatory** (NFR-TST-04): at least half of each category's entries must carry a difficulty tag. A corpus of flat, well-lit cardboard boxes will report a flattering accuracy that predicts nothing about a chip packet in a shop (ADR-0020).

### 5.3 Capture protocol

- One primary image per entry, captured on the **reference device** (ADR-0018) — capture characteristics are device-dependent, and measuring on a better camera measures the wrong thing.
- A **robustness subset** of 5 development entries is captured three times each under different lighting and angle. These do not count toward the 55 but test stability of output across captures of the same label.
- Alongside each image, the corpus stores the **recorded OCR output** (B2, ADR-0020). This lets parser tests run without the OCR engine, separating parser regressions from OCR-version drift — the single most useful property of the corpus format.

### 5.4 Annotation process

**Ground truth is transcribed from the physical packet in hand — never from the image, and never from OCR output.**

This is the rule that makes the corpus meaningful. Annotating from the image inherits the image's ambiguity: if a digit is unclear in the photograph, the annotator guesses, and the parser is then measured against a guess. Annotating from OCR output is circular and measures nothing at all.

Process:

1. Photograph the packet on the reference device.
2. Transcribe every critical field from the packet, under good light, with the packet physically present.
3. Record edge cases using the canonical representations fixed in the annotation guide (`"Nil"`, `"0"`, `"< 0.5 g"`, `"traces"`).
4. Store ground truth as structured data alongside the image and recorded OCR.
5. Sign the entry with the annotation date and corpus schema version.

**Annotation quality control for a solo annotator.** There is no second annotator, so self-consistency is the available check: re-annotate a random 20% of entries **at least two weeks later, without reference to the first annotation**, and compute agreement. Disagreements are investigated — they indicate either a genuine transcription error or an ambiguous field that needs a canonicalisation rule. Target agreement ≥ 98%; below that, the annotation guide is under-specified rather than the annotator careless.

### 5.5 The integrity rule

> **Ground truth is never edited to make a test pass.**

This is the cardinal rule of the corpus and the easiest to violate innocently — the parser disagrees, you look again at the photograph, the photograph is ambiguous, and you "correct" the ground truth. The result is a corpus that certifies the parser against itself.

Enforcement:

- Corpus entries are **append-only**. Ground-truth corrections are versioned, never overwritten.
- A correction requires a recorded reason and must cite **re-examination of the physical packet**, not re-examination of the image or of parser output.
- Corrections are reviewed as a distinct commit type, never bundled into a parser change. A commit that alters both a parser and a ground-truth value is rejected on sight.

### 5.6 Growth

The corpus is expected to grow continuously (`PROJECT_VISION.md` Stage 1). Every real-world parse failure a user reports becomes a candidate entry. **New entries join the development set by default**; the holdout grows only by deliberate decision, so that it stays uncontaminated.

---

## 6. Q7 Resolved — The Fifth Validation Category

### 6.1 Are four categories sufficient?

**No — and the reason is specific rather than general.**

The four priority categories are well chosen for *accuracy* stress: biscuits bring dense small print and serving-size manipulation, chips the worst OCR surface, namkeen the longest ingredient lists, instant noodles the most structurally ambiguous panels.

But they share a hidden commonality: **all four are solid foods declared by mass.** Every one uses `PER_100G`. Nothing in the four exercises the volume path at all.

That is exactly the shape of blind spot FR-CAT-06 exists to find. A parser tuned entirely on gram-based labels can accumulate an implicit assumption that `PER_100G` is the default basis — and that assumption will not fail on any of the forty development labels.

### 6.2 Decision — packaged beverages

The fifth category is **packaged beverages** (carbonated soft drinks, packaged juices, flavoured milk).

| Why it earns the slot | |
|---|---|
| **Changes the basis dimension** | `PER_100ML`, not `PER_100G` — the only candidate that exercises volume units end to end |
| **Different nutrient profile** | Sugar-dominant, near-zero fat and protein — exercises threshold selectors and produces different Layer 2 findings |
| **Makes INV-06 inapplicable** | Macronutrient sum ≤ 100 g per 100 g does not apply to a volume basis, testing that `INAPPLICABLE` is handled as a first-class outcome rather than a silent skip |
| **Different serving conventions** | Bottles declaring per 100 ml plus per bottle, where the bottle *is* the serve — a distinct reconciliation shape |
| **Available and cheap** | Trivially sourced anywhere in India |

Rejected alternatives: **breakfast cereal** (still mass-based; too close to biscuits to probe anything new); **chocolate and confectionery** (structurally near-identical to biscuits); **dairy such as curd** (mass-based, and shorter ingredient lists than namkeen already covers).

### 6.3 Scope — architecture verification, not accuracy

**The fifth category is not a fifth accuracy target.** Its purpose is narrow and must stay narrow, or it silently becomes a fifth corpus to build and blows the schedule.

| In scope | Out of scope |
|---|---|
| 5 labels, added to the rule pack as **data only** | The ≥85% accuracy bar |
| Proving no Dart change is required (FR-CAT-03, E5d) | A 10-label corpus |
| Proving `PER_100ML` flows end to end | Threshold tuning for beverages |
| Proving INV-06 reports `INAPPLICABLE` rather than failing | Per-category accuracy reporting |

**Pass criterion:** the five labels process end to end, producing Layer 1 and Layer 2 output with correct bases and units, with **zero changes to `lw_domain`**. If any Dart file must change, FR-CAT-01 has failed and the finding matters far more than the parse quality.

---

## 7. Confidence Calibration Validation

Confidence is a first-class principle (P2). An uncalibrated confidence system is worse than none, because it lends unearned authority to a guess.

### 7.1 Reliability targets

Measured on the corpus, per confidence level:

| Level | Empirical correctness | Direction |
|---|---|---|
| `HIGH` | **≥ 98%** | Floor (FR-CNF-11, E5c) |
| `MEDIUM` | **≥ 85%** | Floor |
| `LOW` | **≤ 70%** | **Ceiling** |

The `LOW` **ceiling** is the unusual one and the most important. If fields classified LOW turn out to be 95% correct, the classifier is over-cautious: it is asking users to check things that were fine, and users will rapidly learn to ignore the signal. **LOW must actually predict wrongness**, or the disclaimer's instruction to "verify the product label directly" when confidence is low becomes noise.

### 7.2 Discrimination

Reliability alone is gameable: a system that labels everything MEDIUM satisfies FR-CNF-01 and E5b, and is useless.

| Requirement | Bar |
|---|---|
| Proportion of correctly extracted critical fields classified `HIGH` | **≥ 50%** |
| Monotonic ordering | Correctness(HIGH) > Correctness(MEDIUM) > Correctness(LOW), with meaningful separation |

### 7.3 Signal ablation

Because S1 availability is unresolved (Q2) and S3 is primary (ADR-0010), calibration is measured in three configurations:

| Configuration | Purpose |
|---|---|
| S2 + S3 only | **The shipping baseline.** Must meet §7.1 on its own. |
| S2 + S3 + S1 | Measures whether S1 adds discrimination |
| S2 only | Quantifies how much S3 is actually contributing |

If the third configuration performs nearly as well as the first, the invariants are not earning their place and the design assumption behind ADR-0010 needs revisiting. That would be a genuinely surprising and important finding, which is why it is worth measuring rather than assuming.

### 7.4 Tolerance band calibration workflow (completes Q14)

The bands in §4.4 of `DATA_MODEL.md` are provisional. Calibration procedure:

1. **Compute deviations from ground truth, not from parser output.** For each development-set label, evaluate INV-07, INV-08 and INV-10 using the hand-verified ground-truth values. This isolates deviation inherent to the *label* — manufacturer rounding, fibre in the carbohydrate figure — from deviation caused by *our parsing*.
2. **Characterise the distribution** of that inherent deviation per invariant.
3. **Set each band** at approximately the 99th percentile of the inherent distribution, rounded to a legible value.
4. **Verify sensitivity** by injecting realistic single-digit OCR errors into ground-truth values and confirming the band flags them.
5. **Record** the band, its basis, the corpus version and the calibration date in `rulepack/rules/confidence.json`.
6. **Confirm on the holdout** at the phase gate.

> **⚠ Architect's Note — step 1 is the whole method, and getting it backwards is an easy mistake.**
>
> Calibrating bands against *parser output* would tune them to accept the parser's own errors: every mistake the parser currently makes would widen the band that was supposed to catch it. The invariants would then agree with the parser by construction and detect nothing.
>
> Calibrating against ground truth measures the only thing that matters — how much a *correctly read* label naturally deviates. Anything beyond that range is our error, which is precisely what S3 is for.

---

## 8. Performance Benchmarks

### 8.1 Protocol

All measurements on the **Moto G34 5G, 4 GB** (ADR-0018), release build, on battery, after a cold boot, with a five-run median. Any measurement on another device is not evidence.

| Benchmark | Budget | Requirement |
|---|---|---|
| Cold start to interactive | < 2 s | NFR-PRF-01 |
| Capture → displayed result | < 5 s | NFR-PRF-02 |
| Analysis only (parse + confidence + L1 + L2) | < 500 ms | NFR-PRF-03 |
| Rule pack eager load | < 300 ms | §12.2 of `REQUIREMENTS.md` |
| Peak memory during scan | < 400 MB | NFR-PRF-05 |
| Installed size | < 40 MB | NFR-SIZ-01 |
| UI thread never blocked | No frame > 32 ms during scan | NFR-PRF-04 |

### 8.2 What runs where

Analysis-only timing is pure computation and **can** be benchmarked in CI, giving early warning of algorithmic regressions. Everything else requires the physical device.

> **⚠ Architect's Note — device benchmarks cannot run in CI, and that gap needs an owner, not a hope.**
>
> A device farm costs money that CON-02 forbids, and the reference device is a single handset on a desk. Device benchmarks are therefore **manual, gate-time measurements** following a written protocol, with results recorded in a committed file so the trend is visible in diffs.
>
> The realistic failure mode is not that a benchmark is missed — it is that measurement is deferred until late, a budget turns out to be badly breached, and the fix is architectural. **Recommendation: take the first end-to-end device measurement as soon as a rough pipeline exists, long before it is good.** An early bad number is information; a late bad number is a crisis.

---

## 9. Regression Testing

| Trigger | Suite |
|---|---|
| Any domain change | Unit + property suites |
| Any parser change | Full golden corpus (development set) |
| Any rule pack content change | Rule validation + analysis goldens |
| Any confidence change | Corpus + calibration report |
| Phase gate | Everything, including holdout and device benchmarks |

### 9.1 Stage snapshots

Each pipeline stage has snapshot tests over a subset of corpus entries. A change to S2 that alters layout reconstruction shows up as a snapshot diff at S2, rather than as a mysterious accuracy drop at S8. This is what makes regressions diagnosable rather than merely detectable.

### 9.2 The golden-blessing rule

> **A golden or snapshot is never updated without reviewing the diff and recording why it changed.**

Auto-blessing goldens — regenerating them wholesale when they fail — is the standard way corpus testing dies. It converts every test into a tautology in a single command. Updates are individually reviewed, and a bulk regeneration is not a legitimate operation.

### 9.3 Accuracy trend

Every corpus run appends to a committed report: date, commit, corpus version, rule pack version, and all four §4.4 metrics overall and per category. Because it is committed, an accuracy regression appears as a **diff in a pull request** — visible in review rather than discovered at a gate.

---

## 10. CI Validation Gates

### 10.1 Blocking checks

| # | Check | Enforces |
|---|---|---|
| CI-01 | `lw_domain` declares zero dependencies | E1, NFR-MNT-01, ADR-0007 |
| CI-02 | Layer import lints pass | §2.2 of `ARCHITECTURE.md` |
| CI-03 | No `DateTime.now`, `Random`, `Platform`, `Locale` in domain | P4, MI-07 |
| CI-04 | Domain tests pass with no Flutter binding | NFR-TST-02 |
| CI-05 | Domain coverage ≥ 90% | NFR-TST-01, E2 |
| CI-06 | All property tests pass | E3 |
| CI-07 | Rule pack schema validation | FR-KB-03, NFR-TST-07 |
| CI-08 | Zero dangling `ruleId` / `sourceRef` / `messageId` | FR-EXP-04, MI-05 |
| CI-09 | Every advisory rule has ≥1 citation | FR-KB-04, E5 |
| CI-10 | No user-facing literal outside the message catalogue | FR-LOC-01, MI-06 |
| CI-11 | Golden corpus (development set) meets accuracy and error bars | FR-PAR-15 |
| CI-12 | No `INTERNET` permission in the manifest | NFR-OFF-02, ADR-0016 |
| CI-13 | All dependency licences Apache-2.0 compatible | CON-11, ADR-0017 |
| CI-14 | Analysis-only benchmark within budget | NFR-PRF-03 |
| CI-15 | Every **P0-v0.1** requirement maps to ≥1 test; widens to include P0-v0.2 at Phase 7 | NFR-TST-05 |
| CI-16 | No serialised `"qualifier": "EXACT"` in `rulepack/` or `corpus/` | MI-17, ADR-0027 |

### 10.2 Reported, not blocking

| Check | Reason |
|---|---|
| Accuracy trend report | Informational; the bar is enforced by CI-11 |
| Calibration report | Bars enforced at gates, not per commit — per-commit calibration is noise on 40 labels |
| Installed size trend | Bar enforced at gate (NFR-SIZ-01) |

### 10.3 Gate-time only

Holdout accuracy, confidence calibration against §7.1, device performance benchmarks, the fifth-category dry run, and manual accessibility verification on the reference device.

> **⚠ Architect's Note — CI-15 is the check that keeps this document honest.**
>
> `REQUIREMENTS.md` carries 152 P0 requirements. Without a mechanical link from requirement to test, that list quietly becomes documentation rather than specification — and nobody discovers which P0 requirements were never actually verified until something breaks in the field.
>
> The implementation can be simple: test names or annotations carry requirement IDs, and CI asserts full coverage of the P0 set. Crude, and enough. **This should be built in the first week of Phase 2, alongside the layering enforcement**, because both get much harder to add once there is a large untagged test suite.

---

## 11. Traceability

| Requirement | Discharged by |
|---|---|
| FR-PAR-02 (determinism) | PT-06, CI-06 |
| FR-PAR-15 (accuracy) | §4.4, CI-11 |
| FR-PAR-17 (total stages) | PT-16 |
| FR-CNF-03 (S1 absent) | §7.3 ablation |
| FR-CNF-05 (failed invariant) | PT-12 |
| FR-CNF-06 (determinism) | PT-01…04 |
| FR-CNF-11 (HIGH ≥ 98%) | §7.1 |
| FR-CNF-12 (user-supplied) | PT-14 |
| FR-COR-04 (correction survives) | PT-14 |
| FR-EXP-01/04 (explanations) | PT-11, CI-08, CI-09 |
| FR-CAT-03/06 (data-only extension) | §6.3 |
| FR-CAT-07 (corpus per category) | §5.1 |
| FR-CAT-08 (per-category reporting) | §4.4 |
| FR-KB-03 (build-time validation) | CI-07 |
| FR-LOC-01 (no literals) | CI-10 |
| NFR-OFF-02 (no INTERNET) | CI-12 |
| NFR-PRF-01…05 (performance) | §8.1 |
| NFR-TST-01 (coverage) | CI-05 |
| NFR-TST-03/04 (corpus size, adversarial) | §5.1, §5.2 |
| NFR-TST-05 (P0 → test) | CI-15 |
| NFR-TST-06 (property tests) | §3.1 |
| NFR-TST-07 (rule pack CI) | CI-07 |
| E5c (calibration) | §7.1, §7.4 |
| E5d (category-agnostic) | §6.3 |
| MI-01…12 | PT-01…16, CI-03, CI-08, CI-10 |

---

## 12. Open Questions

| # | Question | Blocks | Needed by |
|---|---|---|---|
| Q2 | Does the OCR engine expose usable per-element confidence? | §7.3 ablation | Phase 2 week 1 |
| Q15 | `StoredScan` serialisation format | Persistence tests | Before history is built |
| Q16 | Does `MICROGRAM` earn its place in the unit set? | §2.3 of `DATA_MODEL.md` | Before implementation |
| Q17 | Property-testing library selection | §3 | Before implementation — subject to CON-11 |
| Q18 | Should the robustness subset (§5.3) have its own stability bar, or is it diagnostic only? | §5.3 | After first corpus run |

---

## 13. Approval

| Item | Status |
|---|---|
| **Q7 resolved** — fifth category is packaged beverages, scoped to architecture verification | ✅ §6 |
| **Q8 resolved** — exact match; tolerance excluded from accuracy; three outcome classes | ✅ §4 |
| **Q14 resolved** — corpus methodology, annotation, integrity rule, calibration workflow | ✅ §5, §7.4 |
| Unit testing strategy | ✅ §2 |
| Property-based testing strategy | ✅ §3, PT-01…16 |
| Golden corpus testing | ✅ §5 |
| Parser accuracy metrics | ✅ §4.4 |
| Confidence calibration validation | ✅ §7 |
| Performance benchmarks | ✅ §8 |
| Regression testing | ✅ §9 |
| CI validation gates | ✅ §10, CI-01…15 |
| No code written | ✅ |

*End of document. Approval required before proceeding to `ROADMAP.md`, the final Phase 1 deliverable.*
