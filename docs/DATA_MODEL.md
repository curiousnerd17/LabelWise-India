# LabelWise India — Data Model

| Field | Value |
|---|---|
| **Document** | `docs/DATA_MODEL.md` |
| **Version** | 1.6 |
| **Status** | **Approved** |
| **Phase** | Phase 1: Architecture & Planning |
| **Author** | Chief Software Architect |
| **Date** | 4 August 2026 |
| **Parents** | `PROJECT_VISION.md` v1.1, `REQUIREMENTS.md` v1.2, `ARCHITECTURE.md` v1.0 |
| **Decision log** | [`docs/adr/`](adr/README.md) |
| **Successor** | `TEST_STRATEGY.md` |
| **Resolves** | Q3 (invariant tolerances), Q4 (aggregate confidence), Q13 (region classification), **Q19 (qualified quantities)** |

**Changes in v1.6.** Two fields of `ParsedLabel`'s transitive shape become optional, found while reviewing Milestone 8. `ParsedLabel` is the parser's published contract (§5.5), yet §5.3 required `ServingInfo.reconciliation` — explicitly a **Layer 1** output — and §5.4 required `Ingredient.identification`, which needs the additive engine `ROADMAP.md` schedules for Phase 4. The first closes a cycle: Layer 1 consumes the object one of its own outputs is required to complete. The second demands a capability that does not exist yet. Both are now optional, each with the reason recorded inline. **Additive only:** no field removed, no type altered, no existing optionality changed. `ARCHITECTURE.md` v1.3 correspondingly retargets S8's output to `ScoredFields`.

**Changes in v1.5.** §4.3 — `InvariantResult` gains an optional `basis`. A gap found while building Milestone 7: an Indian panel declares the same nutrients on two bases, so `saturatedFat ≤ totalFat` is a *distinct* check per-100 g and per-serve. Evaluating both produced two results carrying `INV-02` with nothing to separate them, which would have let a per-serve failure cap a correctly-read per-100 g field under FR-CNF-05, and would have left FR-EXP-09 with a derivation the user could not check against the packet. Additive only: one optional field, no existing field altered or removed.

**Changes in v1.4.** §3.1 — `parseStrength` becomes optional, matching `parseRuleId`. A verified inconsistency found during Milestone 3: a `USER_SUPPLIED` value has no parse rule *and* no parse strength, but only the former was marked optional. Minimum change; no other field altered, no new type, no fourth `ParseStrength` value.

**Changes in v1.3.** Canonical serialised form of the qualifier fixed normatively in the schema (§2.2a, ADR-0027 decision 5), MI-17 added.

**Changes in v1.2 — Q19, qualified quantities (ADR-0027).** `Quantity` gains a `qualifier` and denotes an **interval** rather than a point (§2.2a). Exact-match comparison includes the qualifier (§2.2a). Invariant evaluation treats quantities as bounds and gains a fourth outcome, `INDETERMINATE` (§4.3a). Layer 2 reasons explicitly over bounds with no implicit coercion (§6.3a). Model invariants MI-13…16 added.

---

## 0. Scope And Conventions

This document defines the **shapes** the system moves through: domain types, the rule pack schema, and the persistence format. It contains no Dart. Types are described as structured tables — field, kind, constraint, rationale — because the point of Phase 1 is to settle *what must be true of the data*, and a Dart declaration would smuggle in language conventions before that question is answered.

Notation used throughout:

| Notation | Meaning |
|---|---|
| `A \| B \| C` | A closed union — a value is exactly one of these variants |
| `{ … }` | A record with named fields |
| `[T]` | An ordered sequence of `T` |
| `T?` | Optional. **Used sparingly and always justified** — see §1. |

---

## 1. Modelling Principles

These govern every type below. They are the data-model expression of P1, P2, P3 and P4.

### M1 — Make illegal states unrepresentable

Where a rule says something must always be true, the type system should enforce it rather than a validator checking it later. Concretely:

- An advisory finding cannot exist without an Explanation (FR-EXP-03, ADR-0011).
- An extracted field cannot exist without Provenance and Confidence (FR-CNF-01).
- A quantity cannot exist without a unit and a basis.
- A rule cannot exist without a citation (FR-KB-04).

### M2 — Optionality is a modelling failure until proven otherwise

`T?` collapses several distinct situations into one — "not applicable", "not found", "not declared", "not yet computed" — and the difference between the last two is precisely what FR-ERR-03 requires us to preserve. **Every optional field in this document carries a written justification.** Where a value may be absent for more than one reason, a union is used instead.

### M3 — Every value carries its origin

Provenance is not metadata attached where convenient; it is part of the value (ADR-0009). Confidence and Explanation are both derived from it.

### M4 — Determinism is structural

No type may contain a wall-clock time, a locale, a platform identifier, or a floating-point value whose exact representation affects an output comparison. Timestamps enter only through the clock port at the persistence boundary.

### M5 — Text is identity, not content

The domain holds message **IDs**. It never holds display text in any language (B8, FR-LOC-01).

---

## 2. Quantities And Units

### 2.1 The decimal representation problem

> **⚠ Architect's Note — this is the least glamorous decision in the document and one of the most consequential.**
>
> Nutrition values are decimal: `2.5 g`, `0.3 g`, `412 mg`. The obvious representation is a double. Doubles make `0.1 + 0.2 ≠ 0.3`, make equality comparison unreliable, and make golden-corpus assertions ("expected 2.5, got 2.4999999999999996") a recurring source of noise that engineers learn to suppress — which is exactly how a real regression gets suppressed alongside it.
>
> P4 requires byte-identical output for identical input (FR-PAR-02), and the golden corpus compares parsed structures directly. Both are materially easier with exact arithmetic.
>
> **Decision: quantities are stored as scaled integers.** A `Quantity` holds an integer count of the unit's smallest tracked increment, together with the unit. Rounding happens at exactly one place, under one published policy (§2.4), and is recorded when it occurs. This costs a little arithmetic ceremony and buys exact equality, deterministic comparison, and corpus assertions that mean what they say.

### 2.2 `Quantity`

