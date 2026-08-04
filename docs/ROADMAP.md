# LabelWise India — Roadmap

| Field | Value |
|---|---|
| **Document** | `docs/ROADMAP.md` |
| **Version** | 1.1 |
| **Status** | **Approved — Phase 1 complete** |
| **Phase** | Phase 1: Architecture & Planning — **final deliverable** |
| **Author** | Chief Software Architect |
| **Date** | 4 August 2026 |
| **Parents** | All Phase 1 documents; ADR log 0001–0027 |

**Approved at v1.1 — Option A.** Release sequencing is **v0.1 Factual (~30 working days) → v0.2 Advisory (~20 additional)**. The Layer 1 / Layer 2 split is the official release boundary (ADR-0025). The contingency order in §6 is **frozen** and may not be renegotiated under schedule pressure without a new ADR (ADR-0026). The Annotation Guide and rule pack JSON schemas are **Phase 2 Day 1 deliverables, mandatory before parser implementation begins**. §9 is the formal gate into implementation.

---

## 0. Purpose

This document sequences the work, defines the gates, and states honestly what the schedule can and cannot absorb. It closes Phase 1.

It also does the thing a roadmap most often avoids: **arithmetic**. A plan that does not add up is not a plan, and discovering that on day 25 is materially worse than discovering it now.

---

## 1. The Schedule Question

### 1.1 The honest arithmetic

The MVP objective is a production-quality MVP in 30 days. Below is the work actually specified by M1–M17, estimated in **solo working days**, at the quality bar the approved documents set.

| Work | Days | Notes |
|---|---|---|
| Foundations: packages, CI enforcement (CI-01…15), skeleton | 3 | Must come first (§4.1) |
| Q2 OCR confidence spike | 1 | Gates the confidence design |
| Domain value objects: Quantity, Unit, Version, Provenance, Confidence, FieldState | 3 | |
| **Parser stages S1–S8** | **10–14** | The core; iterated against the corpus |
| Confidence subsystem (S1/S2/S3, invariants, lattice) | 3 | |
| Rule pack schema, validator, loader | 3 | |
| **Knowledge base curation** | **5–8** | Research and writing, not coding |
| **Golden corpus: 55 labels** | **4–6** | Photograph, transcribe, verify, re-annotate 20% |
| Layer 1 factual engine | 3 | |
| Layer 2 advisory engine + explanations | 3 | |
| UI: capture, result, correction, history | 6–8 | 720p layout is non-trivial (§12.4 of `ARCHITECTURE.md`) |
| Localisation scaffolding | 1 | |
| Calibration, hardening, device benchmarking | 4 | |
| Licence, README, docs, release prep | 1 | |
| **Total** | **50–61 working days** | |

Thirty calendar days is approximately **21 working days**. The specified MVP is therefore **roughly 2.5× the available time.**

> **⚠ Architect's Note — the scope grew after the 30-day target was set, and the roadmap should say so plainly.**
>
> I flagged in `PROJECT_VISION.md` §9.3 that M1–M14 looked unachievable in 30 days. Since then the scope has *increased*, for good reasons: two first-class subsystems were added (confidence M15, explainability M16), category-agnostic verification was added (M17), and the corpus grew from 50 to 55 labels with a holdout split.
>
> Every one of those additions improved the product. None of them made it faster to build. **The 30-day figure predates the specification it is now being applied to**, and holding both is not a plan — it is a decision deferred until it becomes a crisis.
>
> This is not an argument for lowering the bar. `PROJECT_VISION.md` §7.6 fixes the quality bar and makes scope the variable. §1.2 applies that rule.

### 1.2 Recommendation — split the MVP at a seam the architecture already has

The natural release boundary is **Layer 1 / Layer 2**, and it is already a hard architectural boundary: B6, and FR-L2-01 which requires that *"Layer 1 must remain fully functional with Layer 2 disabled."*

That requirement was written for testability and regulatory defensibility. It turns out to also describe a shippable product.

| Release | Contents | Working days |
|---|---|---|
| **v0.1 — Factual** | Capture, OCR, parser, confidence, correction, Layer 1 (normalisation, %RDA, serving reconciliation, declaration gaps, common additives), history, English UI | **~30** |
| **v0.2 — Advisory** | Layer 2 thresholds, full Explanations, complete evidence curation, severity ranking, expanded additive coverage | **~20** |

