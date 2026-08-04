# LabelWise India — Project Vision

| Field | Value |
|---|---|
| **Document** | `docs/PROJECT_VISION.md` |
| **Version** | 1.1 |
| **Status** | **Approved** |
| **Phase** | Phase 1: Architecture & Planning |
| **Author** | Chief Software Architect |
| **Date** | 4 August 2026 |
| **Supersedes** | v1.0 (draft) |
| **Review cadence** | End of each phase, or on any change to a Design Principle |

**Changes in v1.1** — Recommendations 1–6 and 8–11 approved as written. Recommendation 7 approved **with modification**: the parser and rule engine are to be **category-agnostic by design**, with four categories prioritised for MVP validation rather than the architecture being narrowed to two (§9.3). Two principles added at the owner's direction: **Explainability** (P3) and **Confidence Reporting** (P2). Design principles renumbered accordingly.

---

## 0. How To Read This Document

This is the **root document** of the project. Every subsequent artefact — architecture, module design, data model, test strategy, roadmap — must be traceable back to a statement made here. If a future decision contradicts this document, either the decision is wrong or this document must be formally revised. Silent divergence is not permitted.

Two conventions are used throughout:

> **⚠ Architect's Note** — an assumption being challenged, a risk being surfaced, or a recommendation that differs from the original brief. These are the parts of the document that matter most. Read them.

> **✅ Decision** — a binding decision for the MVP. Changing it requires a documented revision to this file.

This document deliberately contains **no code, no package names, and no file structures.** Those belong in `ARCHITECTURE.md`, which comes next.

---

## 1. Mission

> **LabelWise India exists to give any Indian consumer, standing in a shop aisle with no internet connection, an honest and comprehensible answer to the question: "what is actually in this packet, and what does that mean for me?"**

The mission has three non-negotiable qualities:

1. **Honest** — the application reports what the label says and what published nutrition science says about it. It does not editorialise, moralise, gamify, or sell. When it does not know, it says so.
2. **Comprehensible** — the output is written for a person who has never read a nutrition panel, not for a nutritionist. Plain language is a hard requirement, not a nice-to-have.
3. **Available** — it works in a basement supermarket with no signal, on a five-year-old ₹8,000 Android phone, without an account, without a subscription, and without sending a photograph of anything to anyone.

Everything in this document derives from those three words.

---

## 2. Problem Statement

### 2.1 The consumer's problem

India's packaged food market has grown faster than the average consumer's ability to interpret it. A shopper picking up a biscuit packet faces:

- **A nutrition panel that is legally correct and practically useless.** Under the *Food Safety and Standards (Labelling and Display) Regulations, 2020*, manufacturers must declare energy, protein, carbohydrate, total sugars, added sugars, total fat, saturated fat, trans fat, cholesterol, sodium and dietary fibre — expressed per 100 g/100 ml **and** as a per-serve percentage contribution to Recommended Dietary Allowance. The RDA denominators are fixed by regulation at 2,000 kcal, 67 g total fat, 22 g saturated fat, 2 g trans fat, 50 g added sugar and 2,000 mg sodium. Almost no consumer knows these numbers, and almost none can perform the arithmetic in an aisle.
- **A serving size chosen by the manufacturer.** The single most effective legal deception in packaged food is declaring a serve small enough to keep the %RDA figures unalarming. A 60 g biscuit packet declared as "2 servings" halves every number on the front.
- **An ingredient list written in chemistry.** Indian regulation requires additives to be declared by functional class title plus **INS number** — "Preservative (INS 211)", "Emulsifier (INS 471)", "Colour (INS 102)". This is admirably precise and completely opaque. The consumer sees a number; they do not see "this is sodium benzoate, a preservative, and here is what is and is not known about it."
- **No trustworthy front-of-pack signal.** India has no finalised front-of-pack nutrition labelling scheme. The 2022 draft "Indian Nutrition Rating" star-rating model was never operationalised, and as of early 2026 FSSAI has told the Supreme Court it intends to **withdraw** the draft and commission further research. The shopper is therefore left with the back-of-pack panel and nothing else.

### 2.2 The problem with the existing solutions

- **Cloud-AI label scanners** require connectivity that fails precisely where the product is used, cost money per scan, and upload photographs of the user's shopping to a third party.
- **Barcode-lookup apps** depend on database coverage. Open Food Facts — the best open option — crossed roughly 10,000 Indian products in late 2024 against an estimated 90,000+ products reported as sold in the Indian market: coverage of roughly one product in nine. An app that fails on eight scans out of nine is worse than no app, because it actively trains the user to distrust it.
- **Generic Western nutrition apps** apply European or American reference intakes and product categories to an Indian diet, and have no concept of INS-numbered additive declarations or FSSAI RDA denominators.

### 2.3 The engineering problem

> **⚠ Architect's Note — the hard problem is not OCR.**
>
> The instinctive framing of this project is "an OCR app." That framing is wrong and will produce a bad architecture.
>
> On-device text recognition is a **solved, commoditised** capability: Google ML Kit's text recognition runs fully offline, is free, supports Latin and Devanagari scripts, and adds roughly 4 MB per script when bundled (~260 KB when unbundled). It will give us a reasonable bag of text lines from a photograph.
>
> The hard, unsolved, project-defining problem is everything *after* that: converting a noisy, reflow-mangled, multi-column, curved-surface, inconsistently-formatted block of OCR text into a **typed, unit-aware, validated nutrition and ingredient structure** — deterministically, offline, and reproducibly enough to write assertions against.
>
> **This parser is the core intellectual property of LabelWise India.** OCR is a replaceable input adapter. The architecture must reflect that inversion of importance, and the test strategy must invest most heavily there.

