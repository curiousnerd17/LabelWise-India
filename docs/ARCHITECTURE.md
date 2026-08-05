# LabelWise India — Architecture

| Field | Value |
|---|---|
| **Document** | `docs/ARCHITECTURE.md` |
| **Version** | 1.1 |
| **Status** | **Approved** |
| **Phase** | Phase 1: Architecture & Planning |
| **Author** | Chief Software Architect |
| **Date** | 4 August 2026 |
| **Parents** | `PROJECT_VISION.md` v1.1, `REQUIREMENTS.md` v1.1 |
| **Successor** | `DATA_MODEL.md` |
| **Decision log** | [`docs/adr/`](adr/README.md) — 20 accepted records |

**Changes in v1.1** — §6.1 only. The S4 stage contract was written before ADR-0027 was accepted and described a `(label, value, unit)` triple. FR-PAR-18 requires the parser to extract the qualifier, and S4 is the only stage that still sees the raw text in which `<` or `About` is printed. The contract is therefore a `(label, value, unit, qualifier)` quadruple. Recorded here rather than left implicit, because a stage contract that omits a P0 requirement will be implemented without it.

Every significant decision in this document is now also recorded as an immutable ADR. Where the two differ, the ADR is authoritative on *rationale*; this document is authoritative on *current structure*.

---

## 0. Scope And Conventions

This document defines **structure**: what the parts are, where the boundaries fall, which direction dependencies point, and how data moves. It contains no Dart. Interface contracts are expressed as language-neutral operation tables rather than code signatures, in keeping with the Phase 1 policy that architecture precedes implementation.

That constraint is not merely procedural. Writing a port as a Dart abstract class invites premature commitment to Dart's idioms — nullability, streams, error conventions. Writing it as a contract forces the question *what does this boundary actually guarantee?*, which is the question that matters.

Every boundary in §3 is presented in the same form: **what it separates, why it exists, what it costs, and what happens if it is violated.** A boundary without a stated cost is a boundary nobody has thought about properly.

---

## 1. Architectural Thesis

> **LabelWise India is a pure, deterministic domain engine wrapped in a thin Flutter shell. The camera, the OCR engine, the file system and the user interface are all replaceable peripherals. The parser, the confidence model, the rule engine and the explanation machinery are the product.**

Three consequences follow, and everything in this document is downstream of them.

**The parser lives in the domain, not in infrastructure.** This is the single most consequential placement decision in the project and the one most likely to be got wrong by instinct. Parsing *feels* like plumbing — it deals with messy input and mechanical string handling, which is the texture of infrastructure code. But parsing is where the knowledge lives: what an Indian nutrition panel looks like, that `Energy (kcal)` and `ENERGY, kcal` mean the same thing, that a value in the right-hand column is per-serve, that saturated fat cannot exceed total fat. That is domain knowledge, and domain knowledge belongs in the domain. Put the parser in infrastructure and it becomes untestable without a device, unversionable against the rule pack, and impossible to reason about as a unit — and E2's 90% coverage target becomes unreachable.

**Provenance is the unifying abstraction.** P2 (confidence) and P3 (explainability) look like two features. They are two *views of the same recorded data*: what produced this value, from what inputs, under what rule, with what strength. Build provenance once, as a property that every derived value carries, and confidence and explanation both fall out of it. Build them as separate systems and they will drift apart — which is exactly the failure the P3 decision in `PROJECT_VISION.md` §6 warns against.

**Determinism is an architectural property, not a coding style.** It cannot be achieved by careful implementation alone; it must be structurally enforced. That means no clock, no locale, no randomness, no I/O and no ambient state anywhere in the domain — enforced by the dependency rule (§2.2), not by reviewer vigilance.

---

## 2. The Layering Model

### 2.1 Layers

```
┌──────────────────────────────────────────────────────────────┐
│  PRESENTATION            Flutter widgets, view models        │
│                          Knows: Application, Domain          │
├──────────────────────────────────────────────────────────────┤
│  INFRASTRUCTURE          ML Kit adapter, camera adapter,     │
│  (Adapters)              asset loader, local store           │
│                          Knows: Ports, Domain                │
├──────────────────────────────────────────────────────────────┤
│  PORTS                   Contracts the outside must satisfy  │
│                          Knows: Domain                       │
├──────────────────────────────────────────────────────────────┤
│  APPLICATION             Use cases: PerformScan,             │
│                          CorrectField, LoadRulePack          │
│                          Knows: Domain, Ports                │
├──────────────────────────────────────────────────────────────┤
│  DOMAIN                  Entities, value objects, parser,    │
│  (innermost)             confidence, rule engine, analysis   │
│                          Knows: NOTHING                      │
└──────────────────────────────────────────────────────────────┘

           Dependencies point INWARD only.  Always.
```

### 2.2 The Dependency Rule

**Source code dependencies point inward. An inner layer may not name an outer layer — not in a type, not in an import, not in a comment that implies coupling.**

| Layer | May depend on | May NOT depend on |
|---|---|---|
| Domain | Dart core only | Flutter, ports, adapters, presentation, any package |
| Application | Domain, Ports | Flutter, adapters, presentation |
| Ports | Domain | Application, adapters, presentation |
| Infrastructure | Ports, Domain | Application, presentation |
| Presentation | Application, Domain | Infrastructure directly |

Two rules deserve emphasis because they are the ones that erode first:

**The domain depends on *nothing* — not even a JSON package.** The rule pack enters the domain as already-parsed domain types, never as maps or dynamic data. Deserialisation happens in infrastructure. The moment the domain knows what JSON is, the rule pack format has leaked into the business logic and FR-KB-01's separation becomes cosmetic.

