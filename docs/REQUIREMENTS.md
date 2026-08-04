# LabelWise India — Requirements Specification

| Field | Value |
|---|---|
| **Document** | `docs/REQUIREMENTS.md` |
| **Version** | 1.3 |
| **Status** | **Approved** |
| **Phase** | Phase 1: Architecture & Planning |
| **Author** | Chief Software Architect |
| **Date** | 4 August 2026 |
| **Parent document** | `PROJECT_VISION.md` v1.1 (approved) |
| **Successor** | `ARCHITECTURE.md` (in progress) |

**Changes in v1.1** — Q1, Q5 and Q6 resolved by the owner. Reference device nominated (§12.2). Licence and disclaimer text fixed (§12.3).

**Changes in v1.3** — Release-scoped priority applied (`P0_REPRIORITISATION.md`, approved). 22 Layer 2 / advisory-explanation requirements become **P0-v0.2**; 5 become P1; the remainder are **P0-v0.1**.

**Changes in v1.2** — Q19 approved (ADR-0027). Three requirements added for qualified quantities: FR-PAR-18, FR-CNF-14, FR-L2-14. IDs are never reused, so these append rather than renumber.

---

## 0. How To Read This Document

This document converts the approved scope in `PROJECT_VISION.md` §4 into **individually verifiable statements**. It says *what* the system must do. It does not say *how* — no modules, no packages, no file layout, no state management. Those decisions belong to `ARCHITECTURE.md` and are deliberately absent here so that architecture can be judged against requirements rather than co-written with them.

### 0.1 Requirement identity

Every requirement has a permanent ID of the form `FR-<GROUP>-<nn>` or `NFR-<GROUP>-<nn>`. **IDs are never reused and never renumbered.** A withdrawn requirement is marked withdrawn and left in place. Architecture, test cases and code comments cite these IDs; renumbering would silently break that chain.

### 0.2 Priority

Priority is **scoped by release** (ADR-0025). "MVP-blocking" is two questions, not one.

| Level | Meaning |
|---|---|
| **P0-v0.1** | Blocks the Factual release |
| **P0-v0.2** | Blocks the Advisory release; not required for v0.1 |
| **P1** | Expected in its release unless explicitly deferred with a recorded reason |
| **P2** | Post-MVP. Specified now because it constrains the architecture; not built now. |

The original single-priority scheme put 84% of requirements at P0, which meant the field carried no scheduling information. I first proposed demoting polish requirements and named nine candidates — **checking that list showed every one was already P1.** The P0 set contained almost no padding; the real problem was that this document predated the release split.

Release scoping fixes it without demotion theatre: it says *when* each requirement blocks, which is what the field was always supposed to convey. See [`P0_REPRIORITISATION.md`](P0_REPRIORITISATION.md).

### 0.3 Verification method

Every requirement states how it will be proven. A requirement with no verification method is not a requirement — it is an aspiration, and does not belong in this document.

| Code | Method |
|---|---|
| **U** | Unit test in the domain core |
| **W** | Widget test |
| **G** | Golden corpus test against real labels |
| **P** | Property-based / invariant test |
| **S** | Static analysis or build-time check |
| **I** | Instrumented measurement on the reference device |
| **M** | Manual review at a phase gate |

### 0.4 Language

**MUST** — mandatory. **MUST NOT** — prohibited. **SHOULD** — strongly expected; deviation requires a recorded reason. **MAY** — permitted, at the implementer's discretion.

### 0.5 Traceability

Each requirement traces to a section of `PROJECT_VISION.md` and, where applicable, to a Design Principle (P1–P10). §14 carries the reverse matrix: every vision commitment mapped to the requirements that discharge it. Any vision commitment with no requirement is a gap; any requirement with no vision trace is scope creep.

---

## 1. Glossary

Terms are defined once, here, and used consistently throughout the project. Ambiguity in this glossary becomes ambiguity in the code.

| Term | Definition |
|---|---|
| **Label** | The physical printed surface carrying a product's mandatory declarations. |
| **Nutrition panel** | The tabular declaration of nutrient values required by FSSAI Labelling & Display Regulations 2020. |
| **Ingredient list** | The ordered declaration of ingredients, including additives declared by class title and INS number. |
| **Capture** | A single user-initiated image acquisition event. |
| **Scan** | One complete pipeline execution: capture → OCR → parse → confidence → analyse → present. |
| **Extraction** | Producing a typed value from OCR text. |
| **Field** | A single typed datum, e.g. `saturatedFat.per100g`. |
| **Critical field** | A field whose incorrect extraction materially misleads the user. Enumerated in §4.3. Basis of the E4 accuracy metric. |
| **Basis** | The reference quantity a value is expressed against: `PER_100G`, `PER_100ML`, `PER_SERVE`, or `PER_PACK`. |
| **Serve** | The serving size declared by the manufacturer. Manufacturer-chosen, not standardised. |
| **Net quantity** | The total declared contents of the pack. |
| **Invariant** | A deterministic arithmetic relationship that must hold between fields on a valid label. Enumerated in §5.3. |
| **Confidence** | A four-level classification of how much trust an extracted field warrants. §5.2. |
| **Rule** | A single declarative unit of analysis logic, held as data, with an ID, version, condition, threshold and citation. |
| **Rule pack** | The versioned, integrity-checked bundle of all rules, thresholds, additive records, message text and source citations. |
| **Finding** | A single output of the analysis engine — factual (Layer 1) or advisory (Layer 2). |
| **Explanation** | The mandatory structured justification attached to every advisory finding. §8.2. |
| **Layer 1 / Factual** | Analysis that restates declared facts and gazetted arithmetic. Contains no judgement. |
| **Layer 2 / Advisory** | Analysis that interprets Layer 1 against published nutrition evidence. Contains judgement, and says so. |
| **Source** | A citable published reference held in the rule pack's source registry. |
| **Category** | A product classification (e.g. biscuits). An *optional attribute*, never a precondition for the pipeline. |
| **Priority category** | One of the four categories prioritised for MVP validation: biscuits, chips, namkeen, instant noodles. |
| **Golden corpus** | The versioned set of real label images paired with hand-verified expected parse results. |
| **Reference device** | The nominated low-to-mid-range Android device against which all performance requirements are measured. §12.2. |

---

## 2. Actors

| Actor | Description | Requirements affected |
|---|---|---|
| **Consumer** | The primary user (`PROJECT_VISION.md` §3.1). The only human actor in the MVP. | All FR groups |
| **Contributor** | An external engineer or nutrition reviewer extending the rule pack or corpus. | FR-KB, NFR-MNT |
| **Maintainer** | The solo developer. Owns the rule pack and corpus. | FR-KB, NFR-MNT, NFR-TST |
| **Device camera** | Platform capability behind an adapter. | FR-CAP |
| **OCR engine** | Third-party on-device text recogniser behind an adapter. | FR-OCR |
| **Local storage** | On-device persistence behind an adapter. | FR-HIS |

There is **no server actor, no authentication actor and no analytics actor**, by design (`PROJECT_VISION.md` P7).

---

## 3. Assumptions

Recorded so that they can be invalidated deliberately rather than discovered painfully. Each carries the requirement most at risk if it proves false.