---

## 3. Target Users

We define three user segments. Only the first is a design target for the MVP; the others are explicitly deferred so that we do not silently build for them.

### 3.1 Primary — "The Cautious Shopper" *(MVP design target)*

| Attribute | Description |
|---|---|
| **Who** | Urban and semi-urban Indian adult, typically 25–45, buying packaged food for a household. |
| **Device** | Mid-to-low-range Android phone, 3–4 GB RAM, Android 8–13, frequently storage-constrained. |
| **Connectivity** | Intermittent. Often absent inside shops. Data is metered and consciously conserved. |
| **Language** | Reads English adequately; is more comfortable receiving explanations in Hindi. |
| **Nutrition literacy** | Low to moderate. Knows "too much sugar is bad." Does not know what 22 g of saturated fat means, or what INS 621 is. |
| **Motivation** | A specific concern — a diabetic parent, a child's snacks, personal weight, a distrust of "healthy" marketing claims. |
| **Job to be done** | *"Tell me in ten seconds whether this is as good as the front of the packet claims."* |
| **Failure they will not tolerate** | A wrong answer delivered confidently. This user will uninstall after one bad reading and will not return. |

### 3.2 Secondary — "The Health-Constrained Buyer" *(post-MVP)*

Users with a medical reason to read labels: diagnosed diabetes, hypertension, CKD, coeliac disease, or specific allergies. They need *personalised* thresholds and *allergen certainty*.

> **⚠ Architect's Note — do not build for this user in the MVP.**
>
> This segment is the most emotionally compelling and the most dangerous. Allergen detection has a catastrophic failure mode: a false negative on "contains peanuts" caused by an OCR misread can kill someone. Personalised thresholds for a CKD patient constitute dietary advice with clinical consequences.
>
> Serving this user requires a level of parser reliability, corpus validation, and legal review that we will not possess at day 30. The MVP must be explicit — in product copy and in the README — that it is **not** an allergen-safety tool. Building toward this segment is a v2 goal gated on a measured, published parser accuracy figure.

### 3.3 Tertiary — "The Contributor" *(the open-source audience)*

Flutter and mobile engineers evaluating the repository — as a reference implementation, a portfolio signal, or a project to contribute to. Their job to be done is *"can I understand this codebase in thirty minutes and add a rule without breaking anything?"*

This user is served entirely by architecture quality, documentation, and test coverage — which is why Phase 1 exists.

---

## 4. Scope

The MVP is defined by the following capabilities. Anything not listed here is out of scope by default.

### 4.1 Capture

- Capture a photograph of a nutrition facts panel and/or an ingredient list using the device camera.
- Import an existing image from device storage.
- Manual entry / correction of every extracted field.

> **✅ Decision — manual correction is a P0 feature, not a fallback.**
> A parser that cannot be corrected by the user is a parser that fails silently. The correction UI is also our only offline mechanism for discovering where the parser is weak. It ships in the MVP.

### 4.2 Extraction

- On-device, offline OCR of **English-language** label text.
- Deterministic parsing of the OCR output into a typed nutrition record: per-100 g/ml values, per-serve values, declared serving size, and servings per pack.
- Deterministic parsing of the ingredient list into an ordered ingredient sequence, with additives resolved by **INS number**.
- **Explicit confidence reporting at every stage** — OCR, parse and per-field — so the user can tell certain information from probable information from absent information.

> **✅ Decision — confidence is a first-class output, not diagnostic metadata.**
> Every extracted field carries a confidence classification derived from three deterministic signals: the OCR engine's own character confidence, the strength of the parse rule that matched (exact pattern versus heuristic fallback), and **arithmetic self-validation** against known invariants — saturated fat ≤ total fat, added sugar ≤ total sugars, sugars ≤ carbohydrate, macronutrient energy reconciling with declared energy, per-serve values reconciling with per-100 g values and declared serve size.
>
> That third signal is the most valuable and the most overlooked: it catches OCR digit errors deterministically, offline, with no model and no network. A label whose numbers do not reconcile is a label we should not report confidently, and we can know that from arithmetic alone.

> **✅ Decision — INS number is the primary key for additive identification.**
> Because Indian regulation mandates additive declaration by class title *plus* INS number, the additive knowledge base is keyed on the INS integer, not on ingredient name strings. This makes additive lookup exact, language-independent, deterministic, and trivially testable — a structural advantage that a US- or EU-targeted app does not have. Name-based matching exists only as a secondary, clearly-lower-confidence path.

### 4.3 Analysis — a two-layer model

Analysis is split into two architecturally and epistemically separate layers. This separation is the most important design decision in the project.

**Layer 1 — Regulatory & Factual Layer**
States what the label declares and what Indian labelling regulation says about it. Contains no judgement.

- Normalisation of all declared values to a per-100 g/ml basis and to a whole-pack basis.
- Computation of %RDA contribution against the FSSAI-specified denominators (2,000 kcal; 67 g fat; 22 g saturated fat; 2 g trans fat; 50 g added sugar; 2,000 mg sodium).
- Identification of each declared additive: INS number → common name → functional class → regulatory permission status.
- Detection of declaration gaps (a required field the label does not carry).
- Serving-size reconciliation: what the pack declares as a serve versus what the pack actually contains.

**Layer 2 — Advisory Nutrition Layer**
Interprets Layer 1 against published, citable nutrition evidence. Contains judgement, and labels it as such.

