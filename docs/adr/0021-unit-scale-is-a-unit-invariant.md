# ADR-0021 — Unit scale is an invariant of the Unit, not state on Quantity

- **Status:** Accepted
- **Date:** 2026-08-04
- **Amends:** ADR-0012 context (data model §2.2); corrects `DATA_MODEL.md` v1.0

## Context

ADR-0010 and the data model represent quantities as scaled integers to obtain exact arithmetic and deterministic equality. The first draft of the model carried three fields on `Quantity`: `scaledValue`, `unit`, and `scale`.

That was a modelling error. It permitted two quantities with the same unit but different scales — a state that is meaningless, and that principle M1 ("make illegal states unrepresentable") says should not be constructible. Worse, its failure mode is silent: a comparison between mismatched-scale quantities would return a confident wrong answer rather than an error.

## Decision

**Scale is a fixed property of the `Unit` definition.** `Quantity` holds only `scaledValue` and `unit`. Scale is derived, never stored per value, and never overridable.

## Consequences

**Positive.** The illegal state is unconstructible. Same-unit comparison reduces to integer comparison with no reconciliation step, removing an entire class of silent comparison bug. One authoritative place defines precision per unit.

**Negative.** Changing a unit's scale becomes a global change affecting all persisted quantities in that unit, requiring a migration. This is correct — such a change *is* global — but it must be recognised as a schema migration rather than a local edit.

## Alternatives considered

**Scale as a `Quantity` field** — rejected as above: permits an illegal state with a silent failure mode.
**Scale inferred at comparison time from context** — rejected: reintroduces the same reconciliation risk, less visibly.