| Field | Kind | Constraint | Rationale |
|---|---|---|---|
| `scaledValue` | integer | ≥ 0 for all nutrition values (INV-01) | Exact arithmetic; deterministic equality |
| `unit` | `Unit` | required | A bare number is meaningless (FR-PAR-05) |
| `qualifier` | `Qualifier` | required, defaults to `EXACT` | Indian labels declare bounds and approximations; see §2.2a |

A `Quantity` is a value object: immutable, compared by value, with no identity.

**Scale is a property of the `Unit`, not of the `Quantity` (ADR-0021).** v1.0 of this document carried `scale` as a third field on `Quantity`, which was a modelling error: it permitted two quantities with the same unit but different scales — an illegal state that M1 says should be unrepresentable. Scale now derives from the unit definition in §2.3 and cannot vary per value.

The practical consequence is that equality and comparison for same-unit quantities reduce to integer comparison of `scaledValue`, with no scale reconciliation step and therefore no opportunity for scale mismatch to produce a silently wrong comparison.

### 2.2a `Qualifier` — quantities denote intervals

Resolves Q19 (ADR-0027). Indian labels routinely print `< 0.5 g` for trans fat and `About 4 servings` for pack counts. Both are declarations, not omissions, and neither is a point value.

| Qualifier | Meaning | Interval denoted |
|---|---|---|
| `EXACT` | The declared value (default) | `[v, v]` |
| `LESS_THAN` | Declared below a bound | `[0, v)` — lower bound 0 by INV-01 |
| `GREATER_THAN` | Declared above a bound | `(v, ∞)` |
| `APPROXIMATELY` | Manufacturer explicitly declines precision | `[v−δ, v+δ]`, δ per unit from the rule pack |

**The qualifier is part of the value, not metadata beside it.** It travels with the number everywhere the number goes — including rule pack thresholds and persisted scans — because separating them guarantees a call site that compares the number and forgets the qualifier.

`δ` for `APPROXIMATELY` is rule pack data rather than a constant, consistent with P10. This is also why `APPROXIMATELY` widens INV-10's effective tolerance without special-casing: the interval simply is wider.

#### Equality and comparison

**Equality includes the qualifier.** `LESS_THAN 0.5 g` is not equal to `EXACT 0.5 g`. This is binding on the accuracy comparator (§4.2 of `TEST_STRATEGY.md`): a parser that reads `< 0.5` as `0.5` records an **Error**, not a Correct.

Ordering comparisons operate on intervals and produce three outcomes:

| Result | Condition (for `a ≤ b`) |
|---|---|
| Definitely true | `sup(a) ≤ inf(b)` |
| Definitely false | `inf(a) > sup(b)` |
| **Indeterminate** | Otherwise — the intervals overlap in a way the declarations do not settle |

#### Canonical serialised form

**The schema defines the canonical form; implementations do not get to choose** (ADR-0027 decision 5). Two normative rules:

| Direction | Rule |
|---|---|
| **Reading** | An absent `qualifier` MUST be interpreted as `EXACT`. |
| **Writing** | A quantity whose qualifier is `EXACT` MUST omit the field. Emitting `"qualifier": "EXACT"` is **invalid output**, not a stylistic variant. |

JSON Schema's `default` keyword is annotation only and enforces nothing, so the rule is stated normatively in the schema description **and** checked by CI-16, which rejects any serialised `"qualifier": "EXACT"` in `rulepack/` or `corpus/`.

> **⚠ Architect's Note — this is not tidiness, and the reason is worth stating.**
>
> Two consumers that disagree about whether to emit the field produce **byte-different output for identical data**. That breaks three things at once: the rule pack integrity hash (FR-KB-09), FR-PAR-02's byte-identical determinism guarantee, and golden-corpus comparison.
>
> It matters more here than in a typical project because there will be a second consumer. The knowledge base ships under CC BY 4.0 specifically so other tools can read it (Stage 4). A serialisation convention that lives in one implementation's head is not a specification.

#### Interval arithmetic through derivations

Layer 1 derivations scale quantities by positive constants (per-100 g → per-serve → per-pack). **Scaling a bound by a positive constant preserves the bound direction**, so `LESS_THAN 0.5 g` per 100 g becomes `LESS_THAN 1.0 g` for a 200 g pack. Addition of intervals widens them, as expected.

> **⚠ Architect's Note — two conflations to avoid, and they are easy to make.**
>
> **A qualifier must never reduce confidence.** A label printing `< 0.5 g` is being *precise about its imprecision*. Reading that correctly is a `HIGH`-confidence read. Confidence measures how sure we are that we read the label right — not how precise the label chose to be. Wiring the qualifier into confidence assignment would conflate the manufacturer's caution with our uncertainty, and would punish the parser for succeeding.
>
> **`INDETERMINATE` is not `FAILED`.** An unresolvable comparison is not evidence of error. It must not cap confidence the way a failed invariant does (§4.3a). It is recorded distinctly so an explanation can state *why* the check could not be made.

### 2.3 `Unit` — closed set

| Unit | Measures | Scale | Smallest increment |
|---|---|---|---|
| `GRAM` | mass | 100 | 0.01 g |
| `MILLIGRAM` | mass | 10 | 0.1 mg |
| `MICROGRAM` | mass | 1 | 1 µg |
| `MILLILITRE` | volume | 10 | 0.1 ml |
| `KILOCALORIE` | energy | 10 | 0.1 kcal |
| `KILOJOULE` | energy | 10 | 0.1 kJ |
| `PERCENT` | proportion | 10 | 0.1 % |
| `COUNT` | dimensionless | 100 | 0.01 (servings per pack) |

Scale is fixed by the unit and is not overridable. Scales are deliberately one or two orders finer than any label declares. Labels do not print sodium to 0.1 mg; tracking it there means intermediate arithmetic (per-100 g → per-serve → per-pack) does not accumulate rounding error before the single rounding step at presentation.

Unit conversion is closed within a dimension. Cross-dimension conversion is forbidden except energy (`KILOJOULE` → `KILOCALORIE`), which is a defined constant and is always recorded as a conversion in provenance (FR-PAR-07).

### 2.4 Rounding policy