- Per-nutrient "high in" / "moderate" / "low" flags for sugar, sodium, saturated fat and trans fat.
- Plain-language explanation of each flag, including *why* the threshold exists.
- Additive commentary: what the additive does, what the evidence base says, and where the evidence is contested or thin.
- Explicit citation of the threshold source for every flag emitted.
- **A machine-readable explanation attached to every advisory output** — the rule that fired, the input values it consumed, the threshold it compared against, the margin by which the threshold was crossed, and the source citation. No advisory statement may be emitted without one.

> **⚠ Architect's Note — Layer 1 cannot produce a health verdict, and we must stop pretending otherwise.**
>
> There is a widespread assumption — one worth confronting directly — that "we'll just use the FSSAI thresholds." **India has no finalised regulatory nutrient-profile model.** The Indian Nutrition Rating draft of 2022 was never operationalised and FSSAI has moved to withdraw it. There is no legally-sanctioned Indian answer to "is this product healthy."
>
> The two-layer split is therefore not stylistic — it is the only architecture that survives this regulatory vacuum. Layer 1 is defensible because it only restates declared facts and gazetted arithmetic. Layer 2 is defensible because it is explicitly framed as advisory and every threshold carries a citation.
>
> **Recommendation:** anchor Layer 2 primarily on the **WHO South-East Asia Region Nutrient Profile Model (2017)**, supplemented by ICMR-NIN dietary guidance. SEARO is published, citable, regionally calibrated, and has been independently validated against the Indian market — an analysis of 31,516 Indian products found it discriminates appropriately, with roughly 68% of the market carrying at least one "high-in" flag. That last figure is a warning as much as a validation: our advisory layer will flag most of the shelf, and the UX must handle that without becoming noise.

### 4.4 Presentation

- A single scan result screen: factual summary, per-nutrient flags, ingredient breakdown, additive detail.
- Every advisory statement is visually and textually distinguishable from every factual statement.
- Message catalogue architecture supporting **English and Hindi** output.
- Local scan history, stored on-device.

### 4.5 Non-functional scope

- Fully functional with the network disabled, from first launch, forever.
- Cold start under 2 seconds on a mid-range device.
- Scan-to-result under 5 seconds on a mid-range device.
- No account, no login, no personal data collection, no analytics SDK.
- Reproducible builds with a documented, justified dependency set.

---

## 5. Out of Scope

Listed so that they can be declined quickly and without re-litigation.

| Excluded | Rationale |
|---|---|
| **Cloud AI / LLM label interpretation** | Violates offline-first and ₹0-recurring-cost constraints. Also non-deterministic — untestable, unauditable, and capable of confidently inventing a nutrient value. |
| **Barcode → product database lookup** | Coverage against the Indian market is far too low to be relied upon. A lookup that fails on most products erodes trust faster than having no lookup. |
| **User accounts, cloud sync, social features** | No backend exists and none is justified. Every one of these creates a privacy surface and a recurring cost. |
| **Allergen safety determination** | Catastrophic failure mode. Requires a reliability level we will not have at MVP. Explicitly disclaimed in-product. |
| **Personalised medical/dietary advice** | Requires clinical validation and creates regulatory exposure. Out of scope indefinitely, not merely for MVP. |
| **A single composite "health score"** | See Architect's Note below. |
| **Devanagari / regional-language OCR** | Deferred to post-MVP. Mandatory declarations must appear in **English *or* Hindi in Devanagari** — English is not legally guaranteed, but is near-universal in practice on national FMCG brands. English-only OCR therefore buys most of the market at a fraction of the risk. See R13. |
| **iOS** | Android-first. The architecture must not *preclude* iOS, but no iOS work, testing, or capability is in scope. |
| **Cosmetics, medicines, supplements** | Long-term vision. Must not influence MVP scope, but must not be architecturally excluded either. |
| **Monetisation of any kind** | No ads, no subscriptions, no affiliate links. Ever. |

> **⚠ Architect's Note — resist the single health score.**
>
> A single 0–100 number or A–E grade is the most requested and most harmful feature we could ship. It is (a) not defensible without a regulatory anchor that India does not have, (b) an invitation to regulatory attention because it constitutes a health claim about a third party's product, and (c) lossy — it collapses "high in sodium" and "high in sugar" into one figure that tells the user nothing actionable.
>
> **Recommendation:** ship per-nutrient flags in the MVP. Revisit a composite score only after v1.0, and only if user testing demonstrates that flags are genuinely not actionable. If it is ever built, it must be a transparent, published, reproducible function of the flags — never an opaque number.

---

## 6. Design Principles

These are ranked. When two principles conflict, the higher-numbered one yields.

### P1 — Honesty over completeness
The application never guesses to fill a gap. An unreadable field is reported as unreadable. A missing declaration is reported as missing. A contested additive is reported as contested. "We could not read this" is a valid, respectable, shippable output.

### P2 — Confidence is always reported, never implied
Every extracted value carries a confidence classification, and that classification is visible to the user — not buried in a debug log. The user must be able to distinguish, at a glance, a figure we read cleanly from one we reconstructed from a partial match, and to see immediately which fields are worth checking by hand.

Confidence is derived deterministically from OCR character confidence, parse-rule strength, and arithmetic self-validation. It is never a guess about a guess, and it is never presented as a false precision — a coarse, honest four-level scale beats a fabricated percentage.

*P2 is the operational enforcement of P1. Without it, honesty is a stated intention rather than a property of the system.*