| # | Assumption | If false | At risk |
|---|---|---|---|
| A1 | Target products carry mandatory declarations in English | Devanagari-only labels are unreadable to the MVP | FR-OCR-05, R13 |
| A2 | The on-device OCR engine returns per-element text with positional geometry and a confidence signal | The confidence model loses signal S1 and must lean harder on S2/S3 | FR-CNF-02 |
| A3 | Nutrition panels are tabular or near-tabular in layout | Layout-based parsing degrades; heuristic fallback rate rises | FR-PAR-03 |
| A4 | INS numbers are printed and legible on most labels | Additive resolution falls back to name matching at lower confidence | FR-PAR-11 |
| A5 | FSSAI RDA denominators remain as gazetted in the 2020 regulations | Layer 1 %RDA arithmetic must be revised — mitigated by rules-as-data | FR-L1-04 |
| A6 | WHO SEARO thresholds remain the best available regional anchor | Layer 2 thresholds require re-sourcing — mitigated by rules-as-data | FR-L2-02 |
| A7 | Users will tolerate a correction step when confidence is low | Correction UI is ignored and low-confidence values are trusted anyway | FR-COR-01, FR-CNF-08 |

> **⚠ Architect's Note — A2 deserves scrutiny before architecture is finalised.**
>
> The confidence model in §5 assumes three independent signals. Signal S1 depends entirely on what the OCR adapter actually exposes. If the chosen engine does not surface per-element confidence — or surfaces something that turns out to be poorly calibrated in practice — then S1 is worthless and the model rests on S2 and S3 alone.
>
> That is survivable: **S3 (arithmetic invariant validation) is the strongest of the three signals anyway**, because it is engine-independent, deterministic, and catches the failure mode that actually matters — a misread digit. But the confidence design must degrade gracefully rather than assume S1 exists. **This must be verified experimentally in the first week of Phase 2, before the confidence model is implemented.** It is the cheapest possible de-risking spike and it gates a first-class principle.

---

## 4. Functional Requirements — Capture, OCR, Parsing

### 4.1 FR-CAP — Capture

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-CAP-01 | The system MUST allow the user to capture a label image using the device camera. | P0-v0.1 | W, M | §4.1 |
| FR-CAP-02 | The system MUST allow the user to select an existing image from device storage. | P0-v0.1 | W, M | §4.1 |
| FR-CAP-03 | The system MUST allow separate captures for the nutrition panel and the ingredient list, and MUST allow either to be supplied alone. | P0-v0.1 | W, U | §4.1 |
| FR-CAP-04 | The system MUST display framing guidance during capture indicating the expected region of interest. | P1 | W, M | §3.1 |
| FR-CAP-05 | The system MUST allow the user to retake a capture before processing. | P0-v0.1 | W | §4.1 |
| FR-CAP-06 | The system MUST NOT require network access at any point in the capture flow. | P0-v0.1 | I | P6 |
| FR-CAP-07 | The system MUST NOT persist a captured image outside the device, transmit it, or include it in any automated report. | P0-v0.1 | S, I | P7 |
| FR-CAP-08 | The system SHOULD warn the user before processing when the captured image fails a basic quality heuristic (severe blur or severe underexposure). | P1 | U, W | P1 |
| FR-CAP-09 | The system MUST function with the camera permission granted for capture only, and MUST degrade to gallery import if the permission is denied. | P1 | W, M | §3.1 |
| FR-CAP-10 | Captured images MAY be retained on-device as part of scan history, at the user's option, and MUST be deletable. | P1 | U, W | P7, FR-HIS |

### 4.2 FR-OCR — Text recognition

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-OCR-01 | Text recognition MUST execute entirely on-device with no network call. | P0-v0.1 | I, S | P6 |
| FR-OCR-02 | Text recognition MUST be accessed through an adapter interface; no consumer of OCR output may depend on a specific engine. | P0-v0.1 | S, U | §7.2 |
| FR-OCR-03 | The OCR adapter MUST return recognised text elements with positional geometry sufficient to reconstruct reading order and column structure. | P0-v0.1 | U | FR-PAR-03 |
| FR-OCR-04 | The OCR adapter MUST expose any per-element confidence signal the underlying engine provides, and MUST explicitly report its absence rather than substituting a default value. | P0-v0.1 | U | P1, P2 |
| FR-OCR-05 | The system MUST detect when a captured image is predominantly non-Latin script and MUST return an explicit unsupported-language result rather than attempting a parse. | P0-v0.1 | U, G | P1, R13 |
| FR-OCR-06 | The system MUST NOT alter, correct or "improve" recognised text before parsing; all normalisation MUST occur in the parsing stage where it is traceable. | P0-v0.1 | U | P4 |
| FR-OCR-07 | OCR failure MUST be surfaced as a distinct, actionable outcome, never as an empty successful result. | P0-v0.1 | U, W | P1, FR-ERR |
| FR-OCR-08 | Devanagari script recognition is a P2 capability; the adapter interface MUST accommodate it without redesign. | P2 | M | §10 Stage 2 |

### 4.3 FR-PAR — Parsing

The parser is the core intellectual property of the project (`PROJECT_VISION.md` §2.3). These requirements carry the heaviest verification burden in the document.

**Critical fields**, for the purposes of FR-PAR-15 and metric E4:

`energy` · `protein` · `carbohydrate` · `totalSugars` · `addedSugars` · `totalFat` · `saturatedFat` · `transFat` · `sodium` · `servingSize` · `servingsPerPack` · `netQuantity`

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-PAR-01 | Parsing MUST be a pure function of OCR output and rule pack version: no I/O, no clock, no locale dependence, no randomness. | P0-v0.1 | U, P, S | P4 |
| FR-PAR-02 | Identical input MUST produce byte-identical output, including confidence classifications, on every platform and every run. | P0-v0.1 | P, G | P4, E3 |
| FR-PAR-03 | The parser MUST reconstruct tabular structure from positional geometry, handling single-column, two-column and per-100g/per-serve paired layouts. | P0-v0.1 | U, G | §2.3 |
| FR-PAR-04 | The parser MUST extract each nutrient value together with its unit and its basis (`PER_100G`, `PER_100ML`, `PER_SERVE`, `PER_PACK`). | P0-v0.1 | U, G | §4.2 |
| FR-PAR-05 | The parser MUST NOT emit a value whose unit or basis could not be determined; such a value MUST be reported as unresolved. | P0-v0.1 | U | P1 |
| FR-PAR-06 | The parser MUST normalise recognised unit variants (`g`, `gm`, `gms`, `mg`, `kcal`, `kJ`, `ml`) to canonical units, and MUST record that a normalisation occurred. | P0-v0.1 | U, G | P4 |
| FR-PAR-07 | The parser MUST convert energy declared in kJ to kcal, retaining the original declared value and marking the conversion. | P1 | U | §4.3 |
| FR-PAR-08 | The parser MUST extract declared serving size, servings per pack and net quantity where present. | P0-v0.1 | U, G | FR-L1-05 |
| FR-PAR-09 | The parser MUST report every critical field as one of: extracted, unresolved, or absent from the label. The three MUST be distinguishable. | P0-v0.1 | U, G | P1 |
| FR-PAR-10 | The parser MUST extract the ingredient list as an ordered sequence, preserving declaration order. | P0-v0.1 | U, G | §4.2 |
| FR-PAR-11 | The parser MUST resolve additives by INS number as the primary key, and MAY fall back to name matching at explicitly lower confidence. | P0-v0.1 | U, G | §4.2 |
| FR-PAR-12 | The parser MUST handle nested and parenthetical ingredient declarations without losing the parent-child relationship. | P1 | U, G | §4.2 |
| FR-PAR-13 | The parser MUST record, for every extracted field, which parse rule produced it and at what strength (`EXACT`, `NORMALISED`, `HEURISTIC`). | P0-v0.1 | U | P2, P3 |
| FR-PAR-14 | The parser MUST tolerate partial input: a nutrition panel without an ingredient list, or the reverse, MUST produce a complete result for the portion supplied. | P0-v0.1 | U, G | FR-CAP-03 |
| FR-PAR-15 | The parser MUST achieve ≥ 85% correct extraction of critical fields across the golden corpus, reported overall **and per priority category**. | P0-v0.1 | G | E4 |
| FR-PAR-16 | The parser MUST NOT contain category-specific branching. | P0-v0.1 | S, M | FR-CAT-01 |
| FR-PAR-17 | Parsing failure MUST yield a structured failure result identifying what could not be parsed, never a silent empty success. | P0-v0.1 | U | P1, FR-ERR |
| FR-PAR-18 | The parser MUST extract the qualifier of a declared value (`EXACT`, `LESS_THAN`, `GREATER_THAN`, `APPROXIMATELY`) and MUST NOT coerce a bound or approximation to a point value. | P0-v0.1 | U, G | ADR-0027 |