**One policy, one place, always recorded.**

| Rule | Value |
|---|---|
| Mode | Half-away-from-zero |
| Applied at | Presentation, and at the single conversion point for kJ→kcal |
| Never applied at | Any intermediate arithmetic step |
| Recorded | Every rounding is a `Substitution` entry in provenance |

Banker's rounding is rejected: it is less surprising to statisticians and more surprising to everyone else, and this product's audience reads a number off a screen and compares it to a packet.

### 2.5 `Basis` — closed set

| Value | Meaning |
|---|---|
| `PER_100G` | Per 100 grams |
| `PER_100ML` | Per 100 millilitres |
| `PER_SERVE` | Per the manufacturer-declared serving |
| `PER_PACK` | Per the whole declared net quantity |

A quantity without a basis is not interpretable. `Basis` is therefore required wherever a nutrient value appears — never optional, never defaulted.

### 2.6 `Version` — semantic value object

Rule pack and rule versions are modelled as a structured value object, not an opaque string (ADR-0022).

| Field | Kind | Constraint |
|---|---|---|
| `major` | integer | ≥ 0 |
| `minor` | integer | ≥ 0 |
| `patch` | integer | ≥ 0 |

Ordering and compatibility are defined operations on the type rather than ad-hoc string handling at each call site. This matters because `minAppVersion` (§7.2) and FR-HIS-05 (a stored scan viewed under a newer pack) both require **comparison**, and string comparison gets `1.10.0` versus `1.9.0` wrong — a defect that would surface as a rule pack silently refusing to load, or worse, silently loading when it should not.

**Compatibility rule:** a rule pack is loadable when its `major` matches the application's supported major version and its `minor.patch` is greater than or equal to `minAppVersion`. A major mismatch is an explicit, reported refusal (FR-ERR-06), never a best-effort load.

### 2.7 `NutrientId` — closed, typed set

Per ADR-0014 this is a typed enumeration, not rule pack data.

| Group | Members |
|---|---|
| Energy | `ENERGY` |
| Macronutrients | `PROTEIN`, `CARBOHYDRATE`, `TOTAL_SUGARS`, `ADDED_SUGARS`, `DIETARY_FIBRE`, `TOTAL_FAT`, `SATURATED_FAT`, `TRANS_FAT`, `MONOUNSATURATED_FAT`, `POLYUNSATURATED_FAT`, `CHOLESTEROL` |
| Minerals | `SODIUM` |

**Critical fields** (FR-PAR-15, E4) are: `ENERGY`, `PROTEIN`, `CARBOHYDRATE`, `TOTAL_SUGARS`, `ADDED_SUGARS`, `TOTAL_FAT`, `SATURATED_FAT`, `TRANS_FAT`, `SODIUM`, plus the three serving descriptors in §5.3.

> **⚠ Architect's Note — the model must not silently equate sodium and salt.**
>
> FSSAI mandates sodium. Some labels additionally print "salt", and WHO SEARO thresholds are expressed in sodium. Salt ≈ sodium × 2.5 — an approximate conversion, not an exact one.
>
> **Recommendation: model only `SODIUM` in the domain. If a label declares salt, convert at parse time, mark the field `DERIVED`, record the conversion in provenance, and cap its confidence at MEDIUM.** Modelling both as first-class nutrients would create two sources of truth for one quantity and invite a rule that fires twice. The conversion factor lives in the rule pack, not in code.

---

## 3. Provenance

The foundation of both confidence and explainability (ADR-0009).

### 3.1 `Provenance`

| Field | Kind | Notes |
|---|---|---|
| `origin` | `FieldOrigin` | See §3.2 |
| `producedByStage` | `PipelineStage` | S1–S8 (`ARCHITECTURE.md` §6.1) |
| `parseRuleId` | `RuleId?` | *Optional justified:* absent only for `USER_SUPPLIED` values, which no rule produced |
| `parseStrength` | `ParseStrength?` | See §3.3. *Optional justified:* absent only for `USER_SUPPLIED` values. The same reasoning already accepted for `parseRuleId` applies — a value no rule produced has no strength at which a rule matched. Fabricating one would feed signal S2 (ADR-0010) from a match that never occurred. |
| `substitutions` | `[Substitution]` | Possibly empty; never absent |
| `sourceRegion` | `RegionRef?` | *Optional justified:* absent for derived and user-supplied values, which have no position on the label |
| `rulePackVersion` | `Version` | FR-KB-02 |

### 3.2 `FieldOrigin` — closed set

| Value | Meaning | Confidence treatment |
|---|---|---|
| `EXTRACTED` | Read from the label by the parser | Computed from S1/S2/S3 |
| `DERIVED` | Computed from other fields | Meet of inputs, possibly downgraded |
| `USER_SUPPLIED` | Entered or corrected by the user | **No inferred confidence** (FR-CNF-12) |

### 3.3 `ParseStrength` — closed set (signal S2)

| Value | Meaning |
|---|---|
| `EXACT` | Canonical label text matched verbatim |
| `NORMALISED` | Matched after documented normalisation (case, spacing, known synonym) |
| `HEURISTIC` | Matched by positional or fuzzy inference |

### 3.4 `Substitution`

Every transformation applied to raw text, recorded so the chain from pixel to value is reconstructible (FR-EXP-07, `ARCHITECTURE.md` §8.3).

| Field | Kind |
|---|---|
| `kind` | `CHARACTER_CONFUSION \| UNIT_NORMALISATION \| ENERGY_CONVERSION \| SALT_TO_SODIUM \| ROUNDING \| WHITESPACE` |
| `before` | text |
| `after` | text |
| `appliedByRuleId` | `RuleId` |

---

## 4. Confidence

### 4.1 `Confidence` — the lattice

Totally ordered: `ABSENT < LOW < MEDIUM < HIGH`. Propagation is the **meet** (minimum) operation (ADR-0010).

Properties that must hold, and are property-tested:

| Property | Statement |
|---|---|
| Monotonic | `meet(a, b) ≤ a` and `meet(a, b) ≤ b` |
| Commutative | `meet(a, b) = meet(b, a)` |
| Associative | `meet(meet(a,b),c) = meet(a,meet(b,c))` |
| Idempotent | `meet(a, a) = a` |