**Presentation never touches infrastructure directly.** It talks to application use cases. When a widget calls an OCR adapter to "just get some text quickly", the boundary is gone and it does not come back.

### 2.3 Enforcement

Discipline does not survive a deadline. The rule is enforced mechanically:

| Mechanism | Enforces | Failure mode |
|---|---|---|
| Package-level import lints | Layer violations | CI build fails |
| Domain package has zero declared dependencies | Domain purity (NFR-MNT-01, E1) | Dependency resolution fails |
| Domain tests run with no Flutter test binding | Domain testability (NFR-TST-02) | Test suite fails |
| Static scan for `DateTime.now`, `Random`, `Platform`, `Locale` in domain | Determinism (P4) | CI build fails |

> **⚠ Architect's Note — the enforcement table is the most important part of this section, and it is the part most likely to be deferred.**
>
> Every project of this kind begins with clean layering and ends with a domain that imports Flutter for one convenient type. The difference between architectures that hold and architectures that decay is almost never the quality of the initial design; it is whether violation is *impossible* or merely *discouraged*.
>
> **Recommendation: build the enforcement before the code it constrains.** A CI check that fails on a layer violation costs perhaps two hours in Phase 2 and is worth more than every architectural intention in this document.

### 2.4 Rationale and trade-offs

**Why this layering.**

The domain must be testable at speed and without a device. That is not an aesthetic preference — it is arithmetic. The golden corpus is 50 labels (NFR-TST-03), and the parser will go through many dozens of iterations against it. If each run requires an emulator or a handset, the feedback loop is minutes and the parser does not get to 85% accuracy (FR-PAR-15) within any realistic schedule. Pure-Dart domain tests run the entire corpus in seconds. **The layering exists primarily to buy iteration speed on the corpus**, and only secondarily for elegance.

The second reason is R10: the OCR engine is the dependency most likely to be abandoned, break, or need replacing. Behind a port, that is an adapter rewrite. Woven through the parser, it is a project rewrite.

**What it costs — stated honestly.**

| Cost | Assessment |
|---|---|
| More packages, more files, more indirection | Real. A solo developer feels this daily. |
| Mapping between layer representations | Real, and the most tedious part of the work. |
| Harder for a newcomer to trace one value end to end | Real, and partly mitigated by §10's data flow narrative. |
| Temptation to add a "shortcut" module that spans layers | The characteristic failure. Enforcement in §2.3 exists for this. |

**The honest trade:** we accept meaningfully more structural overhead than a 30-day MVP would normally justify, in exchange for corpus iteration speed, OCR replaceability, and the ability to reach Stage 3 (cosmetics, medicines) without a rewrite. If this project were a disposable prototype, this layering would be over-engineering. It is not one, and the vision explicitly says so.

**Rejected alternative — a simpler three-layer split** (UI / logic / data). Cheaper to build and entirely adequate for a typical CRUD app. Rejected because it provides no natural home for ports, which means the OCR engine's types leak into logic, which forfeits both R10 mitigation and device-free testing. The saving is a few days; the cost is the project's central quality property.

---

## 3. Architectural Boundaries

Each boundary is specified as: **separates / why / cost / violation symptom.**

### B1 — Domain ↔ Flutter

| | |
|---|---|
| **Separates** | All business logic from the UI framework |
| **Why** | Device-free testing (NFR-TST-02); 90% coverage feasibility (E2); framework replaceability; determinism (Flutter carries locale and platform ambient state) |
| **Cost** | View models must translate domain types into display types. Duplicated-looking structures that are not actually duplicates. |
| **Violation symptom** | A domain type with a `Color`, an `IconData`, or a localised string in it |

The subtle trap here is *localised text*. It is tempting to have the rule engine emit "High in sodium" directly. That couples the domain to a language and defeats FR-LOC-01. **The domain emits message IDs and structured values; only presentation resolves them to text.** This is also what makes Hindi (FR-LOC-03) a content problem rather than an engineering one, exactly as R11 requires.

### B2 — Domain ↔ OCR engine

| | |
|---|---|
| **Separates** | Text recognition from everything that consumes text |
| **Why** | R10 (dependency abandonment); FR-OCR-02; enables corpus tests to inject recorded OCR output instead of running OCR |
| **Cost** | A neutral recognition model must be defined and mapped from the engine's own model, including geometry |
| **Violation symptom** | An ML Kit type name appearing anywhere outside the adapter package |

The second reason listed is the one that pays for itself fastest. Because the parser consumes a neutral recognition model, **the golden corpus can store recorded OCR output alongside each image**. Parser tests then run without OCR at all — deterministic, fast, and isolating parser regressions from OCR-version drift. Without this boundary, every corpus run is also an OCR benchmark and the two failure sources are inseparable.

### B3 — Domain ↔ Image acquisition

| | |
|---|---|
| **Separates** | Camera, gallery and image bytes from the pipeline |
| **Why** | Permissions, lifecycle and platform behaviour are infrastructure concerns; the domain must never hold a bitmap |
| **Cost** | Downscaling and orientation handling must live in the adapter, and their parameters become a tuning surface outside the domain |
| **Violation symptom** | The domain referencing image dimensions, EXIF, or byte buffers |

This boundary carries a hard constraint from the reference device: a 50 MP decode is roughly 200 MB uncompressed against ~1.5 GB of available RAM. **The adapter must decode at a bounded sample size and must never materialise a full-resolution bitmap** (§12).

### B4 — Domain ↔ Persistence

| | |
|---|---|
| **Separates** | Scan history storage from the domain |
| **Why** | Storage engine replaceability; FR-HIS-02 (nothing leaves the device); keeps the domain free of serialisation concerns |
| **Cost** | Domain entities need a persistence representation and a mapping, maintained in step |
| **Violation symptom** | Serialisation annotations or table/column names on domain types |