### P3 — Every output is explainable
No advisory finding may be emitted without a machine-readable explanation attached: the rule that fired, its identifier and version, the input values consumed, the threshold applied, the margin of the crossing, and the source citation. The UI surfaces this on demand; the domain layer produces it unconditionally.

This makes the system auditable by a reviewer, debuggable by a contributor, testable by assertion, and — most importantly — *arguable with* by the user. A user who can see why the app said something can disagree with it intelligently. A user shown an unexplained verdict can only obey it or ignore it, and most will ignore it.

> **✅ Decision — explanations are produced unconditionally, not on request.**
> Generating an explanation lazily "when the user taps for detail" invites an implementation where the explanation is reconstructed separately from the decision and can therefore drift from it. The explanation and the finding are produced together, by the same evaluation, as a single indivisible result. An advisory finding without its explanation is a malformed object and must not be representable.

### P4 — Determinism over intelligence
The same label image, on the same app version and rule pack version, produces the same result — including the same confidence classifications and the same explanations — on every device, forever. This is what makes the app testable, auditable, and trustworthy, and it is why cloud AI is excluded on engineering grounds rather than merely on cost grounds.

### P5 — Facts and judgement are never mixed
Layer 1 and Layer 2 are separate in the data model, separate in the rule engine, and visually separate in the UI. The user must always be able to tell "the label says X" from "nutrition guidance suggests X is high."

### P6 — Offline is the default state, not the degraded state
There is no "offline mode." There is the application, which happens not to need a network. Any future network feature must be strictly additive and fully optional.

### P7 — The user's data never leaves the device
No telemetry, no crash-reporting SDK that ships images, no analytics. Photographs of what a person eats are sensitive. The only egress path is a user-initiated, explicit export.

### P8 — Every claim carries a citation
Every advisory threshold, every additive statement, every RDA denominator is traceable to a named, dated, public source held in the knowledge base. An uncited claim is a bug.

### P9 — Plain language is a functional requirement
Output is written at a reading level the primary user can act on. "Contains INS 211" is a failure. "Contains sodium benzoate — a preservative that stops mould growing" is the requirement. This applies equally to explanations and confidence indicators: an explanation the user cannot read is not an explanation.

### P10 — The rule engine is data, not code
Thresholds, additive facts, rule definitions and message text live in versioned, validated data assets — not in Dart conditionals. This is what allows the nutrition knowledge base to evolve without a code change, allows non-engineers to contribute, and allows the rules to be tested as data.

Rules-as-data and explainability are mutually reinforcing: a rule that exists as a data record already carries the identity, version and citation that an explanation needs. A rule buried in an `if` statement has nothing to point at.

> **⚠ Architect's Note — "offline-first" is being conflated with "frozen forever," and that is a mistake.**
>
> Additive science changes. FSSAI regulations change — indeed, a pending amendment will require total sugar, salt and saturated fat to be displayed in bold and larger type. A rule pack baked immutably into an APK is a rule pack that becomes wrong and stays wrong until the user updates the app, which most users never do.
>
> **Recommendation:** design the rule pack in Phase 1 as a **versioned, integrity-checked, self-describing data asset**, bundled in the APK as the default. Post-MVP, an *optional, user-initiated* refresh becomes a small addition rather than an architectural rewrite. Offline-first means the app is complete without a network — not that it is forbidden from ever having one.

---

## 7. Engineering Philosophy

### 7.1 We are building a system, not an app

The deliverable is not a screen that shows a number. It is: a capture pipeline, an extraction pipeline, a knowledge base, a rule engine, a presentation layer, and the test corpus that proves all five work. The app is the thin shell around that system. Architecture documents come before implementation because the system, not the shell, is what has to be right.

### 7.2 Boundaries are the product

The single most valuable architectural property here is that the **domain core — parsing, rules, analysis — is pure Dart with no Flutter dependency, no I/O, and no platform channels.** OCR is an adapter behind an interface. Storage is an adapter behind an interface. The camera is an adapter behind an interface.

This buys us three things that nothing else buys: the core is testable at speed without a device, the OCR engine becomes swappable without touching business logic, and the future cosmetics/medicine expansion becomes a new rule pack rather than a new application.

### 7.3 The test corpus is a first-class deliverable

> **⚠ Architect's Note — this is the recommendation most likely to be skipped, and it is the one that determines whether the project succeeds.**
>
> A deterministic parser is only as good as the evidence that it is correct. We need a **golden corpus**: real photographs of real Indian product labels, each paired with a hand-verified expected parse. Every parser change is validated against the entire corpus. Parser accuracy becomes a *measured number that appears in the README*, not an opinion.
>
> This corpus is slow, unglamorous, non-engineering work — photographing packets, transcribing panels, reviewing edge cases. It is also the difference between "a Flutter app that reads labels" and "a production-quality engineering artefact." **It must be built in parallel with the parser, starting in Phase 2, not retrofitted before launch.**
>
> Target: **50 labels for the MVP gate, distributed across the four priority categories** (biscuits, chips, namkeen, instant noodles — see §9.3), with no category below 10 labels. The corpus must deliberately over-sample bad cases: glossy and metallised packaging, curved surfaces, low light, poor print, two-column panels, bilingual panels, and multi-component packs.
>
> A corpus of easy labels proves nothing. If the corpus pass rate is not uncomfortable at first, the corpus is wrong.

### 7.4 Dependencies are liabilities