**v0.1 is genuinely useful on its own.** It answers "what does this packet actually contain, per 100 g and per pack, and does the serving size add up?" — which already beats reading the label unaided, and is the half where all the parsing risk lives.

**v0.1 also avoids the schedule's worst dependency.** Knowledge base curation (5–8 days of non-parallelisable research) is needed almost entirely for Layer 2. v0.1 needs only the six FSSAI RDA denominators, the nutrient synonym table, and additive records for the ~60–80 INS numbers common to the four categories. Unknown INS numbers are reported honestly as unidentified with the number shown — P1-compliant, and a fraction of the work.

**Three options:**

| Option | Assessment |
|---|---|
| **A. Two releases: v0.1 at ~30 days, v0.2 at ~50** | **Recommended.** Quality bar intact, honest dates, useful product early, curation moved off the critical path. |
| **B. Single MVP, ~55 working days (~11 calendar weeks)** | Legitimate if the date genuinely does not matter. Nothing ships until everything works. |
| **C. Full MVP in 30 days** | Rejected. Achievable only by lowering the bar, which contradicts the project's entire premise. |

**This is your decision, not mine.** The roadmap below is structured so that either A or B works: the phases are identical, and only the release point differs.

---

## 2. Phase Structure

| Phase | Name | Gate |
|---|---|---|
| **1** | Architecture & Planning | ✅ Complete on approval of this document |
| **2** | Foundations & Spikes | Enforcement green; Q2 resolved; skeleton builds |
| **3** | Parser & Confidence | Parser meets accuracy and error bars on development set |
| **4** | Analysis & Rule Pack | Layer 1 complete; rule pack validated in CI |
| **5** | Presentation & Correction | Full flow on the reference device |
| **6** | Hardening & Release Gate | All MVP gate conditions met |
| **7** | Layer 2 (v0.2 under Option A) | Advisory engine and explanations complete |

**Phases are gated, not timeboxed.** A phase ends when its gate passes. If a gate does not pass, scope reduces — the gate does not move (ADR-0023 rule 2 applied to schedule as well as metrics).

---

## 3. Two Tracks, Running in Parallel

The single most common way this project fails is treating the content work as something to do "later". It gates engineering deliverables and cannot be compressed by coding faster (R2).

| Track | Work | Character |
|---|---|---|
| **Engineering** | Code, tests, CI, UI | Compressible with effort |
| **Content** | Golden corpus, additive records, thresholds, citations, message text, annotation guide | **Not compressible.** Research and transcription. |

**The content track starts on day 1 of Phase 2 and never stops.** A realistic cadence is 2–3 corpus labels per working day alongside engineering, which delivers 55 labels across roughly four weeks without a dedicated block.

> **⚠ Architect's Note — the corpus must not be built in one sitting at the end.**
>
> Beyond the schedule argument, corpus-first has a design consequence: the first ten labels will reveal parser assumptions that are wrong, and they should reveal them in week 2 rather than week 5. The corpus is a design instrument before it is a measurement instrument.
>
> **Recommendation: photograph and annotate the first 8 labels — two per category — before writing any parser code.** They will change the parser's design, and that is the point.

---

## 4. Phase Detail

### 4.1 Phase 2 — Foundations & Spikes *(~4 working days)*

Everything here is infrastructure that becomes much harder to add later.

| # | Deliverable | Rationale |
|---|---|---|
| 2.1 | Package skeleton per §4 of `ARCHITECTURE.md` | |
| 2.2 | **CI enforcement CI-01…04, CI-10, CI-12, CI-13** | Layer violations must be impossible from commit 1 |
| 2.3 | **CI-15: P0 requirement → test mapping** | Crude is fine. Retrofitting onto an untagged suite is far worse. |
| 2.4 | **Q2 spike: OCR per-element confidence** | Resolves A2; gates the confidence design |
| 2.5 | **PT-06 determinism property test** | Written before the parser exists (§3.2 of `TEST_STRATEGY.md`) |
| 2.6 | **Annotation guide** with canonical edge-case representations | *Does not yet exist* — see §7 |
| 2.7 | ~~P0 re-prioritisation pass~~ | ✅ **Done in Phase 1** — release-scoped priority applied, 70% P0-v0.1 |
| 2.8 | LICENSE, NOTICE, `rulepack/LICENSE` (CC BY 4.0), README with disclaimer | ADR-0017; CON-08/09/10 |
| 2.9 | Dependency justification register | NFR-MNT-02, CON-11 |
| 2.10 | First 8 corpus labels | §3 |
| 2.11 | Reference device acquired and baseline-measured | ADR-0018 |