FR-HIS-05 makes this boundary carry real semantics rather than being a thin CRUD seam: a stored scan records its rule pack version and **must not be silently re-evaluated** under a newer pack. The repository therefore returns stored findings *as stored*, and re-analysis is an explicit, separate use case. A repository that helpfully re-runs analysis on read would violate P1 by changing history without saying so.

### B5 — Domain ↔ Rule pack

| | |
|---|---|
| **Separates** | Rule *content* from rule *evaluation* |
| **Why** | P10; contributor access without Dart (FR-KB-12, E11); refreshability (FR-KB-09); Stage 3 extension |
| **Cost** | Rules cannot use arbitrary logic — they are limited to what the declarative schema expresses. This constrains what a rule can say. |
| **Violation symptom** | A threshold, denominator or tolerance appearing as a literal in Dart (NFR-MNT-06) |

> **⚠ Architect's Note — this boundary has a real and underappreciated cost, and it should be accepted with open eyes.**
>
> Rules-as-data means the rule language is a language, and it will be less expressive than Dart. Some future rule — a conditional threshold, a category-dependent interaction, a two-nutrient combination — will not fit the schema, and the pressure will be to "just special-case this one in code."
>
> That single exception is how rules-as-data dies. **Recommendation: when the schema cannot express a needed rule, extend the schema — never bypass it.** The schema is a domain artefact and evolving it is normal work; smuggling logic into Dart is not. Expect to extend it two or three times during Phase 2 and budget for that rather than treating each occasion as a failure.

### B6 — Layer 1 ↔ Layer 2

| | |
|---|---|
| **Separates** | Facts and gazetted arithmetic from advisory judgement |
| **Why** | P5; regulatory defensibility (§4.3 vision); R4 mitigation; FR-L2-01 requires Layer 1 to function with Layer 2 disabled |
| **Cost** | Two finding types, two evaluation paths, two presentation treatments |
| **Violation symptom** | Layer 1 emitting a comparative or evaluative word; Layer 2 recomputing a normalisation that is Layer 1's job |

This is the only boundary in the document that exists for **non-engineering** reasons as much as engineering ones. It is what allows the product to state a fact with confidence and an opinion with humility, in a regulatory environment where no Indian nutrient-profile model has been finalised. It is also structurally verifiable: Layer 1 must compile, run and pass its tests in a build where Layer 2 is absent. That test is the boundary's proof.

### B7 — Analysis ↔ Presentation

| | |
|---|---|
| **Separates** | Findings from their rendering |
| **Why** | Findings must be exportable (FR-EXP-10), testable, and localisable independently of layout |
| **Cost** | Rendering decisions (ordering, grouping, emphasis) need explicit inputs rather than reading domain internals |
| **Violation symptom** | A widget computing a threshold comparison or deciding severity |

Severity ranking (FR-L2-08) is a domain concern, not a UI concern — it derives from the margin recorded in the Explanation. The UI displays the order it is given. A widget that sorts findings by its own heuristic has quietly become a second, untested rule engine.

### B8 — Message catalogue

| | |
|---|---|
| **Separates** | Message identity from message text |
| **Why** | FR-LOC-01; Hindi gated on review (FR-LOC-04) without blocking engineering; explanations localisable (FR-LOC-05) |
| **Cost** | Indirection when reading code — a message ID tells you less at a glance than a literal string |
| **Violation symptom** | Any user-visible literal outside the catalogue |

---

## 4. Module Structure

A layered package structure, chosen so that the dependency rule is enforced by package manifests rather than by convention.

```
labelwise/
├─ packages/
│  ├─ lw_domain/            PURE DART · zero dependencies
│  │   ├─ label/            Nutrition record, ingredient, additive, units, basis
│  │   ├─ provenance/       Provenance, ParseStrength, Substitution
│  │   ├─ confidence/       Confidence lattice, invariants, assignment
│  │   ├─ parser/           The staged pipeline (§6)
│  │   ├─ rules/            Rule types, evaluator, selectors
│  │   ├─ analysis/         Layer 1 factual · Layer 2 advisory
│  │   ├─ explanation/      Explanation, Derivation, citations
│  │   └─ result/           Result / failure types
│  │
│  ├─ lw_ports/             Contracts · depends on lw_domain only
│  ├─ lw_application/       Use cases · depends on domain + ports
│  ├─ lw_infrastructure/    Adapters · depends on ports + domain
│  └─ lw_rulepack/          Rule pack schema, validator, build tooling
│
├─ app/                     Flutter application · presentation only
├─ rulepack/                Rule pack SOURCE DATA (JSON) — the knowledge base
├─ corpus/                  Golden corpus: images + expected parses + recorded OCR
└─ docs/                    This document set
```

**Why separate packages rather than folders.** Folders rely on discipline; packages rely on the dependency resolver. `lw_domain` declaring zero dependencies makes a Flutter import in the domain a build failure rather than a code review finding. This directly discharges E1 and NFR-MNT-01.

**Why `rulepack/` sits outside `packages/`.** It is content, not code. It has different contributors (nutrition reviewers, not engineers), a different review process, and — pending Q9 — potentially a different licence. Placing it at the repository root makes that separation visible and makes FR-KB-12 socially as well as technically true.

**Why `corpus/` is a first-class top-level directory.** It is a deliverable (M12), not test scaffolding. Burying it under a test folder signals that it is incidental. It is the primary evidence for the project's headline quality claim.

---

## 5. Adapter Interfaces (Ports)

Contracts, not signatures. Every port obeys three universal rules:

1. **No port returns a null or empty value to signal failure.** Every operation returns an explicit success-or-failure result.
2. **No port throws for an expected condition.** Exceptions are reserved for programming errors, never for "no text found" or "permission denied".
3. **No port exposes a third-party type.** Everything crossing the boundary is a domain type.