Every package added is code we did not write, cannot fully audit, and may have to replace. Each one requires a written justification: what it does, why we cannot reasonably do it ourselves, what its maintenance signals are, and what our exit path is. Prefer first-party Flutter and Google-maintained packages. A dependency for the domain core requires a stronger justification than one for the UI.

### 7.5 Documentation precedes implementation

Requirements → architecture → module design → data flow → risks → milestones → code. Not because documentation is virtuous, but because a solo developer has no colleague to catch a bad decision in review, and writing it down is the only available substitute for that review.

### 7.6 Quality over speed — with an honest definition of quality

Quality here means: the core is pure and tested; the rules are data and validated; every claim is cited; the parser has a measured accuracy figure; a new contributor can add a rule in thirty minutes; and the failure modes are documented rather than discovered.

Quality does *not* mean: comprehensive abstraction layers, a state-management framework chosen for its sophistication, or premature optimisation of a pipeline that has never been profiled.

---

## 8. Success Metrics

Success is defined in two sequenced tiers. **Tier 2 metrics are not measured, discussed, or optimised for until the Tier 1 gate is passed.** Mixing them is how engineering projects become bad products and bad products become bad codebases.

### 8.1 Tier 1 — Engineering Quality *(Phases 1–3; the primary definition of success)*

| # | Metric | Target | How measured |
|---|---|---|---|
| E1 | Domain core purity | 100% of parsing, rules and analysis logic has zero Flutter/IO imports | Static dependency check in CI |
| E2 | Domain core unit test coverage | ≥ 90% line coverage | Coverage report |
| E3 | Rule engine determinism | 100% of rule evaluations reproducible across runs and platforms | Property/golden tests |
| E4 | Parser accuracy on golden corpus | ≥ 85% of *critical fields* extracted correctly on ≥ 50 real labels, **reported per category** as well as overall | Golden corpus suite |
| E5 | Citation completeness | 100% of advisory statements resolve to a source entry | Knowledge-base validator |
| E5a | Explanation completeness | 100% of advisory findings carry a resolvable rule ID, inputs, threshold, margin and citation | Type-level invariant + unit tests |
| E5b | Confidence coverage | 100% of extracted fields carry a confidence classification | Type-level invariant + unit tests |
| E5c | Confidence calibration | On the golden corpus, fields classified HIGH are correct ≥ 98% of the time | Golden corpus suite |
| E5d | Category-agnosticism | Zero category-specific branches in the domain core; adding a category is a data-only change | Static check + a "fifth category" dry run |
| E6 | Rule pack validation | 100% of rule/knowledge data passes schema validation at build time | Build-time validator |
| E7 | Cold start | < 2 s on a mid-range reference device | Instrumented measurement |
| E8 | Scan → result latency | < 5 s on a mid-range reference device | Instrumented measurement |
| E9 | APK size | < 40 MB | Build output |
| E10 | Documentation completeness | Every Phase-1 document exists, is current, and is linked from the README | Manual review at phase gate |
| E11 | Contributor onboarding | A new contributor can add an additive entry and a threshold rule using docs alone | Dry-run with an external reader |
| E12 | Zero network calls | Verified absence of egress in the MVP build | Network inspection on an instrumented run |

**Tier 1 gate:** all sixteen met, documented, and published in the repository. Only then does Tier 2 begin.

*Note on E5c:* calibration matters more than coverage. A system that labels everything MEDIUM satisfies E5b and is useless. HIGH must mean something, or P2 degrades into decoration.

*Note on E5d:* the "fifth category" dry run is the real test — take a category outside the prioritised four (say, breakfast cereal), add it to the rule pack data only, and confirm the pipeline handles it with no code change. If that requires touching Dart, the architecture has failed the approved modification to Recommendation 7.

*Note on E4:* "critical fields" must be defined explicitly in the test strategy document — at minimum energy, total sugar, added sugar, sodium, saturated fat, total fat, serving size and servings-per-pack. An 85% target is deliberately honest rather than aspirational; publishing a real number beats claiming a fictional one.

### 8.2 Tier 2 — Real-World Validation *(post-v1.0, gated on Tier 1)*

| # | Metric | Target |
|---|---|---|
| A1 | Real-world scan success rate | ≥ 80% of scans produce a usable result without manual correction |
| A2 | Manual correction rate | Declining across releases — the primary signal of parser improvement |
| A3 | Category coverage | Verified against ≥ 200 distinct Indian products across ≥ 10 categories |
| A4 | Correctness complaints | Zero unresolved reports of a factually wrong nutrition reading |
| A5 | Contributor participation | ≥ 3 external contributors merged |
| A6 | Adoption | Meaningful and growing installs — deliberately unquantified until A1–A4 hold |

> **⚠ Architect's Note — Tier 2 metrics are unmeasurable under our own privacy principle, and this contradiction must be resolved now rather than at launch.**
>
> A1 and A2 require knowing what happened on users' devices. P7 forbids telemetry. These cannot both hold as stated.
>
> **Recommendation:** resolve it in favour of privacy, and change how the metrics are gathered. Replace background analytics with (a) an explicit, user-initiated "share this scan report" export that the user reviews before sending, (b) structured feedback via GitHub issues, and (c) our own expanding golden corpus as the primary accuracy instrument. This makes A1/A2 slower and less statistically clean — and that is the correct trade. **Decide this in Phase 1**, because retrofitting a privacy posture is far harder than designing one.

---

## 9. MVP Goals

### 9.1 Definition of the MVP