**Gate:** enforcement green on an empty project; Q2 answered; annotation guide written; 8 labels annotated.

### 4.2 Phase 3 — Parser & Confidence *(~16–20 working days)*

The core. Longest and riskiest phase.

| # | Deliverable |
|---|---|
| 3.1 | Domain value objects: Quantity, Unit, Version, Provenance, FieldState, Confidence lattice |
| 3.2 | Property tests PT-01…05, PT-07, PT-08, PT-15 |
| 3.3 | Parser stages S1–S4 (normalisation, layout, region classification, tokenisation) |
| 3.4 | Stage snapshot tests |
| 3.5 | Parser stages S5–S6 (field resolution, unit normalisation) — synonym table in rule pack |
| 3.6 | Invariants INV-01…10 (S7) |
| 3.7 | Confidence assignment S8; S2+S3 baseline **shipping without dependence on S1** |
| 3.8 | Golden corpus harness with exact-match comparator (ADR-0023) |
| 3.9 | Accuracy trend report, committed |
| 3.10 | Corpus grows to 40 development labels |
| 3.11 | **First end-to-end device measurement** — early and rough (§8.2 of `TEST_STRATEGY.md`) |

**Gate:** Field Accuracy ≥ 85% **and** Critical Error Rate ≤ 3% on the development set, per category; PT-01…16 green.

### 4.3 Phase 4 — Analysis & Rule Pack *(~7 working days)*

| # | Deliverable |
|---|---|
| 4.1 | Rule pack schema, CI validator (CI-07…09), loader with integrity check |
| 4.2 | RDA denominators with citations |
| 4.3 | Additive records for common INS numbers in the four categories |
| 4.4 | Layer 1 engine: normalisation, %RDA, serving reconciliation, declaration gaps, additive identification |
| 4.5 | `Derivation` on every Layer 1 finding (FR-EXP-09) |
| 4.6 | Message catalogue (English), stable IDs |
| 4.7 | Holdout set completed (10 labels) |

**Gate:** Layer 1 complete and correct on the corpus; rule pack passes CI with zero dangling references.

### 4.4 Phase 5 — Presentation & Correction *(~8 working days)*

| # | Deliverable |
|---|---|
| 5.1 | Capture flow: camera, gallery, framing guidance, bounded decode |
| 5.2 | **Confidence and Layer 1/2 visual language, designed on the 720p device first** (ADR-0018) |
| 5.3 | Result view: per-100 g / per-serve / per-pack together on a 720 px screen |
| 5.4 | Correction UI with S7 re-entry (§6.4 of `ARCHITECTURE.md`) |
| 5.5 | Local history with rule pack version; no silent re-evaluation |
| 5.6 | Persistent disclaimer (FR-PRS-06) |
| 5.7 | Widget tests; accessibility verification |

**Gate:** full flow works offline on the reference device.

### 4.5 Phase 6 — Hardening & Release Gate *(~5 working days)*

| # | Deliverable |
|---|---|
| 6.1 | **Tolerance band calibration** against ground truth (Q14, §7.4 of `TEST_STRATEGY.md`) |
| 6.2 | Confidence calibration report incl. signal ablation |
| 6.3 | **Fifth-category dry run** — 5 beverage labels, data-only (ADR-0024) |
| 6.4 | Holdout measurement, reported as an interval |
| 6.5 | Device performance benchmarks against all budgets |
| 6.6 | Airplane-mode verification; permission audit |
| 6.7 | Published accuracy figures, overall and per category |
| 6.8 | Release documentation |

**Gate:** all 12 MVP gate conditions in §13 of `REQUIREMENTS.md`.

### 4.6 Phase 7 — Layer 2 *(~20 working days; v0.2 under Option A)*

| # | Deliverable |
|---|---|
| 7.1 | Full evidence curation: WHO SEARO thresholds, ICMR-NIN, source registry |
| 7.2 | Expanded additive records with evidence-strength classification |
| 7.3 | Layer 2 engine with structurally mandatory Explanations (ADR-0011) |
| 7.4 | Severity ranking from recorded margins |
| 7.5 | Provisional marking for LOW-confidence inputs (FR-L2-09) |
| 7.6 | Explanation UI, reachable within one interaction |
| 7.7 | PT-11 and CI-09 green |