### P-OCR — Text recognition

| Aspect | Contract |
|---|---|
| Operation | Recognise text in a supplied image reference |
| Input | Image handle, target script hint |
| Output | Recognition result: ordered text elements, each with text, bounding geometry, and optional per-element confidence |
| Failure modes | Engine unavailable · unsupported script · no text found · recognition error |
| Guarantees | Fully on-device (FR-OCR-01) · no mutation of recognised text (FR-OCR-06) · absent confidence reported explicitly, never defaulted (FR-OCR-04) |
| Determinism | Not guaranteed across engine versions — hence corpus tests inject recorded output (B2) |

### P-IMG — Image acquisition

| Aspect | Contract |
|---|---|
| Operations | Capture from camera · select from gallery |
| Output | Image handle plus dimensions; never raw bytes into the domain |
| Failure modes | Permission denied · user cancelled · decode failure · source unavailable |
| Guarantees | Bounded decode resolution (§12) · orientation normalised · original never transmitted (FR-CAP-07) |

### P-PACK — Rule pack access

| Aspect | Contract |
|---|---|
| Operations | Load manifest and thresholds · resolve additive by INS number · resolve message by ID · report pack version |
| Output | Domain types only — never maps, never dynamic data |
| Failure modes | Pack missing · integrity check failed · version unsupported |
| Guarantees | Immutable once loaded · integrity verified before use (FR-ERR-06) · no silent fallback to unvalidated data |

### P-STORE — Scan persistence

| Aspect | Contract |
|---|---|
| Operations | Save scan · list scans · load scan · delete scan · clear all |
| Guarantees | App-private storage only (NFR-SEC-03) · no network path exists (FR-HIS-02) · stored findings returned as stored, never re-evaluated (FR-HIS-05) |

### P-CLOCK — Time

| Aspect | Contract |
|---|---|
| Operation | Current instant |
| Why it exists | So the domain never calls a clock directly (P4). History needs timestamps; determinism forbids ambient time. |
| Guarantees | Injectable and fixed in tests |

> **⚠ Architect's Note — P-CLOCK looks like ceremony and is not.**
>
> A single `DateTime.now()` inside the domain makes every test that touches it non-reproducible, and the failure is intermittent rather than immediate — which is the worst kind. The port costs almost nothing and turns a whole category of flaky test into an impossibility. It also makes the static determinism check in §2.3 enforceable without exceptions, and a rule with exceptions is not a rule.

---

## 6. The Parser Pipeline

The core of the system (`PROJECT_VISION.md` §2.3). Structured as a sequence of **pure stage functions**, each with a distinct input and output type.

### 6.1 Stages

| # | Stage | Input → Output | Responsibility |
|---|---|---|---|
| S0 | *(port boundary)* | Image → `RecognitionResult` | Supplied by P-OCR; not part of the domain |
| S1 | **Normalisation** | `RecognitionResult` → `NormalisedText` | Unicode normalisation, whitespace collapse, catalogued character-confusion handling (`O`↔`0`, `l`↔`1`, `S`↔`5`, `B`↔`8`). Every substitution recorded. |
| S2 | **Layout reconstruction** | `NormalisedText` → `LabelLayout` | Geometry only: cluster elements into lines, lines into columns and table structure. No semantics. |
| S3 | **Region classification** | `LabelLayout` → `ClassifiedRegions` | Identify nutrition panel, ingredient list, other. |
| S4 | **Tokenisation** | `ClassifiedRegions` → `Candidates` | Nutrition: candidate (label, value, unit, qualifier) quadruples with column association. Ingredients: delimiter split respecting parentheses. |
| S5 | **Field resolution** | `Candidates` → `ResolvedFields` | Map candidate labels to canonical nutrients via the synonym table **held in the rule pack**. Assign basis from column headers. |
| S6 | **Unit normalisation** | `ResolvedFields` → `TypedFields` | Canonical units; kJ→kcal with the original retained; every conversion recorded. |
| S7 | **Invariant evaluation** | `TypedFields` → `ValidatedFields` | Evaluate INV-01…10; record pass, fail, or inapplicable. |
| S8 | **Confidence assignment** | `ValidatedFields` → `ParsedLabel` | Combine S1/S2/S3 signals into a classification per field (§7). |

### 6.2 Properties every stage must hold

| Property | Consequence |
|---|---|
| Pure — no I/O, no clock, no locale, no randomness | FR-PAR-01; determinism is structural |
| Total — every input produces an output, including a failure output | FR-PAR-17; no silent empty success |
| Provenance-recording — every produced value records its origin | §7, §8 both depend on this |
| Independently testable | Each stage has its own unit tests |
| Independently snapshot-testable | Layout regressions detectable without running the whole pipeline |
| Forward-only — no stage may consult a later stage | Prevents cyclic reasoning and untestable coupling |

### 6.3 Two design decisions worth defending

**Layout reconstruction (S2) is deliberately semantic-free.** It is tempting to let S2 use knowledge of nutrient names to decide what is a column. Keeping it purely geometric means it can be tested against label images with no nutrition knowledge at all, and — more importantly — it becomes **reusable for cosmetics and medicine labels in Stage 3**, which have entirely different vocabulary but the same physical layout problem. The cost is that S2 sometimes produces a structure S3 must correct.

**The synonym table lives in the rule pack, not in code.** `Energy`, `ENERGY`, `Energy (kcal)`, `Energy Value` and their OCR-mangled variants are *content*, and content accumulates from corpus experience. A contributor who notices an unhandled variant should be able to add it without touching Dart (FR-KB-12). This is the highest-frequency contribution path in the project and the one most worth keeping open.