> A user can photograph the nutrition panel and ingredient list of an English-labelled Indian packaged food product, entirely offline, and receive: an accurate normalised restatement of what the label declares, an identification of every declared additive, and a set of cited, plain-language nutrition flags — each one explaining why it was generated — with a visible confidence level on every extracted field, and with every unreadable or missing field honestly reported and manually correctable.

### 9.2 MVP goal set

| ID | Goal | Definition of done |
|---|---|---|
| M1 | Offline capture pipeline | Camera + gallery capture with usable framing guidance; no network |
| M2 | Offline OCR integration | Text extraction working on-device behind a swappable interface |
| M3 | Deterministic nutrition parser | Typed nutrition record produced from OCR text; meets E4 on the golden corpus |
| M4 | Deterministic ingredient parser | Ordered ingredient list with INS-number resolution |
| M5 | Additive knowledge base | Curated, cited, schema-validated INS-keyed dataset covering additives common in the Indian market |
| M6 | Layer 1 factual engine | Per-100 g/per-pack normalisation, %RDA computation, serving-size reconciliation, gap detection |
| M7 | Layer 2 advisory engine | Cited per-nutrient flags anchored on WHO SEARO / ICMR-NIN |
| M8 | Manual correction UI | Every extracted field viewable and editable |
| M9 | Result presentation | Facts and advice visually separated; plain language throughout |
| M10 | Localisation architecture | Zero hardcoded user-facing strings; English catalogue complete; Hindi structurally supported |
| M11 | Local history | On-device scan history, no cloud |
| M12 | Golden corpus | ≥ 50 real labels with verified expected parses, ≥ 10 per priority category |
| M13 | Documentation set | All Phase-1 documents complete and current |
| M14 | Test suite | Unit, widget and golden tests meeting E2/E3/E4 |
| M15 | Confidence subsystem | Every field carries a deterministic confidence classification from OCR, parse-rule and arithmetic-invariant signals; surfaced in the UI; meets E5b/E5c |
| M16 | Explainability subsystem | Every advisory finding carries rule ID, version, inputs, threshold, margin and citation; surfaced on demand; meets E5a |
| M17 | Category-agnostic verification | "Fifth category" dry run passes as a data-only change; meets E5d |

### 9.3 On the 30-day timeline

> **⚠ Architect's Note — I do not believe M1–M14 is achievable in 30 days by a solo developer at the stated quality bar, and saying so now is more useful than discovering it on day 28.**
>
> The engineering is plausible. The non-engineering work is not. M5 (curating and citing an additive knowledge base) and M12 (photographing, transcribing and verifying 50 real labels) are together several weeks of careful, slow, non-code work — and both are *prerequisites* for M7 and E4 respectively. They cannot be compressed by writing code faster.
>
> **Approved resolution — separate the architecture question from the validation question.**
>
> My original recommendation was to narrow the MVP to two product categories. That was the wrong shape of answer, and the approved modification is better: **narrowing the validation surface does not require narrowing the architecture.** Those are independent decisions and conflating them would have baked a temporary schedule constraint into a permanent design constraint.
>
> The approved position is therefore:
>
> **The parser and rule engine are category-agnostic from day one.** No category-specific branching in the domain core. Category, where it matters at all, is an *attribute carried in the rule pack data* — never a conditional in code. Adding a category must require zero changes to the parser, the rule engine, or the analysis pipeline.
>
> **Four categories are prioritised for MVP validation and corpus construction:**
>
> | Category | Why it earns a slot |
> |---|---|
> | **Biscuits** | Highest-volume packaged category; dense, small-print panels; heavy serving-size manipulation |
> | **Chips** | Extreme sodium and fat profiles; small pack sizes where per-pack normalisation matters most; glossy metallised film — the hardest OCR surface in the set |
> | **Namkeen** | Long, additive-rich ingredient lists; highly variable label layouts across regional manufacturers; the strongest test of ingredient parsing |
> | **Instant noodles** | Multi-component packs (cake + seasoning sachet) with separate or combined declarations — the strongest test of parser robustness against structural ambiguity |
>
> These four are deliberately chosen to be *adversarial*, not convenient. Between them they cover the worst OCR surface, the longest ingredient lists, the most aggressive serving-size behaviour, and the most structurally ambiguous panel layout in the Indian market. A parser that handles these four is unlikely to be defeated by biscuits' easier neighbours.
>
> **The schedule risk is real and is not eliminated by this decision.** Category-agnostic architecture costs no more engineering time than category-specific — arguably less, since it forbids special-casing. But the knowledge base and corpus work (M5, M12) still gate the quality bar. The honest position: **scope of validation is the variable; the quality bar is fixed.** If day 25 arrives with three categories at target accuracy and one below it, we ship three and say so publicly. We do not ship four at a lower bar and stay quiet about it.

### 9.4 Explicit MVP non-goals

Barcode scanning · cloud sync · accounts · allergen determination · composite health score · Devanagari OCR · iOS · product comparison · recommendations · any monetisation.

---

## 10. Long-term Vision

Sequenced, with each stage gated on the previous. Nothing here may influence MVP scope; everything here must remain architecturally reachable.

### Stage 1 — Depth *(v1.x)*
Expand product-category coverage and the golden corpus. Complete the Hindi content layer with reviewed nutrition terminology. Optional, user-initiated rule-pack refresh. Publish measured parser accuracy per category.

### Stage 2 — Reach *(v2.x)*
Devanagari OCR for Hindi-only labels. Additional Indian languages, ranked by market need. Accessibility work, including screen-reader support and audio output — a meaningful accessibility win for low-literacy users, which is arguably the most underserved segment of all.