Associativity and commutativity are what make propagation order irrelevant, which is what makes FR-CNF-06 provable rather than merely intended.

`USER_SUPPLIED` sits outside the lattice: it is not a level but a different kind of thing. In propagation it behaves as maximally trustworthy, because the user has looked at the packet — which the parser cannot do.

### 4.2 `ConfidenceSignals`

| Field | Kind | Notes |
|---|---|---|
| `s1OcrConfidence` | `OcrConfidence?` | *Optional justified:* the engine may not expose it. Absence is recorded explicitly, never defaulted (FR-OCR-04, FR-CNF-03). |
| `s2ParseStrength` | `ParseStrength` | Always present |
| `s3InvariantResults` | `[InvariantResult]` | Possibly empty when no invariant applies |

Per ADR-0010, assignment weights S3 first, S2 second, S1 as refinement. The assignment table itself lives in the rule pack (§7.8) so it is tunable without a code change.

### 4.3 `InvariantResult`

| Field | Kind |
|---|---|
| `invariantId` | `INV-01 … INV-10` |
| `outcome` | `PASSED \| FAILED \| INDETERMINATE \| INAPPLICABLE` |
| `participatingFields` | `[NutrientId \| ServingField]` |
| `basis` | `Basis?` — *optional justified:* null for invariants that are not basis-scoped (INV-09, INV-10 concern serving arithmetic, which no basis qualifies) |
| `observedDeviation` | `Quantity?` — *optional justified:* meaningless for `INAPPLICABLE` |
| `toleranceApplied` | `Tolerance?` — *optional justified:* same |

A panel declaring both per-100 g and per-serve columns produces **one result per invariant per basis**. `basis` is what separates them, and what lets FR-CNF-05 cap only the fields that actually participated in the failure.

`INAPPLICABLE` is a first-class outcome, not a silent skip: "we could not check this" is different from "this checked out", and FR-CNF-04 requires the distinction.

**FR-CNF-05 is absolute:** a field participating in a `FAILED` invariant cannot be `HIGH`, whatever S1 and S2 say.

### 4.3a Invariants over qualified quantities

Per ADR-0027, invariants compare **intervals**, not points. INV-02 (`saturatedFat ≤ totalFat`) evaluated against `saturatedFat = LESS_THAN 0.5 g` and `totalFat = EXACT 0.4 g` cannot be settled: the intervals overlap.

| Outcome | Condition | Confidence effect |
|---|---|---|
| `PASSED` | The comparison is definitely true | Supports `HIGH` |
| `FAILED` | The comparison is definitely false | **Caps below `HIGH`** (FR-CNF-05) |
| `INDETERMINATE` | Intervals overlap; the declarations do not settle it | **No signal.** Neither supports nor caps. |
| `INAPPLICABLE` | Participating fields absent, or excluded for this category | No signal |

`INDETERMINATE` and `INAPPLICABLE` behave identically for confidence and are nonetheless recorded separately, because they answer different questions: *"the label declared a bound, so this check cannot conclude"* versus *"there was nothing to check."* Only the first is worth telling the user about.

**A tolerance band is applied to the interval, not in place of it.** Tolerance widens the comparison to absorb the manufacturer's rounding (§4.4); the qualifier describes what the manufacturer declared. They compose; neither substitutes for the other.

### 4.4 Q3 resolved — tolerance bands

Invariants compare declared values that manufacturers have independently rounded. Tolerances must absorb legitimate rounding without absorbing genuine misreads.

**Provisional bands**, to be calibrated against the corpus before the MVP gate:

| Invariant | Check | Provisional tolerance |
|---|---|---|
| INV-01 | values ≥ 0 | Exact — no tolerance |
| INV-02 | saturated ≤ total fat | +0.1 g grace for rounding |
| INV-03 | trans ≤ total fat | +0.1 g grace |
| INV-04 | added ≤ total sugars | +0.1 g grace |
| INV-05 | total sugars ≤ carbohydrate | +0.5 g grace |
| INV-06 | protein + carb + fat ≤ 100 g/100 g | +2 g grace |
| INV-07 | energy vs Atwater estimate | **±15%, floor ±20 kcal** |
| INV-08 | per-serve vs per-100 g × serve/100 | **±5%, floor = one unit of the last declared decimal place** |
| INV-09 | serve size ≤ net quantity | Exact |
| INV-10 | servings/pack vs netQty ÷ serveSize | **±10%, floor ±0.5 servings** |

> **⚠ Architect's Note — these numbers are a starting point, not an answer, and the document should not pretend otherwise.**
>
> INV-07 is the loosest and the most fragile. The Atwater estimate (4/4/9 kcal per g) is disturbed by dietary fibre (~2 kcal/g), polyols, and — critically — by whether a given label's declared carbohydrate includes fibre. Indian labelling practice varies on this. A ±15% band is a guess dressed as a specification.
>
> **The corpus is the calibration instrument.** With 50 labels carrying hand-verified true values, the actual distribution of |declared − estimated| is measurable. The band should be set to capture correctly-read labels while still flagging misreads — which is an empirical question with a real answer, not a judgement call.
>
> **Requirement: calibrate INV-07, INV-08 and INV-10 against the corpus before the MVP gate, and record the resulting bands and their basis in the rule pack.** The failure mode in both directions is severe. Too loose and INV-07 never fires, silently removing the primary confidence signal for energy. Too tight and every label reports LOW, making confidence noise. Neither failure announces itself — which is why this needs measuring rather than deciding.

### 4.5 Q4 resolved — aggregate scan confidence

FR-CNF-07 requires a scan-level classification. The naive approach — meet across all fields — is wrong: one LOW field among twelve would render the whole scan LOW, which is both uninformative and demoralising.

`ScanConfidence` is a **separate type** from field `Confidence`, deliberately, so the two cannot be confused or accidentally substituted:

