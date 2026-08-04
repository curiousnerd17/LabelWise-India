# ADR-0027 — Quantities carry a qualifier and denote intervals

- **Status:** Accepted
- **Date:** 2026-08-04
- **Note:** §Decision item 5 was added by the owner at acceptance. Nothing has been altered after acceptance; see the process note at the end.
- **Amends:** ADR-0021 (`Quantity` shape); `DATA_MODEL.md` v1.1 → v1.2
- **Related:** ADR-0023 (measurement integrity), ADR-0010 (confidence)

## Context

Indian packaged food labels routinely print values that are not point measurements:

- `< 0.5 g` trans fat — extremely common, because a declaration below a threshold supports a "trans fat free" claim.
- `About 4 servings` / `Approx. 4 servings` — manufacturers explicitly declining to claim precision.

`DATA_MODEL.md` v1.1 had nowhere to put this. `Quantity` was a bare scaled integer plus a unit. Both available workarounds destroy information: recording `< 0.5 g` as `0` discards a declaration the manufacturer deliberately made, and recording it as `0.5` asserts a precision the label explicitly disclaims.

This is not an edge case. It appears on a large share of real labels in the four priority categories.

## Decision

**A `Quantity` carries a `qualifier`: `EXACT` (default) | `LESS_THAN` | `GREATER_THAN` | `APPROXIMATELY`.**

The qualifier is part of the **value model**, not parser metadata — it travels with the number everywhere the number goes, including rule pack thresholds and persisted scans.

A qualified quantity denotes an **interval**, not a point:

| Qualifier | Interval |
|---|---|
| `EXACT v` | `[v, v]` |
| `LESS_THAN v` | `[0, v)` — lower bound 0 by INV-01 |
| `GREATER_THAN v` | `(v, ∞)` |
| `APPROXIMATELY v` | `[v−δ, v+δ]`, δ defined per unit in the rule pack |

Four consequences, all binding:

1. **Exact-match comparison includes the qualifier.** `LESS_THAN 0.5 g` is not equal to `EXACT 0.5 g`. A parser that reads `< 0.5` as `0.5` records an **Error**, not a Correct (ADR-0023).
2. **Invariant evaluation treats quantities as bounds.** Comparisons yield a fourth outcome, `INDETERMINATE`, when the intervals do not settle the question.
3. **Layer 2 reasons explicitly over bounds.** A threshold comparison against an interval that straddles the threshold is `INDETERMINATE` and is reported as such. **No implicit coercion to a point value is permitted anywhere.**
4. **Default is `EXACT`**, so the common case stays simple.

5. **The canonical serialised form is defined by the schema, not by implementations.** Two rules, both normative:

   - **Reading:** an absent `qualifier` MUST be interpreted as `EXACT`.
   - **Writing:** a quantity whose qualifier is `EXACT` MUST omit the field entirely. Emitting `"qualifier": "EXACT"` is invalid output, not a stylistic variant.

   JSON Schema's `default` keyword is annotation only — it constrains nothing. The canonical form is therefore stated normatively in the schema description **and enforced by a CI check** that rejects any serialised `"qualifier": "EXACT"`.

## Consequences

**Positive.** The label's own precision is preserved rather than silently improved or degraded. Bound reasoning is deterministic and testable. Interval arithmetic through Layer 1 derivations is straightforward: scaling a bound by a positive constant preserves its direction.

Fixing the canonical serialised form in the schema rather than in each implementation matters more than it first appears. Two consumers that disagree about whether to emit `"qualifier": "EXACT"` produce byte-different output for identical data — which breaks the rule pack integrity hash (FR-KB-09), breaks FR-PAR-02's byte-identical determinism guarantee, and breaks golden-corpus comparison. A convention that lives in one implementation's head is not a specification, and this project will eventually have a second consumer: the CC BY 4.0 knowledge base is intended to be read by other tools entirely (Stage 4).

It also lets the product say something honest it previously could not: *"the label declares less than 0.5 g, which does not settle whether this crosses the threshold."* That is more useful than a confident answer derived from a coerced number.

**Negative.** Every comparison site must handle four qualifiers rather than one. `INDETERMINATE` propagates into confidence, analysis and UI, all of which must render it. Accuracy measurement gets marginally harder, because reading a bound as a point is now correctly counted as an error.

**Two non-conflations that must be preserved:**

- **`INDETERMINATE` is not `FAILED`.** An unresolvable check is not evidence of error and must not cap confidence the way a failed invariant does. It contributes no signal, and is recorded distinctly so the explanation can say *why* the check could not be made.
- **Label imprecision is not our uncertainty.** A label printing `< 0.5 g` is being precise about its imprecision. Reading it correctly is a `HIGH`-confidence read. A qualifier must never reduce confidence.

## Alternatives considered

**Coerce to a point value at parse time** — rejected: destroys information, and the coercion would be invisible in every downstream explanation.
**Qualifier as parser metadata on `FieldState`** — rejected: the qualifier is part of what the number *means*. Separating them guarantees a call site that compares the number and forgets the qualifier.
**A separate `QualifiedQuantity` type alongside `Quantity`** — rejected: two numeric types invite using the wrong one, and every comparison would need to handle both.

---

## Process note

This record was drafted with `Status: Accepted` before the owner had approved it, which was premature on my part. The clarification in Decision item 5 was supplied by the owner **as a condition of acceptance** and incorporated before the record was accepted — so the immutability rule in ADR-0001 is intact, but only just.

**Recommendation, adopted in `docs/adr/README.md`:** new records are created with `Status: Proposed` and move to `Accepted` only on approval. Otherwise the difference between "completing a draft" and "editing an accepted record" becomes a judgement call, and an immutability rule that depends on judgement is not a rule.