> **⚠ Architect's Note — FR-PAR-15 will be the most uncomfortable requirement in this project, and that is intentional.**
>
> An 85% critical-field accuracy target sounds modest until it is measured honestly on metallised chip packaging in poor light. Expect the first corpus run to land far below it. The correct response is to improve the parser and the confidence model — not to quietly redefine "critical field", loosen the comparison, or curate an easier corpus.
>
> The number gets published in the README either way. That is precisely what makes it worth having.

---

## 5. Functional Requirements — Confidence

Confidence is a first-class principle (P2) and therefore gets its own requirement group rather than being folded into parsing.

### 5.1 Design intent

The user must never have to wonder whether a number on screen was read cleanly or reconstructed hopefully. Confidence exists to make the difference visible without demanding that the user understand OCR.

### 5.2 Confidence classification

The system uses exactly four levels. **A numeric percentage MUST NOT be shown to the user** — it implies a precision the underlying signals do not possess.

| Level | Meaning | User-facing intent |
|---|---|---|
| **HIGH** | Clean recognition, exact parse-rule match, all applicable invariants satisfied | Trust this |
| **MEDIUM** | Recognised with minor uncertainty or via a normalising rule; invariants satisfied | Probably right; check if it matters to you |
| **LOW** | Poor recognition, heuristic-only parse, or a failed invariant | Check this by hand |
| **ABSENT** | Not present on the label, or not found | Nothing to trust — the label did not say |

### 5.3 Arithmetic invariants

Deterministic, engine-independent checks. These are the strongest confidence signal available and require no model, no network and no training data.

| ID | Invariant |
|---|---|
| INV-01 | All declared values ≥ 0 |
| INV-02 | `saturatedFat` ≤ `totalFat` |
| INV-03 | `transFat` ≤ `totalFat` |
| INV-04 | `addedSugars` ≤ `totalSugars` |
| INV-05 | `totalSugars` ≤ `carbohydrate` |
| INV-06 | `protein + carbohydrate + totalFat` ≤ 100 g per 100 g |
| INV-07 | Declared energy reconciles with Atwater estimate (4·protein + 4·carbohydrate + 9·fat) within a defined tolerance band |
| INV-08 | `perServe` ≈ `per100g` × (`servingSize` ÷ 100), within tolerance |
| INV-09 | `servingSize` ≤ `netQuantity` |
| INV-10 | `servingsPerPack` ≈ `netQuantity` ÷ `servingSize`, within tolerance |

### 5.4 Requirements

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-CNF-01 | Every extracted field MUST carry exactly one confidence classification. A field without one MUST NOT be representable in the data model. | P0-v0.1 | S, U | P2, E5b |
| FR-CNF-02 | Confidence MUST be computed from three signals: OCR character confidence (S1), parse-rule strength (S2), and arithmetic invariant validation (S3). | P0-v0.1 | U | P2 |
| FR-CNF-03 | Confidence computation MUST degrade gracefully when S1 is unavailable, deriving classification from S2 and S3 alone, and MUST record that S1 was absent. | P0-v0.1 | U | A2 |
| FR-CNF-04 | The system MUST evaluate all applicable invariants in §5.3 and MUST record which passed, which failed, and which were inapplicable for want of data. | P0-v0.1 | U, P | P2 |
| FR-CNF-05 | A field participating in a failed invariant MUST NOT be classified HIGH. | P0-v0.1 | U, P | P1, P2 |
| FR-CNF-06 | Confidence computation MUST be deterministic: identical inputs yield identical classifications, always. | P0-v0.1 | P, G | P4 |
| FR-CNF-07 | The system MUST produce an aggregate scan-level confidence derived from the field-level classifications by a documented, deterministic rule. | P1 | U | P2 |
| FR-CNF-08 | The UI MUST visually distinguish HIGH, MEDIUM, LOW and ABSENT fields without requiring the user to open a detail view. | P0-v0.1 | W, M | P2, P9 |
| FR-CNF-09 | The UI MUST direct the user toward correction of LOW-confidence fields specifically. | P0-v0.1 | W | P2, FR-COR |
| FR-CNF-10 | The system MUST NOT display a numeric confidence percentage to the user. | P0-v0.1 | W, M | P1, P2 |
| FR-CNF-11 | Fields classified HIGH MUST be correct in ≥ 98% of golden corpus instances. | P0-v0.1 | G | E5c |
| FR-CNF-12 | A user-corrected field MUST be recorded as user-supplied and MUST NOT be assigned an inferred confidence. | P0-v0.1 | U, W | P1, FR-COR-04 |
| FR-CNF-13 | Layer 2 MUST NOT emit an advisory finding derived solely from LOW-confidence inputs without marking the finding as provisional. | P0-v0.1 | U | P1, P3 |
| FR-CNF-14 | Invariant evaluation MUST treat quantities as intervals and MUST report `INDETERMINATE` where the declarations do not settle the comparison. `INDETERMINATE` MUST NOT cap confidence and MUST NOT be treated as `FAILED`. A qualifier MUST NOT influence confidence assignment. | P0-v0.1 | U, P | ADR-0027, MI-15 |

> **⚠ Architect's Note — FR-CNF-13 is the requirement that stops confidence from being cosmetic.**
>
> It is easy to build a confidence system that displays a badge and then computes advice from the same suspect number anyway. That is worse than having no confidence system, because it lends the advice an unearned appearance of rigour.
>
> If a sodium reading is LOW confidence, any "high in sodium" verdict resting on it inherits that uncertainty and must say so. Confidence has to propagate through the analysis, not merely decorate the extraction.

---