| Level | Condition |
|---|---|
| `HIGH` | Every critical field resolved; ≥ 80% of resolved critical fields `HIGH`; zero `FAILED` invariants |
| `MEDIUM` | Every critical field resolved; no resolved critical field `LOW`; ≤ 1 `FAILED` invariant |
| `LOW` | Any resolved critical field `LOW`, or ≥ 2 `FAILED` invariants |
| `PARTIAL` | One or more critical fields `Unresolved` — we could not read them |

"Resolved" means `Extracted`, `UserSupplied`, `Derived`, **or** `NotDeclared`. A label that legitimately does not declare added sugars is not a scan failure — it is a declaration gap, reported by Layer 1. `PARTIAL` is reserved for *our* failure to read, preserving FR-ERR-03 at the scan level.

> **⚠ Architect's Note — aggregate confidence must not gate anything.**
>
> There is an obvious temptation to suppress advisory findings when `ScanConfidence` is `LOW`. That would be **double-gating**: FR-CNF-13 already handles this correctly and precisely, at the level of the individual determining input.
>
> A scan can be `LOW` overall because the protein reading is poor, while the sodium reading is impeccable — and the sodium finding should be presented with full confidence. Suppressing it would discard a good finding on the strength of an unrelated bad one.
>
> **`ScanConfidence` is for user orientation only: "how much of this should you check?" It never participates in rule evaluation.** This constraint should be enforced by keeping it out of the analysis engine's input types entirely, rather than by remembering not to use it.

---

## 5. Label Data

### 5.1 `FieldState` — the central union

This union is where FR-PAR-09, FR-ERR-03 and FR-CNF-12 are discharged simultaneously. It replaces what would otherwise be a nullable value plus a scatter of boolean flags.

| Variant | Fields | Meaning |
|---|---|---|
| `Extracted` | `quantity`, `basis`, `provenance`, `confidence`, `signals` | Read from the label |
| `Derived` | `quantity`, `basis`, `derivation`, `confidence` | Computed from other fields |
| `UserSupplied` | `quantity`, `basis`, `provenance` | Entered or corrected by the user — **no confidence field exists** |
| `Unresolved` | `reason`, `provenance` | We saw something and could not type it |
| `NotDeclared` | — | The label does not carry this |

`UserSupplied` having **no confidence field at all** — rather than a confidence set to some sentinel — is the M1 principle doing real work: FR-CNF-12 becomes impossible to violate rather than merely forbidden.

`Unresolved` vs `NotDeclared` is the distinction FR-ERR-03 demands, and it is the difference between "the label is incomplete" and "we failed". Conflating them would let a parser failure masquerade as a manufacturer's omission.

### 5.2 `NutrientField`

| Field | Kind |
|---|---|
| `nutrient` | `NutrientId` |
| `perHundred` | `FieldState` |
| `perServe` | `FieldState` |
| `perPack` | `FieldState` |

All three bases are always present as `FieldState` values — typically one `Extracted` and the others `Derived` or `NotDeclared`. Modelling them as a fixed triple rather than a list keeps FR-PRS-02 (display all three together) a lookup rather than a search, and makes "we could not compute per-pack because net quantity was unreadable" expressible.

### 5.3 `ServingInfo`

| Field | Kind | Notes |
|---|---|---|
| `declaredServingSize` | `FieldState` | The manufacturer's chosen serve |
| `servingsPerPack` | `FieldState` | Often "about N" |
| `netQuantity` | `FieldState` | Total pack contents |
| `reconciliation` | `ServingReconciliation?` | *Optional justified:* a **Layer 1** output (§6.2), and Layer 1 consumes the `ParsedLabel` this sits inside. Null from the parser; populated by Layer 1. Requiring it would make `ParsedLabel` unconstructible by its own producer. |

These three are **critical fields**. Serving-size manipulation is the primary legal deception on Indian packaging (`PROJECT_VISION.md` §2.1), so their extraction matters as much as any nutrient.

### 5.4 Ingredients

`Ingredient` — one entry in the declared list:

| Field | Kind | Notes |
|---|---|---|
| `position` | integer | 1-based; declaration order is legally meaningful (descending by weight) |
| `rawText` | text | As recognised, before interpretation |
| `identification` | `IngredientIdentification?` | *Optional justified:* additive identification is **Layer 1** work, scheduled by `ROADMAP.md` §4.3 item 4.4. Null until that engine exists. Distinct from the `Unidentified` variant, which records that identification was *attempted and failed* — null records that it has not yet been attempted, and conflating the two would let an unbuilt feature masquerade as a resolved absence (FR-ERR-03). |
| `subIngredients` | `[Ingredient]` | Possibly empty; preserves nesting (FR-PAR-12) |
| `provenance` | `Provenance` | |

`IngredientIdentification`:

| Variant | Fields | Confidence ceiling |
|---|---|---|
| `AdditiveByIns` | `insNumber`, `classTitle?` | May be `HIGH` |
| `AdditiveByName` | `matchedName`, `insNumber?` | Capped at `MEDIUM` (ADR-0005) |
| `PlainIngredient` | `normalisedName` | May be `HIGH` |
| `Unidentified` | `reason` | `LOW` |

The confidence ceiling on `AdditiveByName` is structural rather than advisory: name matching is fuzzy and language-dependent, and the model should make it impossible to present a fuzzy match with the same authority as an INS-number match.

### 5.5 `ParsedLabel` — the published contract

The boundary object between the parser and analysis. Per `ARCHITECTURE.md` AR5, **this is the only parser type that is a published contract**; S1–S8 intermediates are internal and refactorable.

| Field | Kind |
|---|---|
| `nutrients` | `[NutrientField]` |
| `servingInfo` | `ServingInfo` |
| `ingredients` | `[Ingredient]` |
| `declaredCategory` | `CategoryId?` — *optional justified:* category is never required (FR-CAT-02) |
| `invariantResults` | `[InvariantResult]` |
| `scanConfidence` | `ScanConfidence` |
| `rulePackVersion` | `Version` |
| `unsupportedScript` | boolean | FR-OCR-05 |

---

## 6. Analysis Data

### 6.1 `Finding` — two disjoint types

Layer 1 and Layer 2 findings are **separate types**, not one type with a flag (B6, ADR-0003). A boolean discriminator would permit a factual finding to be constructed with advisory content by mistake; separate types make the boundary a compile-time property.