### Stage 3 — Breadth *(v3.x)*
Extend beyond food into **cosmetics** (INCI ingredient nomenclature), **supplements**, and **over-the-counter medicines**. This is the payoff for treating the rule engine as data: each new domain is a new rule pack and knowledge base against the same core, not a new application.

### Stage 4 — Infrastructure
Publish the additive and threshold knowledge base as a standalone, openly-licensed, citable dataset that other projects can consume. The most durable long-term contribution LabelWise India can make may be the curated, cited knowledge base rather than the application itself.

### What will never be built
Cloud-dependent core functionality · advertising · data monetisation · personalised medical advice · any feature requiring an account.

---

## 11. Risks

Scored as **Impact × Likelihood**. Ordered by severity.

### R1 — Parser accuracy is insufficient for trust — **Critical / High**
Real labels are curved, glossy, badly printed, multi-column and inconsistently formatted. A parser that misreads sodium is worse than no app.
**Mitigation:** golden corpus from Phase 2 onward; published accuracy figure; confidence reporting on every field; mandatory manual correction UI; refusal to output a value the parser is not confident about (P1).
**Early warning:** first 20 corpus labels yield below 70% critical-field accuracy.

### R2 — Knowledge base curation is underestimated — **High / High**
M5 and M7 need a cited, reviewed additive and threshold dataset. This is research work, not coding, and it silently consumes schedule.
**Mitigation:** start curation in Phase 2 in parallel with architecture; scope to categories actually in the MVP (see §9.3); define the schema before populating; treat "cited" as a hard schema constraint, not a convention.

### R3 — The 30-day timeline forces a quality compromise — **High / High**
The stated schedule and the stated quality bar are in tension (§9.3).
**Mitigation:** four prioritised validation categories rather than open-ended market coverage (§9.3); category-agnostic architecture so that scope reduction is a data decision, not a code rewrite; fix the phase gates now; treat the quality bar as fixed and validation scope as the variable. Never the reverse. If a category misses the accuracy bar at the gate, ship the categories that pass and publish the gap.

### R4 — Advisory output is mistaken for medical advice — **High / Medium**
A user with a medical condition acts on a Layer 2 flag. Reputational and potentially legal exposure.
**Mitigation:** rigid Layer 1 / Layer 2 separation (P5); citation on every claim (P8); explanation attached to every advisory finding (P3), so a user can see the reasoning rather than receiving a bare verdict; explicit in-product disclaimer; no personalisation; allergen determination out of scope and stated as such; decide licence and disclaimer posture in Phase 1, not at launch.

### R5 — Regulatory ground shifts under the rules — **Medium / High**
FSSAI's front-of-pack framework is unsettled — the INR draft is being withdrawn and further research commissioned; a labelling amendment on bold-type declaration of sugar, salt and saturated fat is pending. Rules baked into code become stale and wrong.
**Mitigation:** rules as versioned data (P10); rule pack designed for refresh from day one; Layer 1 restricted to gazetted requirements only; regulatory review scheduled at each phase gate.

### R6 — Solo-developer bus factor and review vacuum — **Medium / High**
No colleague catches a bad decision. Illness or fatigue halts everything.
**Mitigation:** documentation-first as a substitute for peer review; small, self-contained, independently-shippable modules; decisions recorded with rationale so a future contributor — or a future self — can reconstruct the reasoning.

### R7 — Scope creep from compelling adjacent features — **Medium / High**
Barcode scanning, a health score, allergen alerts and product comparison will all feel obviously worth adding.
**Mitigation:** §5 exists specifically to make refusal fast; any scope change requires a documented revision to this file.

### R8 — Device fragmentation and performance — **Medium / Medium**
Low-end devices, poor cameras, constrained storage.
**Mitigation:** define a reference low-end device in Phase 1 and test against it throughout; APK budget as a tracked metric (E9); profile before optimising.

### R9 — Advisory layer flags nearly everything, becoming noise — **Medium / Medium**
SEARO thresholds applied to the Indian market flag roughly two thirds of products. If the app says "high in something" on almost every scan, the signal degrades to wallpaper.
**Mitigation:** treat this as a UX problem, not a threshold problem — do not weaken the science to reduce alerts. Rank flags by severity; surface magnitude ("3.2× the reference level"), not just a binary; make the factual layer the primary display and advice the secondary. The explanation payload required by P3 already carries the margin, so magnitude-based ranking is free rather than an additional build.

### R10 — Dependency abandonment or breaking change — **Medium / Low**
An OCR or camera package is abandoned or breaks.
**Mitigation:** adapter interfaces around every third-party capability (§7.2); a documented exit path per dependency; prefer Google-maintained packages for OCR.

### R11 — Hindi content quality — **Medium / Medium**
Machine-translated nutrition guidance is inaccurate at best and alarming at worst. Translating "high in saturated fat" correctly and non-judgementally is a content problem, not a string-table problem.
**Mitigation:** localisation architecture from day one (M10) but Hindi *content* gated on human review; ship English-only rather than ship bad Hindi; build a reviewed nutrition glossary before translating messages.

### R12 — The ₹0 budget is not literally ₹0 — **Low / High**
A Google Play developer account is a one-time US$25 registration fee (no annual renewal), and physical test devices cost money.
**Mitigation:** read the constraint as **₹0 recurring cost** — no servers, no paid APIs, no subscriptions. Acknowledge the one-time costs in planning rather than being surprised by them. Distribution via GitHub Releases / F-Droid is a viable zero-cost fallback.