## 6. Functional Requirements — Knowledge Base & Rule Pack

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-KB-01 | All thresholds, rules, additive records, message text and citations MUST live in versioned data assets, not in code. | P0-v0.1 | S, M | P10 |
| FR-KB-02 | The rule pack MUST carry a semantic version, and every finding MUST record the rule pack version that produced it. | P0-v0.1 | U | P3, P4 |
| FR-KB-03 | The rule pack MUST be schema-validated at build time; an invalid pack MUST fail the build, not the app at runtime. | P0-v0.1 | S | E6 |
| FR-KB-04 | Every advisory rule MUST reference at least one entry in the source registry. A rule without a citation MUST fail validation. | P0-v0.1 | S | P8, E5 |
| FR-KB-05 | The source registry MUST record, for each source: identifier, title, publisher, publication date, and access date. | P0-v0.1 | S, M | P8 |
| FR-KB-06 | Additive records MUST be keyed on INS number and MUST carry common name, functional class, and a plain-language description. | P0-v0.1 | S, U | §4.2 |
| FR-KB-07 | Additive records MUST distinguish established evidence from contested or limited evidence, and MUST NOT overstate certainty. | P0-v0.1 | M | P1, P8 |
| FR-KB-08 | The rule pack MUST be bundled in the application and fully functional with no network access. | P0-v0.1 | I | P6 |
| FR-KB-09 | The rule pack format MUST support integrity verification and out-of-band replacement without an application update. | P1 | U | §6 note, R5 |
| FR-KB-10 | Optional user-initiated rule pack refresh over the network is a P2 capability; the format MUST NOT require redesign to enable it. | P2 | M | §6 note |
| FR-KB-11 | Rules MAY be scoped to a category via a declarative selector held in data; category scoping MUST NOT appear as code branching. | P0-v0.1 | S, U | FR-CAT-04 |
| FR-KB-12 | A contributor MUST be able to add an additive record or a threshold rule using documentation alone, without modifying Dart source. | P0-v0.1 | M | E11, P10 |
| FR-KB-13 | All user-facing message text MUST reside in the rule pack or message catalogue under stable message IDs, never inline in code. | P1 | S | FR-LOC-01 |

---

## 7. Functional Requirements — Analysis

### 7.1 FR-L1 — Layer 1: Factual engine

Restates declared facts and gazetted arithmetic. **Contains no judgement.**

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-L1-01 | Layer 1 MUST NOT emit any evaluative, comparative or advisory statement. | P0-v0.1 | U, M | P5 |
| FR-L1-02 | Layer 1 MUST normalise all declared nutrient values to a per-100 g/100 ml basis where the input permits. | P0-v0.1 | U | §4.3 |
| FR-L1-03 | Layer 1 MUST compute whole-pack values from per-100 g values and net quantity where both are available. | P0-v0.1 | U | §4.3 |
| FR-L1-04 | Layer 1 MUST compute %RDA contribution using the FSSAI-gazetted denominators (2,000 kcal; 67 g total fat; 22 g saturated fat; 2 g trans fat; 50 g added sugar; 2,000 mg sodium), sourced from the rule pack. | P0-v0.1 | U | §4.3, A5 |
| FR-L1-05 | Layer 1 MUST perform serving-size reconciliation, reporting declared serve, servings per pack, and whole-pack totals side by side. | P0-v0.1 | U, W | §2.1 |
| FR-L1-06 | Layer 1 MUST identify mandatory declarations absent from the label and report them as declaration gaps. | P0-v0.1 | U | §4.3 |
| FR-L1-07 | Layer 1 MUST resolve each declared additive to its INS record and report class, common name and plain-language description. | P0-v0.1 | U | §4.3 |
| FR-L1-08 | Layer 1 MUST propagate the confidence of every input field into every derived value it computes. | P0-v0.1 | U, P | P2, FR-CNF-13 |
| FR-L1-09 | Layer 1 MUST NOT infer a missing value from other values except where the derivation is arithmetically exact, and MUST mark any such derivation as derived. | P0-v0.1 | U | P1 |
| FR-L1-10 | Layer 1 output MUST be computable without knowledge of product category. | P0-v0.1 | U | FR-CAT-05 |

### 7.2 FR-L2 — Layer 2: Advisory engine

Interprets Layer 1 against published evidence. **Contains judgement, and labels it.**

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-L2-01 | Layer 2 MUST be architecturally separable from Layer 1: Layer 1 MUST remain fully functional with Layer 2 disabled. | P0-v0.2 | U, S | P5 |
| FR-L2-02 | Layer 2 thresholds MUST derive from the WHO South-East Asia Region Nutrient Profile Model, supplemented by ICMR-NIN guidance, sourced from the rule pack. | P0-v0.2 | U, M | §4.3, A6 |
| FR-L2-03 | Layer 2 MUST emit per-nutrient classifications for sugar, sodium, saturated fat and trans fat. | P0-v0.2 | U | §4.3 |
| FR-L2-04 | Layer 2 MUST NOT emit a composite health score, grade, star rating or ranking. | P0-v0.2 | S, M | §5 |
| FR-L2-05 | Every Layer 2 finding MUST carry a complete Explanation object (§8.2). A finding without one MUST NOT be representable. | P0-v0.2 | S, U | P3, E5a |
| FR-L2-06 | Every Layer 2 finding MUST be visually and textually marked as guidance, not as fact or medical advice. | P0-v0.2 | W, M | P5, R4 |
| FR-L2-07 | Layer 2 MUST report the margin by which a threshold was crossed, in absolute and ratio terms. | P0-v0.2 | U | R9, P3 |
| FR-L2-08 | Layer 2 MUST rank findings by severity so that the most significant finding is presented first. | P1 | U, W | R9 |
| FR-L2-09 | Layer 2 MUST mark as provisional any finding whose determining inputs are LOW confidence. | P0-v0.2 | U | FR-CNF-13 |
| FR-L2-10 | Layer 2 MUST NOT emit allergen-safety determinations. | P0-v0.2 | S, M | §5, §3.2 |
| FR-L2-11 | Layer 2 MUST NOT personalise thresholds to a user profile, condition or goal. | P0-v0.2 | S, M | §5 |
| FR-L2-12 | Layer 2 MUST produce a result for a product of unknown category, using category-independent rules. | P0-v0.2 | U | FR-CAT-05 |
| FR-L2-13 | Layer 2 MUST state explicitly when it has no finding to report, rather than presenting silence as endorsement. | P0-v0.2 | U, W | P1 |
| FR-L2-14 | Layer 2 MUST reason over qualified quantities as intervals, MUST emit an `UNDETERMINED` finding where a threshold comparison cannot be settled, and MUST NOT coerce a qualified quantity to a point value anywhere. `determinacy` and `provisional` MUST remain distinct. | P0-v0.2 | U, P | ADR-0027 |

> **⚠ Architect's Note — FR-L2-13 addresses a failure mode that is easy to miss.**
>
> If the advisory layer produces no flags, a user will read that as "this product is fine." That inference is not supported: it may equally mean the label was too incomplete to evaluate, or that the product's risks lie outside the four nutrients we assess.
>
> "No flags raised" and "nothing concerning here" are different statements, and only the first is one we can honestly make. Absence of a warning is not a clean bill of health, and the copy must say so.

---

## 8. Functional Requirements — Explainability

Explainability is a first-class principle (P3) and therefore gets its own requirement group.

### 8.1 Design intent

A user who can see *why* the app said something can disagree with it intelligently, correct a bad input, or decide the rule does not apply to them. A user shown a bare verdict can only obey or ignore it — and most will ignore it. Explainability is what converts the app from an oracle into an instrument.

### 8.2 Explanation contents

Every advisory finding carries an Explanation composed of:

| Element | Description |
|---|---|
| `ruleId` | Stable identifier of the rule that fired |
| `ruleVersion` | Version of that rule |
| `rulePackVersion` | Version of the pack the rule came from |
| `inputs` | Every field consumed: name, value, unit, basis, confidence |
| `threshold` | The comparison value, its unit and its basis |
| `operator` | The comparison applied |
| `margin` | Absolute and ratio distance from the threshold |
| `outcome` | The classification produced |
| `sourceRefs` | One or more source registry identifiers |
| `messageId` | Stable ID resolving to localised plain-language text |