### 6.2 `FactualFinding` (Layer 1)

| Field | Kind |
|---|---|
| `kind` | `NORMALISATION \| RDA_CONTRIBUTION \| SERVING_RECONCILIATION \| DECLARATION_GAP \| ADDITIVE_IDENTIFICATION` |
| `subject` | `NutrientId \| InsNumber \| ServingField` |
| `value` | `FieldState` |
| `derivation` | `Derivation` |
| `confidence` | `Confidence` |
| `messageId` | `MessageId` |

`Derivation` (FR-EXP-09) records the arithmetic:

| Field | Kind |
|---|---|
| `operation` | `NORMALISE_TO_100 \| SCALE_TO_SERVE \| SCALE_TO_PACK \| RDA_PERCENT \| SALT_TO_SODIUM \| ENERGY_CONVERT` |
| `inputs` | `[{ field, quantity, basis, confidence }]` |
| `constantsUsed` | `[{ constantId, value, sourceRef }]` |
| `result` | `Quantity` |

`constantsUsed` is what makes an RDA computation auditable: the 2,000 mg sodium denominator appears as a named constant with a citation, not as a number that materialised in the arithmetic.

`ServingReconciliation` — the product's signature Layer 1 output:

| Field | Kind |
|---|---|
| `declaredServe` | `FieldState` |
| `servesPerPack` | `FieldState` |
| `wholePackValues` | `[NutrientField]` |
| `discrepancy` | `NONE \| SERVES_INCONSISTENT \| SERVE_EXCEEDS_PACK \| NOT_COMPUTABLE` |

`discrepancy` is factual, not evaluative: it states that the arithmetic does not reconcile. Any suggestion that a small serve is *misleading* is Layer 2's business, and putting it here would violate FR-L1-01.

### 6.3 `AdvisoryFinding` (Layer 2)

**Has no public constructor.** Only the rule evaluator may create one, and creation requires a complete `Explanation` (ADR-0011, FR-EXP-02).

| Field | Kind |
|---|---|
| `nutrient` | `NutrientId` |
| `classification` | `LOW \| MODERATE \| HIGH_IN \| UNDETERMINED` |
| `severity` | `Severity` |
| `confidence` | `Confidence` |
| `determinacy` | `DEFINITE \| INDETERMINATE` — see §6.3a |
| `provisional` | boolean — true when determining inputs are `LOW` (FR-L2-09) |
| `explanation` | `Explanation` — **required, non-optional** |

`Severity` derives from the margin recorded in the explanation, so FR-L2-08 ranking is a read rather than a second computation — and cannot disagree with the explanation it is displayed beside.

### 6.3a Layer 2 over qualified quantities

Owner decision 4 on Q19 is absolute: **Layer 2 reasons explicitly over bounds. No implicit coercion to a point value is permitted anywhere.**

Against a rule such as `sodium PER_100G GTE 500 mg → HIGH_IN`:

| Declared value | Interval | Outcome |
|---|---|---|
| `EXACT 550 mg` | `[550, 550]` | Fires. `DEFINITE`. |
| `LESS_THAN 400 mg` | `[0, 400)` | Definitely does not fire. `DEFINITE`. |
| `GREATER_THAN 600 mg` | `(600, ∞)` | Definitely fires. `DEFINITE`. |
| `LESS_THAN 600 mg` | `[0, 600)` straddles 500 | **`UNDETERMINED` / `INDETERMINATE`** |

An `UNDETERMINED` finding is emitted rather than suppressed. It carries a full Explanation recording the interval, the threshold, and why the comparison could not conclude — which lets the product say something true and useful that it previously could not: *"the label declares less than 0.6 g, which does not settle whether this crosses the threshold."*

**`determinacy` and `provisional` are orthogonal and must not be merged.**

| | Meaning |
|---|---|
| `provisional` | We may have misread the label |
| `INDETERMINATE` | We read the label correctly, and what it says does not settle the question |

Both can hold at once. Collapsing them into a single "uncertain" flag would be precisely the implicit coercion Q19 decision 4 forbids, and it would tell the user the wrong thing: one is fixable by checking the packet, the other is not.

> **⚠ Architect's Note — threshold design now has a consequence worth watching.**
>
> `< 0.5 g` trans fat is extremely common, because a sub-threshold declaration supports a "trans fat free" claim. Against a rule like `transFat GTE 1 g`, it resolves cleanly — `sup = 0.5 < 1`, definitely does not fire.
>
> Against a strict rule like `transFat GT 0 g`, the same value straddles and every such product returns `UNDETERMINED`. That is *correct* behaviour, and it would also be a poor user experience repeated across the shelf.
>
> **Recommendation: when curating Layer 2 thresholds in Phase 7, check each one against the bound values that actually appear on Indian labels.** A threshold that renders a common declaration permanently undetermined is a badly chosen threshold, not a modelling failure — and the fix belongs in the rule pack, never in a coercion.

### 6.4 `Explanation`

Every element required by FR-EXP-01.

| Field | Kind | Notes |
|---|---|---|
| `ruleId` | `RuleId` | Must resolve in the rule pack (FR-EXP-04) |
| `ruleVersion` | `Version` | |
| `rulePackVersion` | `Version` | |
| `inputs` | `[{ nutrient, quantity, basis, confidence, origin }]` | Confidence exposed per input (FR-EXP-07) |
| `threshold` | `{ quantity, basis, comparator }` | |
| `margin` | `{ absolute: Quantity, ratio: Quantity }` | Both forms (FR-L2-07) |
| `outcome` | `classification` | |
| `sourceRefs` | `[SourceId]` | Non-empty (FR-KB-04) |
| `messageId` | `MessageId` | Resolves to localised text (FR-LOC-05) |

`sourceRefs` being non-empty is a type-level constraint, not a validation rule: an uncited advisory finding is unrepresentable.

### 6.5 `ScanResult`