---

## 5. Critical Path

```
Foundations ─▶ Q2 spike ─▶ Value objects ─▶ Parser S1–S8 ─▶ Layer 1 ─▶ UI ─▶ Gate
                                                  ▲
                        Golden corpus ────────────┘   (gates accuracy measurement)
                        (parallel from day 1)
                                                  ▲
                        Knowledge base ───────────┘   (gates additive identification,
                        (parallel from day 1)          then all of Layer 2)
```

**The parser is the critical path, and the corpus is its critical input.** Everything else can slip a few days without moving the gate. These two cannot.

| Dependency | Consequence if late |
|---|---|
| Corpus → accuracy measurement | No accuracy figure, so no gate — the whole release blocks |
| Q2 spike → confidence design | S1 handling reworked mid-build |
| Annotation guide → corpus | Inconsistent ground truth, discovered only at re-annotation |
| CI enforcement → all code | Layering decays invisibly and is expensive to recover |

---

## 6. Contingencies — What Gets Cut, In Order

Decided now, while calm, so the concession under pressure is the right one.

| Order | Concession | Cost | Never traded |
|---|---|---|---|
| 1 | Defer Layer 2 to v0.2 (Option A) | Product is factual-only for one release | — |
| 2 | Reduce priority categories from 4 to 3 at the gate, publish the gap | Narrower validated coverage | — |
| 3 | Defer history (M11) | Scans not retained | — |
| 4 | Merge `lw_application` into `lw_domain` (ADR-0019) | Less layering | — |
| 5 | Defer localisation scaffolding to post-MVP | Hindi delayed further | — |
| — | | | **Domain purity, the OCR boundary, the Flutter boundary, exact-match accuracy, the error-rate bar, corpus integrity** |

The right-hand column is the point of the table. Everything in it is load-bearing for the project's central claim, and none of it may be conceded for schedule.

---

## 7. Gaps Identified While Writing This Roadmap

Two artefacts are referenced by approved documents but do not exist. Both are Phase 2 deliverables.

| Gap | Referenced by | Why it matters |
|---|---|---|
| **Annotation guide** | §5.4 of `TEST_STRATEGY.md` — "canonical representations fixed in the annotation guide" | Ground truth for `"Nil"`, `"0"`, `"< 0.5 g"`, `"traces"` is undefined. Annotating 55 labels without it guarantees inconsistency, and the ≥98% self-agreement target would measure the guide's absence rather than the annotator's care. |
| **Rule pack JSON schemas** | CI-07, FR-KB-03 | CI cannot validate against a schema that has not been written. |

> **⚠ Architect's Note — the annotation guide is a small document with outsized leverage.**
>
> It is perhaps two pages. It is also the difference between a corpus that means something and 55 labels annotated by four slightly different implicit conventions. Because the corpus is append-only (ADR-0023), inconsistent early annotations persist and cannot be quietly cleaned up later.
>
> **Write it before label 9.**

---

## 8. Post-MVP

Per `PROJECT_VISION.md` §10, gated in sequence, and explicitly not influencing MVP scope.

| Stage | Contents |
|---|---|
| **1 — Depth** | Corpus and category growth; reviewed Hindi content; optional rule pack refresh; published per-category accuracy |
| **2 — Reach** | Devanagari OCR; further Indian languages; accessibility and audio output |
| **3 — Breadth** | Cosmetics (INCI), supplements, OTC medicines — reusing S1–S4 |
| **4 — Infrastructure** | Knowledge base published as a standalone CC BY 4.0 citable dataset |

Tier 2 adoption metrics begin only after the Tier 1 engineering gate passes (§8 of `PROJECT_VISION.md`).

---

## 9. Implementation Readiness Checklist

**No production code is written until every item below is complete.**

### 9.1 Documents frozen

| # | Document | Version | Status |
|---|---|---|---|
| 1 | `PROJECT_VISION.md` | v1.1 | ✅ Approved |
| 2 | `REQUIREMENTS.md` | v1.3 | ✅ Approved |
| 3 | `ARCHITECTURE.md` | v1.0 | ✅ Approved |
| 4 | `DATA_MODEL.md` | v1.3 | ✅ Approved |
| 5 | `TEST_STRATEGY.md` | v1.3 | ✅ Approved |
| 6 | `ROADMAP.md` | v1.1 | ✅ Approved |
| 7 | ADR log 0001–0027 | — | ✅ Accepted |