### 8.3 Requirements

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-EXP-01 | Every advisory finding MUST carry an Explanation containing all elements in §8.2. | P0-v0.2 | S, U | P3, E5a |
| FR-EXP-02 | The Explanation MUST be produced by the same evaluation that produced the finding — never reconstructed separately or lazily. | P0-v0.2 | S, U | §6 P3 decision |
| FR-EXP-03 | A finding without a complete Explanation MUST NOT be representable in the data model. | P0-v0.2 | S, U | P3 |
| FR-EXP-04 | Every `ruleId` and `sourceRef` in an Explanation MUST resolve against the rule pack; a dangling reference MUST fail build-time validation. | P0-v0.2 | S | FR-KB-04 |
| FR-EXP-05 | The UI MUST make the Explanation reachable from every advisory finding within one interaction. | P0-v0.2 | W, M | P3 |
| FR-EXP-06 | The user-facing rendering of an Explanation MUST be in plain language, stating the value found, the threshold, the margin and the source. | P0-v0.2 | W, M | P9 |
| FR-EXP-07 | The Explanation MUST expose the confidence of every input it consumed. | P0-v0.2 | U, W | P2, FR-CNF-13 |
| FR-EXP-08 | Explanations MUST be deterministic: identical inputs and rule pack version yield identical Explanations. | P0-v0.2 | P, G | P4 |
| FR-EXP-09 | Layer 1 findings MUST expose their derivation (the arithmetic and inputs used), though they require no advisory citation. | P1 | U, W | P3, P5 |
| FR-EXP-10 | The Explanation MUST be serialisable so that it can be included in a user-initiated export. | P1 | U | §8.2 vision, FR-PRS-08 |
| FR-EXP-11 | The system MUST NOT present an advisory finding whose Explanation cannot be rendered. | P0-v0.2 | U, W | P1, P3 |

---

## 9. Functional Requirements — Category Agnosticism

Derived from the approved modification to Recommendation 7 (`PROJECT_VISION.md` §9.3). These requirements exist to make that modification verifiable rather than aspirational.

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-CAT-01 | The domain core MUST contain no category-specific conditional logic. | P0-v0.1 | S, M | §9.3, E5d |
| FR-CAT-02 | Product category MUST be an optional attribute. The pipeline MUST NOT require it to execute. | P0-v0.1 | U | §9.3 |
| FR-CAT-03 | Adding support for a new category MUST require changes to rule pack data only — no Dart source modification. | P0-v0.1 | M | E5d |
| FR-CAT-04 | Where a rule applies only to certain categories, that scoping MUST be expressed as a declarative selector in data. | P0-v0.1 | S, U | FR-KB-11 |
| FR-CAT-05 | The system MUST produce a complete, useful result for a product whose category is unknown. | P0-v0.1 | U, G | §9.3 |
| FR-CAT-06 | The build MUST include a "fifth category" verification: a category outside the prioritised four, added as data only, processed end to end without code change. | P0-v0.1 | M, G | E5d |
| FR-CAT-07 | The golden corpus MUST cover the four priority categories with no category below 10 labels. | P0-v0.1 | M | §7.3, M12 |
| FR-CAT-08 | Parser accuracy MUST be reported per category as well as in aggregate. | P0-v0.1 | G | FR-PAR-15 |

> **⚠ Architect's Note — FR-CAT-05 is the requirement that actually proves category-agnosticism.**
>
> FR-CAT-01 and FR-CAT-03 can both be satisfied by a system that quietly refuses to work until a category is chosen — the branching just moves from a conditional into a required input, and nothing has genuinely been decoupled.
>
> The real test is an unknown product processed end to end with a useful result. If that path is missing, the architecture has category-dependence hidden in its preconditions rather than its code, and FR-CAT-06 will not catch it.

---

## 10. Functional Requirements — Correction, Presentation, Localisation, History, Errors

### 10.1 FR-COR — Manual correction

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-COR-01 | The user MUST be able to view and edit every extracted field. | P0-v0.1 | W | §4.1 decision |
| FR-COR-02 | Correction MUST re-run the full analysis pipeline, producing updated findings, confidences and Explanations. | P0-v0.1 | U, W | P3, P4 |
| FR-COR-03 | The user MUST be able to supply a value for a field reported as ABSENT. | P0-v0.1 | W | P1 |
| FR-COR-04 | Corrected fields MUST be recorded as user-supplied and MUST NOT be overwritten by a subsequent re-parse of the same scan. | P0-v0.1 | U, W | FR-CNF-12 |
| FR-COR-05 | Correction MUST validate input against the §5.3 invariants and MUST warn — not block — when a user-supplied value violates one. | P1 | U, W | P1 |
| FR-COR-06 | The correction UI MUST prioritise LOW-confidence and ABSENT fields in its ordering. | P1 | W | FR-CNF-09 |
| FR-COR-07 | The user MUST be able to revert a correction to the originally extracted value. | P1 | W | — |

### 10.2 FR-PRS — Presentation

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-PRS-01 | Factual (Layer 1) and advisory (Layer 2) content MUST be visually distinguishable without reading the text. | P0-v0.1 | W, M | P5 |
| FR-PRS-02 | The result view MUST present per-100 g, per-serve and per-pack values together, so serving-size effects are visible. | P0-v0.1 | W | FR-L1-05 |
| FR-PRS-03 | Every field MUST display its confidence classification. | P0-v0.1 | W | FR-CNF-08 |
| FR-PRS-04 | Every advisory finding MUST offer access to its Explanation within one interaction. | P0-v0.1 | W | FR-EXP-05 |
| FR-PRS-05 | The result view MUST list declaration gaps and unreadable fields as explicitly as it lists successful extractions. | P0-v0.1 | W | P1 |
| FR-PRS-06 | The application MUST display a persistent, non-dismissible statement that it does not provide medical advice and does not determine allergen safety. | P0-v0.1 | W, M | R4 |
| FR-PRS-07 | User-facing text MUST avoid moralising language about food or the user's choices. | P0-v0.1 | M | Mission, P9 |
| FR-PRS-08 | The user MAY export a scan result, including findings and Explanations, via an explicit user-initiated action. | P1 | W, U | §8.2 vision |
| FR-PRS-09 | The system MUST NOT display advertising, sponsored content, product recommendations or purchase links. | P0-v0.1 | S, M | §5 |

### 10.3 FR-LOC — Localisation

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-LOC-01 | No user-facing string may be hard-coded; all text MUST resolve through stable message IDs. | P0-v0.1 | S | P10, M10 |
| FR-LOC-02 | The English message catalogue MUST be complete at MVP. | P0-v0.1 | S, M | M10 |
| FR-LOC-03 | The architecture MUST support Hindi output without structural change. | P0-v0.1 | M | M10 |
| FR-LOC-04 | Hindi content MUST NOT ship until reviewed by a competent human reviewer against a nutrition terminology glossary. | P0-v0.1 | M | R11 |
| FR-LOC-05 | Explanations and confidence indicators MUST be localisable on the same basis as all other text. | P0-v0.1 | S | P9 |
| FR-LOC-06 | Missing localisation MUST fall back to English and MUST NOT render an empty string or a raw message ID. | P0-v0.1 | U, W | P1 |