| Field | Kind |
|---|---|
| `scanId` | `ScanId` |
| `parsedLabel` | `ParsedLabel` |
| `factualFindings` | `[FactualFinding]` |
| `advisoryFindings` | `[AdvisoryFinding]` |
| `declarationGaps` | `[NutrientId]` |
| `scanConfidence` | `ScanConfidence` |
| `rulePackVersion` | `Version` |
| `capturedAt` | `Instant` — supplied via the clock port, never read in-domain (M4) |

`advisoryFindings` may legitimately be empty. Per FR-L2-13 the UI must then state that **no flags were raised**, not that the product is fine — absence of a warning is not a clean bill of health, and the model deliberately provides no field that could be read as one.

---

## 7. Rule Pack Schema

Authored as JSON in `rulepack/` (ADR-0012), under CC BY 4.0 (ADR-0017). Validated in CI; the build fails on any error (FR-KB-03).

### 7.1 Layout

```
rulepack/
├─ manifest.json          version, integrity, compatibility
├─ sources.json           the citation registry — everything traces here
├─ nutrients/
│  ├─ synonyms.json       label text → NutrientId  (S5)
│  └─ rda.json            FSSAI denominators (Layer 1)
├─ rules/
│  ├─ thresholds.json     Layer 2 advisory rules
│  └─ confidence.json     S1/S2/S3 assignment + tolerances
├─ additives/
│  └─ ins.json            INS-keyed additive records
├─ categories/
│  └─ categories.json     category records + selectors
└─ messages/
   ├─ en.json
   └─ hi.json             ships only when reviewed (FR-LOC-04)
```

### 7.2 `manifest.json`

| Field | Notes |
|---|---|
| `version` | Semantic version; recorded on every finding (FR-KB-02) |
| `integrityHash` | Verified at load; no silent fallback (FR-ERR-06) |
| `minAppVersion` | Refuses to load into an app too old to interpret it |
| `contentLicence` | `CC-BY-4.0` (CON-10) |

### 7.3 `sources.json` — the citation registry

Every advisory claim in the product terminates here.

| Field | Notes |
|---|---|
| `sourceId` | Stable; referenced by rules and additives |
| `title`, `publisher`, `publicationDate`, `accessDate`, `url` | FR-KB-05 |
| `sourceType` | `REGULATION \| WHO_MODEL \| PEER_REVIEWED \| GOVERNMENT_GUIDANCE` |
| `evidenceStrength` | `ESTABLISHED \| LIMITED \| CONTESTED` (FR-KB-07) |

`evidenceStrength` is what allows the additive commentary to say "the evidence here is contested" rather than implying uniform certainty. Without it, P1 is not achievable for additives at all.

### 7.4 `synonyms.json` (S5)

The project's highest-frequency contribution path — a contributor who spots an unhandled label variant should be able to add it without touching Dart (§6.3 of `ARCHITECTURE.md`).

| Field | Notes |
|---|---|
| `nutrient` | `NutrientId` |
| `patterns` | Label text variants, each with a `ParseStrength` |
| `expectedUnits` | Which units are plausible — a mismatch lowers confidence |

### 7.5 `rda.json` (Layer 1)

The FSSAI-gazetted denominators (FR-L1-04): 2,000 kcal; 67 g total fat; 22 g saturated fat; 2 g trans fat; 50 g added sugar; 2,000 mg sodium. Each carries a `sourceRef`. Held as data because they are regulation, and regulation changes (A5, R5).

### 7.6 `thresholds.json` (Layer 2)

| Field | Notes |
|---|---|
| `ruleId`, `ruleVersion` | Cited in every Explanation |
| `nutrient`, `basis`, `comparator`, `threshold` | The comparison |
| `classification` | Outcome when it fires |
| `categorySelector` | Declarative scoping; **never code branching** (FR-KB-11, FR-CAT-04) |
| `sourceRefs` | Non-empty — validation fails otherwise |
| `messageId` | |

### 7.7 `ins.json`

| Field | Notes |
|---|---|
| `insNumber` | Integer primary key (ADR-0005) |
| `commonName`, `functionalClass` | |
| `descriptionMessageId` | Plain-language explanation (P9) |
| `evidenceStrength`, `sourceRefs` | FR-KB-07 |
| `permittedInIndia` | Regulatory status — Layer 1 fact |

### 7.8 `confidence.json`

Holds the S1/S2/S3 assignment table and the §4.4 tolerance bands, so both are tunable from corpus calibration without a code change. Every tolerance carries a note recording **how it was derived** — a tolerance with no recorded basis is indistinguishable from a guess, and will be treated as one by whoever inherits it.

### 7.9 Q13 resolved — region classification does not consult the rule pack

Region classification (S3) uses **structural cues only**: relative position, table geometry, keyword density against a small built-in marker set. It does not consult the nutrient synonym table.

The reason is Stage 3. Per `ARCHITECTURE.md` §11, S1–S4 are the reusable half of the pipeline. If S3 depends on nutrition vocabulary, it stops being reusable for cosmetics and medicine labels, which have entirely different vocabulary but the same physical layout problem.

The cost is that S3 will occasionally misclassify a region and S4/S5 must tolerate that. **That cost is preferable to forfeiting the Stage 3 reuse boundary**, which was the explicit reason §6.3 of the architecture kept S2 semantic-free in the first place.

---

## 8. Persistence

### 8.1 `StoredScan`

| Field | Notes |
|---|---|
| `scanId`, `capturedAt` | |
| `parsedLabel` | Serialised |
| `factualFindings`, `advisoryFindings` | **Findings as computed at the time** |
| `rulePackVersion` | FR-HIS-04 |
| `imageRef` | *Optional justified:* the user chooses whether to retain the image (FR-CAP-10) |
| `schemaVersion` | Migration support |

### 8.2 Findings are stored, not recomputed

FR-HIS-05 forbids silent re-evaluation. A stored scan viewed under a newer rule pack displays its **original findings with the original version noted**, and offers explicit re-analysis.

This means findings are serialised in full, including Explanations — which is the memory and storage cost flagged as AR4. The alternative, storing only `ParsedLabel` and recomputing on read, is cheaper and wrong: it would silently change history, which violates P1 in the way users are least likely to notice and most likely to be harmed by.

**Mitigation for AR4:** the stored Explanation retains rule references and margins but not the full pixel-level substitution chain, which is only useful during the session that produced it.