### 6.4 Re-entry for correction

FR-COR-02 requires correction to re-run analysis. It must **not** re-run OCR.

```
User corrects a field
        │
        ▼
  Re-enter at S7  ──▶  S8  ──▶  Layer 1  ──▶  Layer 2  ──▶  UI
  (invariants)      (confidence)
        │
        └─ corrected field marked USER_SUPPLIED; retains that
           marking through re-analysis (FR-CNF-12, FR-COR-04)
```

This makes the pipeline's stage boundaries load-bearing rather than decorative: S7 must be callable with a field set assembled from mixed extracted and user-supplied values. **Any design where stages are only reachable in sequence from S1 fails this requirement**, which is a good reason to settle it now rather than discover it when the correction UI is built.

---

## 7. Confidence Propagation

### 7.1 Confidence as a lattice

The four levels form a totally ordered bounded lattice:

```
        HIGH          most trustworthy
          │
        MEDIUM
          │
         LOW
          │
        ABSENT        nothing to trust
```

**Propagation is the meet (minimum) operation.** A derived value's confidence is the meet of its inputs' confidences, optionally reduced one further level when the derivation itself is approximate.

The governing property — testable, and the one to write a property test against first:

> **A derived value can never be more confident than its least confident input.**

Meet is associative, commutative and idempotent, so propagation order cannot affect the result. That is what makes FR-CNF-06 (determinism) provable rather than merely intended.

### 7.2 Signals

| Signal | Source | Available? |
|---|---|---|
| **S1** OCR character confidence | P-OCR per-element confidence | **Unverified — Q2** |
| **S2** Parse-rule strength | S5/S6 record `EXACT`, `NORMALISED`, or `HEURISTIC` | Always |
| **S3** Invariant validation | S7 results (INV-01…10) | Whenever the participating fields exist |

Assignment is a deterministic function of the three, defined as data in the rule pack so it is tunable without a code change. FR-CNF-05 is absolute: **a field participating in a failed invariant cannot be HIGH**, whatever S1 and S2 say.

> **⚠ Architect's Note — the architecture must not assume S1 exists.**
>
> Assumption A2 says the OCR engine exposes per-element confidence. That is unverified until the Q2 spike. If it turns out to be absent, or present but poorly calibrated, the confidence model must still work.
>
> The design therefore treats **S3 as primary, S2 as secondary, S1 as a bonus** — the reverse of the intuitive ordering. This is defensible on its merits, not just as a fallback: S3 is engine-independent, deterministic, and detects the failure that actually harms users, which is a misread digit. An OCR engine that is *confidently wrong* about a `3` it read as an `8` will report high character confidence; only the arithmetic catches it.
>
> **Recommendation: implement S2 and S3 first and ship a working confidence model that does not depend on the spike's outcome.** Add S1 as a refinement once Q2 resolves. This removes a first-class principle from the critical path of an unverified assumption.

### 7.3 Propagation through analysis

```
Field (S8)                    HIGH
   │
   ├─▶ Layer 1 derived value  meet(inputs) [− 1 if approximate]
   │      e.g. per-pack sodium = per-100g × netQty
   │
   └─▶ Layer 2 finding        meet(determining inputs)
              │
              └─ if LOW ──▶ finding marked PROVISIONAL (FR-L2-09)
```

FR-CNF-13 is what stops confidence from being decorative: a verdict resting on a LOW-confidence input **inherits** that uncertainty rather than laundering it. The provisional marking is produced by the domain, not chosen by the UI.

### 7.4 User-supplied values

A corrected field carries `USER_SUPPLIED` provenance and **no inferred confidence** (FR-CNF-12). It is neither HIGH nor LOW — it is a different kind of thing, and the model must represent that rather than flattening it onto the scale. In propagation it is treated as maximally trustworthy, because the user has looked at the packet, which is more than the parser can do.

---

## 8. Explainability Propagation

### 8.1 Provenance and Explanation

The relationship, which is the point of §1's second consequence:

| Concept | Attached to | Answers |
|---|---|---|
| **Provenance** | Every extracted or derived *value* | "Where did this number come from?" |
| **Derivation** | Every Layer 1 *finding* | "What arithmetic produced this?" |
| **Explanation** | Every Layer 2 *finding* | "Why does the app say this, and on whose authority?" |

All three read the same underlying recorded data. Explanation is Provenance plus a rule reference plus a citation.

### 8.2 Structural enforcement

FR-EXP-03 requires that a finding without an Explanation be **unrepresentable**. This is an architectural obligation, not a validation step:

- An advisory finding has no public constructor. Only the rule evaluator can create one, and creation requires a complete Explanation.
- The Explanation is produced by the same evaluation that produced the finding (FR-EXP-02) — never reconstructed afterwards, which is how explanation and decision drift apart.
- Dangling `ruleId` or `sourceRef` references fail **build-time** validation (FR-EXP-04), not runtime.

The result: FR-EXP-01 is enforced by the compiler and the build, not by test coverage or reviewer attention. That is the difference between a principle and a hope.

### 8.3 The explanation chain

```
Pixel
  └─ RecognitionElement        (geometry, engine confidence)
       └─ NormalisedText       (substitutions applied, recorded)
            └─ ResolvedField   (synonym matched, rule ID, strength)
                 └─ TypedField (unit conversions recorded)
                      └─ ValidatedField (invariant results)
                           └─ Confidence (S1/S2/S3 inputs)
                                └─ Layer 1 finding (derivation)
                                     └─ Layer 2 finding (Explanation)
                                          └─ Rendered text (message ID)
```

Every link records what it did. The chain is reconstructible end to end, which is what makes FR-EXP-07 (exposing input confidence inside the explanation) a lookup rather than a re-derivation.