### 10.4 FR-HIS — History

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-HIS-01 | Completed scans MUST be persisted locally on-device. | P0-v0.1 | U | §4.4 |
| FR-HIS-02 | History MUST NOT be transmitted, synchronised or backed up off-device by default. | P0-v0.1 | S, I | P7 |
| FR-HIS-03 | The user MUST be able to delete an individual scan and to clear all history. | P0-v0.1 | W, U | P7 |
| FR-HIS-04 | A stored scan MUST record the rule pack version that produced its findings. | P1 | U | FR-KB-02 |
| FR-HIS-05 | A stored scan viewed after a rule pack change MUST either display its original findings with the original version noted, or offer explicit re-analysis. It MUST NOT silently re-evaluate. | P1 | U, W | P1, P4 |

### 10.5 FR-ERR — Errors and failure handling

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| FR-ERR-01 | Every failure mode MUST produce a specific, actionable message; a generic error MUST NOT be the only outcome available. | P0-v0.1 | U, W | P1 |
| FR-ERR-02 | A partial result MUST be presented as partial, never as complete. | P0-v0.1 | U, W | P1 |
| FR-ERR-03 | The system MUST distinguish "the label does not declare this" from "we could not read this". | P0-v0.1 | U, W | P1 |
| FR-ERR-04 | An unrecoverable failure MUST leave the user with a usable path — retake, import, or manual entry. | P0-v0.1 | W | P1 |
| FR-ERR-05 | The system MUST NOT transmit crash or diagnostic data off-device. | P0-v0.1 | S, I | P7 |
| FR-ERR-06 | Rule pack integrity failure MUST be reported explicitly and MUST NOT cause a silent fallback to unvalidated data. | P0-v0.1 | U | FR-KB-03 |

---

## 11. Non-Functional Requirements

### 11.1 NFR-OFF — Offline operation

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-OFF-01 | The application MUST be fully functional from first launch with the network permanently disabled. | P0-v0.1 | I, M | P6 |
| NFR-OFF-02 | The application MUST NOT declare or require the `INTERNET` permission in the MVP. | P0-v0.1 | S | P6, P7 |
| NFR-OFF-03 | No feature may degrade, warn or behave differently based on network availability. | P0-v0.1 | I | P6 |
| NFR-OFF-04 | All assets required for a complete scan MUST ship in the application package. | P0-v0.1 | S | P6 |

> **⚠ Architect's Note — NFR-OFF-02 is a stronger commitment than it looks, and it is worth making deliberately.**
>
> Omitting the `INTERNET` permission entirely makes offline operation a property the operating system enforces, not one we merely claim. It converts P6 and P7 from promises into verifiable facts a sceptical user can check in the app listing.
>
> The cost is that FR-KB-10 (optional rule pack refresh) cannot be enabled without adding the permission in a later version — which will be visible to users as a permission change and will require honest explanation. **I consider that a price worth paying**, but it is a real trade and should be approved consciously rather than inherited by accident.

### 11.2 NFR-PRV — Privacy

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-PRV-01 | The application MUST NOT collect, store or transmit personally identifying information. | P0-v0.1 | S, M | P7 |
| NFR-PRV-02 | The application MUST NOT integrate any analytics, telemetry, advertising or attribution SDK. | P0-v0.1 | S, M | P7 |
| NFR-PRV-03 | Captured images MUST remain on-device and MUST NOT be transmitted by any code path. | P0-v0.1 | S, I | P7 |
| NFR-PRV-04 | No user account, login, or identifier of any kind may be required or offered. | P0-v0.1 | M | §5 |
| NFR-PRV-05 | Any data leaving the device MUST be the result of an explicit, user-initiated action whose content the user can review first. | P0-v0.1 | W, M | §8.2 |
| NFR-PRV-06 | The privacy posture MUST be stated plainly in-product and in the README. | P0-v0.1 | M | P1 |

### 11.3 NFR-PRF — Performance

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-PRF-01 | Cold start to interactive MUST be < 2 s on the reference device. | P0-v0.1 | I | E7 |
| NFR-PRF-02 | Capture to displayed result MUST be < 5 s on the reference device. | P0-v0.1 | I | E8 |
| NFR-PRF-03 | Analysis (parse + confidence + Layer 1 + Layer 2) MUST complete in < 500 ms on the reference device, excluding OCR. | P1 | I | E8 |
| NFR-PRF-04 | The application MUST NOT block the UI thread during OCR or analysis. | P0-v0.1 | I, W | §3.1 |
| NFR-PRF-05 | Peak memory during a scan MUST remain within the reference device's budget without triggering a low-memory kill. | P1 | I | R8 |
| NFR-PRF-06 | Captured images MUST be released promptly after processing. | P1 | I | R8 |

### 11.4 NFR-SIZ — Size

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-SIZ-01 | Installed application size MUST be < 40 MB. | P0-v0.1 | S | E9 |
| NFR-SIZ-02 | The rule pack MUST be storage-efficient enough to grow to full market category coverage without breaching NFR-SIZ-01. | P1 | S, M | §10 Stage 1 |
| NFR-SIZ-03 | Only OCR script models actually required MUST be bundled. | P1 | S | E9 |

### 11.5 NFR-CMP — Compatibility

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-CMP-01 | The application MUST support Android 8.0 (API 26) and above. | P0-v0.1 | M | §3.1 |
| NFR-CMP-02 | The application MUST function on a device with 3 GB RAM. | P1 | I | §3.1 |
| NFR-CMP-03 | The application MUST render correctly across small-to-large phone form factors and standard font-scaling settings. | P1 | W, M | §3.1 |
| NFR-CMP-04 | No requirement may preclude a future iOS build; no iOS support is delivered in the MVP. | P1 | M | §5 |

### 11.6 NFR-ACC — Accessibility

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-ACC-01 | Confidence MUST NOT be communicated by colour alone. | P0-v0.1 | W, M | P2, P9 |
| NFR-ACC-02 | The Layer 1 / Layer 2 distinction MUST NOT be communicated by colour alone. | P0-v0.1 | W, M | P5 |
| NFR-ACC-03 | Text and interactive controls MUST meet minimum contrast and touch-target guidance. | P1 | M | §3.1 |
| NFR-ACC-04 | All interactive elements MUST carry screen-reader labels. | P1 | W, M | §10 Stage 2 |
| NFR-ACC-05 | The UI MUST remain usable at large system font scales. | P1 | W, M | §3.1 |

### 11.7 NFR-MNT — Maintainability

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-MNT-01 | The domain core MUST have zero dependency on Flutter, platform channels, or I/O. | P0-v0.1 | S | §7.2, E1 |
| NFR-MNT-02 | Every third-party dependency MUST carry a written justification recording purpose, alternatives, maintenance signals and exit path. | P0-v0.1 | M | §7.4 |
| NFR-MNT-03 | Every external capability (camera, OCR, storage) MUST sit behind an adapter interface owned by the domain. | P0-v0.1 | S | §7.2, R10 |
| NFR-MNT-04 | Public domain APIs MUST carry documentation comments explaining intent, not restating signatures. | P1 | M | §7.5 |
| NFR-MNT-05 | A new contributor MUST be able to add an additive record and a threshold rule using documentation alone. | P0-v0.1 | M | E11 |
| NFR-MNT-06 | No magic numbers: every threshold, denominator and tolerance MUST originate in the rule pack. | P0-v0.1 | S, M | P10 |