### R13 — English-only OCR has a real, legally-permitted blind spot — **Medium / Medium**
A common assumption is that Indian labels always carry English. They do not. FSSAI requires mandatory declarations in **English *or* Hindi in Devanagari script** — regional languages may be added but cannot replace either. A Hindi-only label is fully compliant and will be unreadable to the MVP.
In practice, national FMCG brands label in English almost universally, so English-only OCR captures the large majority of the target market. But the gap is real, is concentrated in regional and smaller brands, and will be invisible to us until users hit it.
**Mitigation:** state the limitation plainly in-product and in the README rather than letting users discover it; detect Devanagari-dominant images and return an honest "this label is not in a language I can read yet" instead of a bad parse (P1); track Hindi-only encounters as a signal for prioritising Stage 2; keep the OCR adapter interface script-agnostic so adding Devanagari is an adapter change, not a redesign.

---

## 12. Approved Decisions

The following departed from or sharpened the original brief. All are now approved and binding; changing any of them requires a revision to this document.

| # | Decision | Status | Section |
|---|---|---|---|
| 1 | Treat the **parser**, not OCR, as the core IP and the primary architectural and testing investment | ✅ Approved | §2.3 |
| 2 | Anchor Layer 2 on **WHO SEARO + ICMR-NIN**, because no finalised FSSAI nutrient-profile model exists | ✅ Approved | §4.3 |
| 3 | Key the additive knowledge base on **INS number**, exploiting India's mandatory INS declaration | ✅ Approved | §4.2 |
| 4 | **No composite health score** in the MVP — per-nutrient flags only | ✅ Approved | §5 |
| 5 | Design the rule pack as a **versioned, refreshable data asset** from day one | ✅ Approved | §6 |
| 6 | Build a **golden corpus of ≥ 50 real labels** as a first-class Phase-2 deliverable | ✅ Approved | §7.3 |
| 7 | ~~Narrow the MVP to two product categories~~ → **Category-agnostic parser and rule engine from day one**, with biscuits, chips, namkeen and instant noodles prioritised for MVP validation and corpus construction | ✅ **Approved with modification** | §9.3 |
| 8 | Resolve the **privacy-versus-metrics contradiction** in favour of privacy, using explicit user-initiated export | ✅ Approved | §8.2 |
| 9 | Gate **Hindi content** on human review; ship English-only rather than poor Hindi | ✅ Approved | §11 R11 |
| 10 | Decide **licence and medical-disclaimer posture** during Phase 1, not at launch | ✅ Approved | §11 R4 |
| 11 | Detect and honestly decline **Devanagari-dominant labels** rather than mis-parsing them — English is not legally guaranteed on Indian labels | ✅ Approved | §11 R13 |
| 12 | **Explainability as a first-class design principle** — every advisory output explains why it fired and references its supporting rule | ✅ Added by owner | §6 P3 |
| 13 | **Confidence reporting** across OCR, parsing and every extracted field, surfaced to the user | ✅ Added by owner | §6 P2 |

---

## 13. Phase 1 Document Set

This document is the first of six. The remainder follow in order, each gated on approval of the last.

| # | Document | Purpose | Status |
|---|---|---|---|
| 1 | `PROJECT_VISION.md` | Mission, scope, principles, risks — this document | **Approved v1.1** |
| 2 | `REQUIREMENTS.md` | Functional and non-functional requirements, traceable to §4 | **Approved v1.1** |
| 3 | `ARCHITECTURE.md` | Layers, boundaries, module design, folder structure, data flow | **Approved v1.0** |
| 3a | [`adr/`](adr/README.md) | Immutable decision log preserving rationale | **20 records accepted** |
| 4 | `DATA_MODEL.md` | Nutrition record, ingredient record, rule pack and knowledge base schemas | **Approved v1.1** |
| 5 | `TEST_STRATEGY.md` | Unit/widget/integration strategy, golden corpus methodology, critical-field definition | **Approved v1.0** |
| 6 | `ROADMAP.md` | Phases, milestones, gates, sequencing, readiness checklist | **Draft** |

---

## 14. Sources

Regulatory, scientific and technical claims in this document are drawn from:

- Food Safety and Standards (Labelling and Display) Regulations, 2020 — gazetted 14 December 2020; nutrition declaration and RDA denominator requirements.
- FSSAI 44th Food Authority meeting (2024) — approved amendment on bold/enlarged declaration of total sugar, salt and saturated fat.
- FSSAI affidavit to the Supreme Court of India (2026) — proposed withdrawal of the 2022 draft Front-of-Pack Nutrition Labelling / Indian Nutrition Rating regulations pending further research.
- Food Safety and Standards (Food Products Standards and Food Additives) Regulations, 2011 — additive declaration by class title and INS number.
- FSSAI packaging and labelling language requirement — mandatory declarations in English or Hindi (Devanagari script); regional languages permitted as additions only.
- WHO Nutrient Profile Model for the South-East Asia Region (2017).
- Pandav, Taillie et al., *"The WHO South-East Asia Region Nutrient Profile Model Is Quite Appropriate for India: An Exploration of 31,516 Food Products"*, Nutrients, 2021.
- Google ML Kit Text Recognition v2 — on-device capability, script support and APK size characteristics.
- Open Food Facts — India database coverage figures.

*Full citations with URLs and access dates are maintained in the knowledge base source registry (see `DATA_MODEL.md`).*

---

*End of document. Approval required before proceeding to `REQUIREMENTS.md`.*