### 8.4 Cost, stated plainly

| Cost | Assessment |
|---|---|
| Findings are heavy objects | Real. Memory matters on a 4 GB device — see §12. |
| The evaluator is harder to write | Real. It must thread explanation construction through every path. |
| Serialisation is larger (FR-EXP-10) | Real but acceptable; export is user-initiated and occasional. |
| More to keep in step when a rule changes | Mitigated: rule ID and citation come from the rule pack, so they update with the rule. |

**The trade is accepted** because the alternative — explanations generated separately from decisions — produces a system that can confidently explain a verdict it did not actually reach. For a product whose entire proposition is honesty, that failure mode is disqualifying.

---

## 9. Rule Pack Loading

### 9.1 Format

**Decision: JSON as the authored source of truth.**

| Option | Verdict |
|---|---|
| **JSON** | **Chosen.** Human-readable and diffable (FR-KB-12, E11); no runtime dependency; ships as an asset; reviewable in a pull request by a non-engineer. |
| YAML | Friendlier to author, but needs a parsing dependency and its ambiguities (implicit typing, indentation) create silent-error risk in a file that must be exactly right. |
| SQLite | Better for large additive lookups, but binary — not diffable, not reviewable, hostile to contribution. Fails the boundary's primary purpose. |
| Binary/protobuf | Fastest and smallest, worst for contribution. Premature: no measurement yet says JSON is too slow. |

If cold-start measurement on the Moto G34 later shows JSON parsing threatening the 300 ms budget, the answer is a **build-time compilation step** producing a compact indexed artefact from the same JSON source — not a change of authoring format. Contribution ergonomics and runtime representation are separable, and should be separated only when measurement demands it (`PROJECT_VISION.md` §7.6: do not optimise what has not been profiled).

### 9.2 Loading strategy

| Segment | Strategy | Rationale |
|---|---|---|
| Manifest, version, integrity hash | Eager, at startup | Tiny; needed before anything runs |
| Nutrient synonyms, thresholds, RDA denominators | Eager | Needed by S5 and Layer 1; small |
| Message catalogue (active language) | Eager | Needed to render anything |
| **Additive table (INS records)** | **Lazy — on first ingredient parse** | The largest segment and not needed for a nutrition-only scan. Protects the 2 s cold start (NFR-PRF-01). |
| Message catalogue (other languages) | Lazy | Not needed until the user switches |

### 9.3 Validation

| When | What | On failure |
|---|---|---|
| **Build / CI** | Full schema validation, dangling `ruleId` and `sourceRef` checks, citation completeness, message ID resolution | **Build fails** (FR-KB-03, NFR-TST-07) |
| **App startup** | Integrity hash only | Explicit error; no silent fallback (FR-ERR-06) |

Full validation at runtime is deliberately rejected: it would cost startup time to re-check something CI already proved, on a device with a 2-second budget. **CI is the authority; the runtime check exists only to detect corruption or tampering.**

### 9.4 Versioning and immutability

- Semantic version on the pack; recorded on every finding (FR-KB-02) and every stored scan (FR-HIS-04).
- Immutable once loaded. No mutation path exists.
- FR-KB-09 (out-of-band replacement) is satisfied by the loader accepting a pack from a supplied source; the MVP supplies only the bundled asset. Enabling refresh later is a new source, not a new architecture.

> **⚠ Architect's Note — NFR-OFF-02 constrains this more than it first appears.**
>
> The MVP ships without the `INTERNET` permission, which makes offline operation OS-enforced rather than merely claimed. That is a strong and valuable commitment. It also means FR-KB-10 (optional rule pack refresh) **cannot** be enabled without adding a permission in a later release — visible to users as a permission change, and requiring honest explanation.
>
> The architecture keeps the door open correctly: the loader is source-agnostic, so no redesign is needed. But the *product* decision to add a network permission is a real one and should be made deliberately when Stage 1 arrives, not treated as a routine follow-up.

---

## 10. Data Flow

### 10.1 Successful scan

```
 User taps Capture
      │
      ▼
 [Presentation] ── invokes ──▶ [Application: PerformScan]
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
                [P-IMG]          [P-OCR]          [P-PACK]
              bounded decode   on-device OCR    thresholds,
                                                 synonyms
                    │                │                │
                    └────────────────┴────────────────┘
                                     │
                                     ▼
                        [Domain] Parser S1 → S8
                                     │
                                     ▼
                          ParsedLabel (fields +
                          provenance + confidence)
                                     │
                    ┌────────────────┴────────────────┐
                    ▼                                 ▼
          [Domain] Layer 1                  [Domain] Layer 2
          normalise · %RDA ·                thresholds · flags ·
          serving reconciliation ·          margins · Explanations
          gaps · additives                  (confidence propagated)
                    │                                 │
                    └────────────────┬────────────────┘
                                     ▼
                              ScanResult
                                     │
                    ┌────────────────┴────────────────┐
                    ▼                                 ▼
              [P-STORE] persist              [Presentation] render
                                             facts ≠ advice,
                                             confidence visible,
                                             explanations reachable
```

### 10.2 Failure paths — first-class, not exceptional

Every branch below terminates in a **specific, actionable** outcome (FR-ERR-01). None produces an empty success.

| Failure | Detected at | Outcome |
|---|---|---|
| Camera permission denied | P-IMG | Offer gallery import (FR-CAP-09) |
| Image decode failure | P-IMG | Offer retake |
| No text recognised | P-OCR | Offer retake with framing guidance |
| Non-Latin script dominant | S1/S3 | Explicit unsupported-language result (FR-OCR-05, R13) |
| Nutrition panel not located | S3 | Offer manual entry; ingredients still processed if present |
| Field unresolvable | S5 | Field marked unresolved, distinct from absent (FR-ERR-03) |
| Invariant failed | S7 | Field cannot be HIGH; correction prompted |
| Rule pack integrity failure | P-PACK | Explicit error; no unvalidated fallback (FR-ERR-06) |
| Only ingredients supplied | S3 | Complete ingredient result; nutrition reported as not supplied (FR-PAR-14) |