### 11.8 NFR-TST — Testability

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-TST-01 | Domain core line coverage MUST be ≥ 90%. | P0-v0.1 | S | E2 |
| NFR-TST-02 | All domain logic MUST be testable without a device or emulator. | P0-v0.1 | S | §7.2 |
| NFR-TST-03 | The golden corpus MUST contain ≥ 50 labels, ≥ 10 per priority category. | P0-v0.1 | M | M12, FR-CAT-07 |
| NFR-TST-04 | The golden corpus MUST include adversarial cases: metallised film, curved surfaces, low light, poor print, two-column panels, multi-component packs. | P0-v0.1 | M | §7.3 |
| NFR-TST-05 | Every P0 requirement MUST have at least one test that fails if the requirement is violated. | P0-v0.1 | M | §0.3 |
| NFR-TST-06 | Determinism MUST be verified by property tests, not only by example tests. | P0-v0.1 | P | E3, P4 |
| NFR-TST-07 | Rule pack validation MUST run in CI and MUST fail the build on any schema, citation or reference error. | P0-v0.1 | S | E6, FR-KB-03 |

### 11.9 NFR-SEC — Security & integrity

| ID | Requirement | Pri | Verify | Traces |
|---|---|---|---|---|
| NFR-SEC-01 | The application MUST request only permissions it actually uses. | P0-v0.1 | S, M | P7 |
| NFR-SEC-02 | Rule pack integrity MUST be verifiable before use. | P1 | U | FR-KB-09 |
| NFR-SEC-03 | Locally stored data MUST be confined to app-private storage. | P0-v0.1 | S | P7 |
| NFR-SEC-04 | Release builds MUST be reproducible from a tagged source revision with documented steps. | P1 | M | §4.5 |

---

## 12. Constraints

### 12.1 Fixed project constraints

| ID | Constraint | Source |
|---|---|---|
| CON-01 | Flutter, Android-first | Project brief |
| CON-02 | ₹0 recurring cost; no servers, paid APIs or subscriptions | Project brief, R12 |
| CON-03 | No cloud AI or LLM inference in the product | P4, P6 |
| CON-04 | No backend, authentication or barcode database | §5 |
| CON-05 | Solo developer | Project brief, R6 |
| CON-06 | Offline-first; network optional and absent in the MVP | P6, NFR-OFF-02 |
| CON-07 | One-time costs (Play Console registration, test hardware) are accepted and out of CON-02's scope | R12 |

### 12.2 Reference device — **Motorola Moto G34 5G (4 GB variant)**

All performance requirements (NFR-PRF-01 … 06) and size requirements are measured against this device and no other. A measurement taken on any other handset is not evidence of compliance.

| Attribute | Value | Architectural consequence |
|---|---|---|
| SoC | Qualcomm Snapdragon 695 (SM6375) | Mid-tier; ML Kit runs on Hexagon DSP, not a high-end NPU. Budget OCR at seconds, not milliseconds. |
| RAM | 4 GB LPDDR4x | Realistically ~1.5 GB available to the app. Hard constraint on image handling. |
| Display | 6.5″ LCD, **HD+ 720 × 1600**, 120 Hz | Low pixel density. Confidence and Layer 1/2 distinctions must be legible at 720p. |
| Rear camera | 50 MP main + 2 MP macro | A full-resolution decode is ~200 MB uncompressed — **must never be held in memory**. |
| OS | Android 14 | Above the API 26 floor (NFR-CMP-01); scoped storage applies. |
| Storage | 128 GB UFS 2.2 | Asset read speed is adequate; not a bottleneck for rule pack loading. |

**Derived engineering budgets** (to be validated in Phase 2, not assumed):

| Budget | Value | Rationale |
|---|---|---|
| OCR input long edge | ≤ 1600 px | Above this, OCR cost rises with no accuracy gain on printed panels |
| Peak app memory | ≤ 400 MB | Leaves headroom below Android 14's low-memory kill threshold on a 4 GB device |
| Rule pack eager-load | ≤ 300 ms | Must fit inside the 2 s cold start (NFR-PRF-01) alongside framework init |

> **⚠ Architect's Note — the 720p display is the specification most likely to be overlooked, and it interacts directly with two P0 requirements.**
>
> FR-CNF-08 requires confidence to be distinguishable at a glance, and NFR-ACC-01 forbids conveying it by colour alone. On a 1440p development display, a subtle icon-plus-colour treatment will look elegant. On a 6.5″ HD+ LCD in Indian supermarket lighting, the same treatment may be unreadable.
>
> **Design the confidence and Layer 1/Layer 2 visual language on the reference device from the first sketch, not as a late verification step.** This is a case where the hardware constraint should lead the design rather than audit it.

---

### 12.3 Licence and disclaimer

| ID | Constraint |
|---|---|
| CON-08 | **Source code** is released under the **Apache License 2.0**. All source files carry the standard header; `LICENSE` and `NOTICE` are present at the repository root. |
| CON-10 | **Rule pack / knowledge base content** (`rulepack/`) is released under **CC BY 4.0**, stated separately from the code licence. The directory boundary is the licence boundary. See ADR-0017. |
| CON-11 | Every third-party dependency's licence MUST be Apache-2.0 compatible. **GPL-family dependencies are rejected at selection time**, not discovered at release. |
| CON-09 | The disclaimer text in §12.4 is fixed. It MUST appear verbatim in-product (FR-PRS-06) and in the README. Changes require a documented revision. |

**Apache 2.0 consequences to observe:**

- Every third-party dependency's licence MUST be compatible and recorded (NFR-MNT-02, CON-11).
- **The knowledge base carries CC BY 4.0, separate from the code (CON-10).** A software licence fits a dataset badly, and the Stage 4 goal is publishing the rule pack as a standalone citable dataset. CC BY 4.0 makes it reusable with attribution, which is exactly the intent.
- One consequence to observe: the `rulepack/` boundary is now a *licensing* boundary as well as an architectural one. A rule smuggled into Dart is a licence inconsistency in addition to a violation of P10.
- Apache 2.0's patent grant and explicit "AS IS" warranty disclaimer are useful here: they reinforce, in legally operative terms, the no-warranty posture that §12.4 states in plain language.

### 12.4 Approved disclaimer text

> LabelWise India provides educational and informational guidance based on information declared on product labels and publicly available nutrition guidance. It does not provide medical advice, diagnose health conditions, or determine allergen safety. Always consult a qualified healthcare professional for medical or dietary decisions. If OCR confidence is low or information is missing, verify the product label directly before making decisions.

This text discharges FR-PRS-06 and mitigates R4. Its final sentence creates a direct dependency on the confidence subsystem: the disclaimer instructs the user to act on confidence signals, so **FR-CNF-08 and FR-CNF-10 are now load-bearing for the disclaimer's truthfulness.** If confidence is not visible and legible, the disclaimer asks the user to do something the product does not let them do.

---

## 13. MVP Acceptance Gate

The v0.1 release is complete when **all P0-v0.1 requirements** are satisfied and verified, and the following hold:

| # | Gate condition |
|---|---|
| 1 | All P0-v0.1 requirements pass their stated verification method |
| 2 | Golden corpus ≥ 50 labels, ≥ 10 per priority category (NFR-TST-03) |
| 3 | Parser accuracy ≥ 85% on critical fields, published overall and per category (FR-PAR-15) |
| 4 | HIGH-confidence fields correct ≥ 98% on the corpus (FR-CNF-11) |
| 5 | Every advisory finding carries a complete, resolvable Explanation (FR-EXP-01, FR-EXP-04) |
| 6 | Fifth-category dry run passes as a data-only change (FR-CAT-06) |
| 7 | Domain core coverage ≥ 90% (NFR-TST-01) |
| 8 | Rule pack passes build-time validation with zero dangling citations (NFR-TST-07) |
| 9 | Zero network egress verified on an instrumented run (NFR-OFF-01, NFR-PRV-03) |
| 10 | Cold start < 2 s and scan < 5 s on the nominated reference device (NFR-PRF-01/02) |
| 11 | All Phase-1 documents current and linked from the README |
| 12 | Licence and medical-disclaimer posture decided and published |