### 8.3 Migration

`schemaVersion` on every record. Migration is forward-only and explicit. A record that cannot be migrated is **surfaced to the user as unreadable, not silently dropped** — quietly discarding a user's history is a P1 violation.

---

## 9. Model Invariants

Properties of the model itself. Each is enforced by construction where possible, and property-tested regardless.

| # | Invariant | Enforcement |
|---|---|---|
| MI-01 | An `AdvisoryFinding` always has a complete `Explanation` | Type (no public constructor) |
| MI-02 | A `UserSupplied` field has no confidence value | Type (field does not exist) |
| MI-03 | Every `Quantity` has a `Unit`; every nutrient value has a `Basis` | Type |
| MI-04 | Confidence propagation never increases confidence | Property test |
| MI-05 | Every `sourceRef` and `ruleId` resolves in the rule pack | Build-time validation |
| MI-06 | No domain type contains display text | Static check |
| MI-07 | No domain type contains a wall-clock time | Static check |
| MI-08 | `Unresolved` and `NotDeclared` are never conflated | Type (distinct variants) |
| MI-09 | A field in a `FAILED` invariant is never `HIGH` | Property test |
| MI-10 | `ScanConfidence` never appears in analysis engine inputs | Static check |
| MI-11 | Quantities compare exactly (no floating point in the model) | Type |
| MI-12 | Declaration order of ingredients is preserved | Property test |
| MI-13 | Every `Quantity` carries a qualifier; `EXACT` is the default | Type |
| MI-14 | Quantity equality includes the qualifier | Type + property test |
| MI-15 | A qualifier never affects confidence assignment | Static check + property test |
| MI-16 | No code path coerces a qualified quantity to a point value | Static check + property test |
| MI-17 | Serialisation omits the qualifier when `EXACT`; deserialisation of an absent qualifier yields `EXACT` | Property test + CI-16 |

MI-10 deserves note: it is how §4.5's "aggregate confidence must not gate anything" becomes structural rather than a convention someone must remember.

MI-16 is the enforcement of Q19 decision 4. It is the hardest of the sixteen to check mechanically — a coercion can hide inside any arithmetic that reads `scaledValue` and ignores `qualifier`. **Recommendation: make the raw `scaledValue` inaccessible outside the interval operations**, so extracting a bare number requires deliberately asking for a bound (`infimum` / `supremum`) and thereby naming which one. A coercion then becomes visible in the code rather than implied by its absence.

---

## 10. Traceability

| Requirement | Discharged by |
|---|---|
| FR-PAR-04/05 (unit and basis required) | §2.2, §2.5, MI-03 |
| FR-PAR-06/07 (normalisation, kJ→kcal) | §2.3, §3.4 |
| FR-PAR-09 (extracted / unresolved / absent) | §5.1 `FieldState` |
| FR-PAR-10/12 (ingredient order, nesting) | §5.4, MI-12 |
| FR-PAR-11 (INS primary key) | §5.4, §7.7 |
| FR-PAR-13 (rule strength recorded) | §3.3 |
| FR-CNF-01 (every field has confidence) | §5.1, MI-02 |
| FR-CNF-02/03 (three signals, S1 optional) | §4.2 |
| FR-CNF-04 (invariant results recorded) | §4.3 |
| FR-CNF-05 (failed invariant caps confidence) | §4.3, MI-09 |
| FR-CNF-07 (aggregate confidence) | §4.5 |
| FR-CNF-12 (user-supplied) | §5.1, MI-02 |
| FR-EXP-01/03 (explanation mandatory) | §6.3, §6.4, MI-01 |
| FR-EXP-04 (references resolve) | §7.3, MI-05 |
| FR-EXP-07 (input confidence exposed) | §6.4 |
| FR-EXP-09 (Layer 1 derivation) | §6.2 |
| FR-ERR-03 (unreadable vs not declared) | §5.1, MI-08 |
| FR-KB-04/05 (citations) | §7.3 |
| FR-KB-06 (INS records) | §7.7 |
| FR-KB-07 (evidence strength) | §7.3 |
| FR-KB-11 (category selectors in data) | §7.6 |
| FR-L1-04 (RDA denominators) | §7.5 |
| FR-L1-05 (serving reconciliation) | §6.2 |
| FR-L2-07/08 (margin, severity) | §6.3, §6.4 |
| FR-HIS-04/05 (version, no silent re-eval) | §8.1, §8.2 |
| P4 (determinism) | §2.1, M4, MI-07, MI-11 |
| P5 (facts ≠ judgement) | §6.1 disjoint types |

---

## 11. Open Questions

| # | Question | Blocks | Needed by |
|---|---|---|---|
| Q2 | Does the OCR engine expose usable per-element confidence? | §4.2 S1 | Phase 2 week 1 |
| Q14 | Corpus-calibrated values for the INV-07/08/10 tolerance bands | §4.4 | **Before the MVP gate** |
| Q15 | Serialisation format for `StoredScan` — JSON or a keyed store? | §8.1 | Before history is built |
| Q16 | Does `MICROGRAM` earn its place, given no MVP nutrient uses it? | §2.3 | Before implementation |

Q16 is small but worth deciding rather than drifting into: an unused enum member invites a future nutrient to be added without the code change ADR-0014 deliberately requires.

---

## 12. Approval

| Item | Status |
|---|---|
| Core value objects and units defined | ✅ §2 |
| Provenance model defined | ✅ §3 |
| Confidence model, lattice properties, tolerances | ✅ §4 |
| Q3 resolved (tolerance bands, provisional + calibration mandate) | ✅ §4.4 |
| Q4 resolved (aggregate confidence, non-gating) | ✅ §4.5 |
| Q13 resolved (region classification is structural) | ✅ §7.9 |
| Label, analysis and explanation types | ✅ §5, §6 |
| Rule pack schema | ✅ §7 |
| Persistence and migration | ✅ §8 |
| Model invariants with enforcement mechanism | ✅ §9, MI-01…12 |
| No code written | ✅ Types described structurally |

*End of document. Approval required before proceeding to `TEST_STRATEGY.md`.*