**The architectural point:** these are not error handling bolted onto a happy path. Each is a value the pipeline returns and the UI renders. P1 (honesty over completeness) is only achievable if partial and failed results are as well-typed and as well-presented as successful ones.

---

## 11. Extension Strategy

What it costs to extend the system along each axis. **A high cost in this table is a design smell worth revisiting.**

| Extension | Changes required | Code change? | Requirement |
|---|---|---|---|
| **New product category** | Rule pack: category record + rule selectors | **No** | FR-CAT-03 |
| **New advisory rule** | Rule pack: rule + threshold + citation + message | **No** | FR-KB-12 |
| **New additive** | Rule pack: INS record + citation | **No** | FR-KB-06 |
| **New label synonym** | Rule pack: synonym table entry | **No** | §6.3 |
| **New language** | Message catalogue + human review | **No** | FR-LOC-03/04 |
| **New OCR engine** | New adapter implementing P-OCR | Adapter only | FR-OCR-02, R10 |
| **New storage engine** | New adapter implementing P-STORE | Adapter only | B4 |
| **iOS** | Platform adapters; domain untouched | Adapter + app only | NFR-CMP-04 |
| **New nutrient** | Domain type + rule pack | **Yes — deliberately** | see below |
| **New product domain** (cosmetics) | New domain module + rule pack; reuse S1–S4 | Partial | Stage 3 |

### Why "new nutrient" deliberately requires code

This is the one row that breaks the data-only pattern, and it is a considered choice rather than an oversight.

Making nutrients fully data-driven would mean a stringly-typed domain: no compile-time guarantee that `saturatedFat` exists, invariants (INV-02, INV-04) resolved by name lookup at runtime, and typos surfacing as runtime failures instead of build failures. The cost of that is paid on every line of the domain, forever.

The set of nutrients FSSAI mandates is **small, stable and legally defined**. It changes on a regulatory timescale of years, not on a contribution timescale of days. Paying a code change on that cadence, in exchange for type safety across the entire domain, is the right trade.

**The general principle:** data-drive the things that change often (rules, thresholds, additives, synonyms, text); type the things that change rarely (nutrients, units, bases, confidence levels). Data-driving everything is not more flexible — it is just untyped.

### Stage 3 (cosmetics, medicines) — reuse boundary

Stages **S1–S4 are domain-independent**: normalisation, layout reconstruction, region classification and tokenisation solve a physical-label problem, not a nutrition problem. Stages S5–S8 and the analysis layers are nutrition-specific.

A cosmetics module therefore reuses roughly the first half of the pipeline and supplies its own second half plus its own rule pack — which is precisely why §6.3 insists that S2 stay semantic-free. That decision looks like fussiness today and is what makes Stage 3 a module rather than a rewrite.

---

## 12. Performance Architecture — Moto G34 5G

Every number here is a **budget to be validated in Phase 2**, not a measurement.

### 12.1 Memory

The binding constraint. 4 GB LPDDR4x with Android 14 leaves roughly 1.5 GB realistically available.

| Rule | Reason |
|---|---|
| **Never decode a full-resolution image** | 50 MP ≈ 200 MB uncompressed. A single careless decode risks a low-memory kill. |
| Decode with a bounded sample size; long edge ≤ 1600 px | Sufficient for printed panels; well above OCR's useful input resolution |
| Release the image immediately after OCR | It is not needed by any later stage |
| Peak app memory ≤ 400 MB | Headroom below the kill threshold |
| Findings carry Explanations — keep them per-scan, not per-history | §8.4's cost lands here |

### 12.2 Latency

| Phase | Budget | Notes |
|---|---|---|
| Cold start to interactive | < 2 s | NFR-PRF-01. Rule pack eager segment ≤ 300 ms. |
| Image capture + decode | < 1 s | Bounded decode is the lever |
| OCR | < 2.5 s | Snapdragon 695 with Hexagon DSP; the dominant cost |
| Parse + confidence + analysis | < 500 ms | NFR-PRF-03; pure computation |
| Render | < 200 ms | |
| **Total capture → result** | **< 5 s** | NFR-PRF-02 |

### 12.3 Concurrency

OCR and parsing run off the UI thread in a background isolate (NFR-PRF-04). This is straightforward for the domain because it is pure: pure functions are trivially safe to move across an isolate boundary, having no shared mutable state to protect.

That is a real, concrete dividend of §2's layering — the kind of benefit that is easy to state abstractly and worth pointing at when it actually arrives.

### 12.4 Display — 720 × 1600

The reference device's HD+ panel is a design constraint, not just a rendering target:

- Confidence must be legible at low pixel density and must not rely on colour alone (FR-CNF-08, NFR-ACC-01).
- The Layer 1 / Layer 2 distinction must survive the same constraint (FR-PRS-01, NFR-ACC-02).
- FR-PRS-02 requires per-100 g, per-serve and per-pack values displayed together — three columns on a 720 px-wide screen is the tightest layout problem in the product and should be prototyped early.

---

## 13. Risks Introduced By This Architecture