**If a gate condition fails, the release scope shrinks — the gate does not move.** A category below the accuracy bar is withheld and the gap published (`PROJECT_VISION.md` §9.3).

---

## 14. Traceability — Vision to Requirements

Every commitment in `PROJECT_VISION.md` is discharged by at least one requirement. A vision commitment with no requirement is a gap; a requirement with no vision trace is scope creep.

| Vision commitment | Discharged by |
|---|---|
| §4.1 Capture | FR-CAP-01 … 10 |
| §4.2 Extraction | FR-OCR-01 … 08, FR-PAR-01 … 17 |
| §4.2 INS as primary key | FR-PAR-11, FR-KB-06 |
| §4.3 Layer 1 factual | FR-L1-01 … 10 |
| §4.3 Layer 2 advisory | FR-L2-01 … 13 |
| §4.4 Presentation | FR-PRS-01 … 09, FR-LOC-01 … 06 |
| §4.5 Non-functional | NFR-OFF, NFR-PRF, NFR-SIZ, NFR-PRV |
| §5 Out of scope | FR-L2-04, FR-L2-10, FR-L2-11, FR-PRS-09, NFR-PRV-04 |
| P1 Honesty | FR-PAR-05/09/17, FR-ERR-01 … 04, FR-L2-13 |
| P2 Confidence | FR-CNF-01 … 13, FR-PRS-03, NFR-ACC-01 |
| P3 Explainability | FR-EXP-01 … 11, FR-L2-05 |
| P4 Determinism | FR-PAR-01/02, FR-CNF-06, FR-EXP-08, NFR-TST-06 |
| P5 Facts ≠ judgement | FR-L1-01, FR-L2-01/06, FR-PRS-01, NFR-ACC-02 |
| P6 Offline default | NFR-OFF-01 … 04, FR-CAP-06, FR-OCR-01 |
| P7 Data stays on device | NFR-PRV-01 … 06, FR-HIS-02, FR-ERR-05 |
| P8 Citations | FR-KB-04/05, FR-EXP-04 |
| P9 Plain language | FR-PRS-07, FR-EXP-06, FR-LOC-01 … 06 |
| P10 Rules as data | FR-KB-01 … 13, NFR-MNT-06 |
| §7.2 Boundaries | NFR-MNT-01/03, FR-OCR-02 |
| §7.3 Golden corpus | NFR-TST-03/04, FR-PAR-15 |
| §9.3 Category-agnostic | FR-CAT-01 … 08 |
| R4 Medical misinterpretation | FR-PRS-06, FR-L2-06/10/11 |
| R9 Advisory noise | FR-L2-07/08 |
| R13 Devanagari blind spot | FR-OCR-05, FR-OCR-08 |

---

## 15. Explicit Non-Requirements

Recorded so they can be declined by citation rather than re-argued.

| ID | Non-requirement | Rationale |
|---|---|---|
| NR-01 | Barcode scanning or product database lookup | Coverage ≈ 1 in 9 Indian products (§2.2) |
| NR-02 | Cloud AI or LLM interpretation | CON-03; non-deterministic and untestable |
| NR-03 | Composite health score, grade or rating | FR-L2-04; no regulatory anchor exists |
| NR-04 | Allergen safety determination | FR-L2-10; catastrophic failure mode |
| NR-05 | Personalised or condition-specific advice | FR-L2-11; clinical validation required |
| NR-06 | Accounts, login, cloud sync | NFR-PRV-04 |
| NR-07 | Analytics or telemetry of any kind | NFR-PRV-02 |
| NR-08 | Devanagari OCR in the MVP | FR-OCR-08; P2 |
| NR-09 | iOS build | NFR-CMP-04; P1 architectural allowance only |
| NR-10 | Product comparison or recommendation | Out of MVP scope; implies ranking, which implies scoring |
| NR-11 | Cosmetics, medicines, supplements | Stage 3; must remain architecturally reachable |
| NR-12 | Monetisation of any form | FR-PRS-09 |

---

## 16. Open Questions

Must be resolved before or during `ARCHITECTURE.md`. Each names an owner decision, not a research task.

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | Which exact device is the reference device? | NFR-PRF-01 … 06 | ✅ **Resolved** — Moto G34 5G, 4 GB (§12.2) |
| Q2 | Does the chosen OCR engine expose usable per-element confidence? (Spike required — A2) | FR-CNF-02/03 | ⏳ Week 1 of Phase 2 |
| Q3 | What tolerance bands apply to INV-07, INV-08, INV-10? | FR-CNF-04 | ⏳ `DATA_MODEL.md` |
| Q4 | What is the aggregate scan-confidence rule? | FR-CNF-07 | ⏳ `DATA_MODEL.md` |
| Q5 | Which open-source licence? | Gate 12 | ✅ **Resolved** — Apache License 2.0 (§12.3) |
| Q6 | Exact wording of the medical/allergen disclaimer | FR-PRS-06 | ✅ **Resolved** — text fixed (§12.4) |
| Q7 | Which category serves as the "fifth category" verification? | FR-CAT-06 | ⏳ `TEST_STRATEGY.md` |
| Q8 | Does "correct" in FR-PAR-15 mean exact match or match within a tolerance? | FR-PAR-15 | ⏳ `TEST_STRATEGY.md` |
| Q9 | Should the rule pack content carry a separate data licence from the Apache-2.0 code? | §12.3, Stage 4 | ✅ **Resolved** — CC BY 4.0, kept separate (CON-10, ADR-0017) |

> **⚠ Architect's Note — Q8 is not a detail.**
>
> Whether a sodium reading of 412 mg against a true 410 mg counts as correct changes the headline accuracy figure substantially, and it is exactly the kind of definition that gets quietly relaxed under schedule pressure once the number turns out disappointing.
>
> **Recommendation: define it now, in `TEST_STRATEGY.md`, before the first corpus measurement exists.** Deciding a measurement rule while ignorant of the result it will produce is the only way to keep the rule honest. My proposal — exact match for serving size, servings per pack and net quantity; a tight, published tolerance for nutrient values — should be fixed before any accuracy figure is generated, not after.

---

## 17. Approval

| Item | Status |
|---|---|
| Requirements complete against `PROJECT_VISION.md` v1.1 | ✅ §14 traceability shows no gaps |
| Every requirement has a verification method | ✅ §0.3 |
| 181 requirements defined, zero dangling cross-references | ✅ Verified |
| Q1, Q5, Q6 resolved by owner | ✅ §12.2, §12.3, §12.4 |
| Approved | ✅ v1.1 |

**Outstanding:** Q2 is a Phase-2 spike. Q3, Q4, Q7 and Q8 are proposed in `ARCHITECTURE.md`, `DATA_MODEL.md` and `TEST_STRATEGY.md`. Q9 (data licence) needs an owner decision before Phase 1 closes.

*End of document. Approval required before proceeding to `ARCHITECTURE.md`.*