"Frozen" means: approved, internally consistent, and changeable only by a documented revision. It does not mean never revised — it means never revised silently.

### 9.2 Owner decisions closed

| # | Decision | Status |
|---|---|---|
| 1 | Reference device (Q1) | ✅ Moto G34 5G, 4 GB |
| 2 | Code licence (Q5) | ✅ Apache 2.0 |
| 3 | Disclaimer text (Q6) | ✅ Fixed verbatim |
| 4 | Content licence (Q9) | ✅ CC BY 4.0, separate |
| 5 | Fifth category (Q7) | ✅ Packaged beverages, verification only |
| 6 | Definition of correct (Q8) | ✅ Exact match, permanent |
| 7 | Corpus methodology (Q14) | ✅ Defined; bands calibrated in Phase 6 |
| 8 | Confidence signal priority | ✅ S3 → S2 → S1 |
| 9 | AR1 concession order | ✅ Application merges into Domain first |
| 10 | Release sequencing (§1.2) | ✅ **Option A** — v0.1 Factual → v0.2 Advisory (ADR-0025) |
| 11 | Contingency order frozen | ✅ §6 binding; changes require a new ADR (ADR-0026) |
| 12 | Annotation Guide + rule pack schemas as Day 1 deliverables | ✅ Mandatory before parser work |
| 13 | Qualified quantities (Q19) | ✅ Approved — ADR-0027; model, schemas and tests updated |

### 9.3 Artefacts that must exist before code

| # | Artefact | Requirement |
|---|---|---|
| 1 | Package skeleton with layer boundaries | ADR-0007 |
| 2 | CI enforcement CI-01…04, CI-10, CI-12, CI-13 green | §2.3 of `ARCHITECTURE.md` |
| 3 | CI-15 requirement→test mapping in place | NFR-TST-05 |
| 4 | **Annotation guide written** | §7 |
| 5 | **Rule pack JSON schemas written** | CI-07 |
| 6 | LICENSE + NOTICE (Apache 2.0) | CON-08 |
| 7 | `rulepack/LICENSE` (CC BY 4.0) | CON-10 |
| 8 | README with verbatim disclaimer | CON-09, FR-PRS-06 |
| 9 | Dependency justification register | NFR-MNT-02, CON-11 |
| 10 | Reference device acquired | ADR-0018 |
| 11 | Q2 OCR spike complete | A2 |
| 12 | PT-06 determinism test written | §3.2 of `TEST_STRATEGY.md` |
| 13 | First 8 corpus labels annotated | §3 |
| 14 | P0 re-prioritisation pass complete | ✅ Applied — `REQUIREMENTS.md` v1.3 |

### 9.4 Understood and accepted before starting

| # | Commitment |
|---|---|
| 1 | Quality bar is fixed; **scope is the variable** |
| 2 | Critical Error Rate outranks Field Accuracy (ADR-0023) |
| 3 | Tolerance never enters accuracy measurement (ADR-0023) |
| 4 | Ground truth is never edited to satisfy the parser (ADR-0023) |
| 5 | Concession order is fixed (§6) and not renegotiated under pressure |
| 6 | The content track starts on day 1 and runs continuously (§3) |
| 7 | A schema that cannot express a rule is **extended, never bypassed** (ADR-0012) |
| 8 | The published accuracy figure is published whatever it says (ADR-0020) |

---

## 10. Approval

| Item | Status |
|---|---|
| Honest schedule arithmetic | ✅ §1.1 |
| Release sequencing options with a recommendation | ✅ §1.2 |
| Phase structure with gates | ✅ §2, §4 |
| Parallel content track | ✅ §3 |
| Critical path and dependencies | ✅ §5 |
| Contingency order fixed in advance | ✅ §6 |
| Gaps in approved documents identified | ✅ §7 |
| Post-MVP staging | ✅ §8 |
| Implementation Readiness Checklist | ✅ §9 |
| No code written | ✅ |

**One decision outstanding: release sequencing (§1.2, checklist 9.2 item 10).** With that answered and the §9.3 artefacts built, Phase 1 closes and implementation begins.

*End of document. End of Phase 1.*