Distinct from the product risks in `PROJECT_VISION.md` §11. These are risks the architecture itself creates.

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| AR1 | Layering overhead slows a solo developer enough to threaten the schedule | High | Enforcement automated early (§2.3); no speculative abstraction; boundaries only where §3 justifies one |
| AR2 | Rule schema cannot express a needed rule; logic leaks into Dart | High | B5's note: extend the schema, never bypass it. Budget for two or three extensions in Phase 2. |
| AR3 | S1 (OCR confidence) proves unavailable, weakening the confidence model | Medium | S3-primary design (§7.2); Q2 spike in week 1; model ships without S1 |
| AR4 | Explanation objects inflate memory or storage | Medium | Per-scan retention; history stores findings not full chains; measure on reference device |
| AR5 | Stage boundaries in §6 prove wrong once real labels are parsed | Medium | Stages are internal to the domain and refactorable; only `ParsedLabel` is a published contract |
| AR6 | Package split creates friction that tempts a spanning "shortcut" module | Medium | Dependency resolution makes it a build failure, not a judgement call |
| AR7 | Pure-domain purism pushes genuinely useful logic into adapters where it is untested | Medium | Adapters stay thin: mapping and platform calls only. Any adapter with a branch on business meaning is misplaced logic. |

> **⚠ Architect's Note — AR1 is the one I would bet on, and it deserves a stated escape hatch.**
>
> This architecture is more structure than a 30-day MVP normally warrants. I have argued it earns its cost through corpus iteration speed and Stage 3 reachability, and I stand by that. But the risk is real, and pretending otherwise would be exactly the kind of confident-and-unfalsifiable claim this project exists to avoid.
>
> **If the layering is measurably slowing delivery by mid-Phase 2, the correct concession is to merge `lw_application` into `lw_domain` — not to weaken B1 or B2.** Application-layer separation is the cheapest boundary to lose: the use cases are thin and the domain would remain pure and testable. B1 (Flutter) and B2 (OCR) are load-bearing for testability and R10 and must not be traded away under schedule pressure.
>
> Deciding the order of concessions *now*, while calm, is how you avoid conceding the wrong thing later, in a hurry.

---

## 14. Traceability

| Requirement | Discharged by |
|---|---|
| FR-OCR-02 (adapter) | §3 B2, §5 P-OCR |
| FR-PAR-01/02 (purity, determinism) | §2.2, §2.3, §6.2 |
| FR-PAR-13 (rule strength recorded) | §6.1 S5/S6, §8.1 Provenance |
| FR-CNF-01…06 (confidence) | §7.1, §7.2 |
| FR-CNF-12/13 (user-supplied, propagation) | §7.3, §7.4 |
| FR-EXP-01…04 (explanation) | §8.2 structural enforcement |
| FR-EXP-07 (input confidence in explanation) | §8.3 chain |
| FR-KB-01/03/08/09 (rule pack) | §9.1, §9.3, §9.4 |
| FR-KB-12 (contributor access) | §4 `rulepack/`, §9.1, §11 |
| FR-CAT-01…05 (category-agnostic) | §11 (data-only), §6.3 |
| FR-COR-02 (re-analysis) | §6.4 re-entry |
| FR-ERR-01…06 (failure handling) | §10.2 |
| FR-HIS-05 (no silent re-evaluation) | §3 B4, §5 P-STORE |
| NFR-MNT-01 / E1 (domain purity) | §2.2, §2.3, §4 |
| NFR-MNT-03 (adapters) | §3 B2/B3/B4, §5 |
| NFR-OFF-01…04 (offline) | §5 P-OCR, §9.2 |
| NFR-PRF-01…05 (performance) | §12 |
| NFR-TST-02 (device-free tests) | §2.4, §3 B2 |
| P4 (determinism) | §2.3 static checks, §5 P-CLOCK, §6.2 |
| P5 (facts ≠ judgement) | §3 B6 |
| P10 (rules as data) | §3 B5, §9, §11 |

---

## 15. Open Questions

| # | Question | Blocks | Needed by |
|---|---|---|---|
| Q2 | Does the OCR engine expose usable per-element confidence? | §7.2 signal S1 | **Week 1 of Phase 2** — spike |
| Q10 | Which state management approach for presentation? | §4 `app/` | Before UI work |
| Q11 | Isolate strategy — one per scan, or a pooled worker? | §12.3 | Before performance tuning |
| Q12 | Does the rule pack need build-time compilation, or is JSON fast enough? | §9.1 | After first cold-start measurement |
| Q13 | Does S3 (region classification) need the rule pack, or can it be purely structural? | §6.1, Stage 3 reuse | `DATA_MODEL.md` |

> **⚠ Architect's Note — Q10 is deliberately left open, and that is itself an architectural result.**
>
> In most Flutter projects, state management is an early, contentious, hard-to-reverse decision. Here it is neither early nor hard to reverse: the domain is pure, the use cases are framework-free, and presentation holds no business logic. Whatever is chosen wraps a thin view-model layer over already-computed results.
>
> **Recommendation: choose the smallest thing that supports testable view models, and choose it late.** The fact that this decision is cheap is evidence the boundaries are in the right places — a good architecture makes framework choices reversible, and the reversibility is the proof rather than the by-product.

---

## 16. Approval

| Item | Status |
|---|---|
| Boundaries specified with rationale and trade-offs | ✅ §3, eight boundaries |
| Dependency rules defined and mechanically enforceable | ✅ §2.2, §2.3 |
| Parser pipeline specified with stage contracts | ✅ §6 |
| Confidence propagation formalised | ✅ §7 |
| Explainability propagation formalised | ✅ §8 |
| Rule pack loading, validation, versioning | ✅ §9 |
| Adapter contracts | ✅ §5, five ports |
| Data flow including failure paths | ✅ §10 |
| Extension strategy with honest costs | ✅ §11 |
| Architecture-specific risks | ✅ §13, AR1–AR7 |
| No code written | ✅ Contracts expressed language-neutrally |

*End of document. Approval required before proceeding to `DATA_MODEL.md`.*
