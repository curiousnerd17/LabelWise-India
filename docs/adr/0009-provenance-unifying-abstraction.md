# ADR-0009 — Provenance is the single abstraction beneath confidence and explainability

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

Confidence reporting (P2) and explainability (P3) arrived as two separate owner requirements and look like two features.

## Decision

They are two views of one recorded fact: what produced this value, from which inputs, under which rule, at what strength. **Provenance** is recorded by every pipeline stage for every value it produces. Confidence is computed from it; Explanation is Provenance plus a rule reference plus a citation.

## Consequences

**Positive.** Built once instead of twice. Confidence and explanation cannot drift apart, because they read the same data. The full chain from pixel to verdict is reconstructible, which makes exposing input confidence inside an explanation a lookup rather than a re-derivation.

**Negative.** Every stage must record provenance even when nothing will read it. Values become heavier objects — a real cost on a 4 GB device.

## Alternatives considered

**Separate confidence and explanation subsystems** — rejected: duplicated plumbing, and they would inevitably diverge, producing a system that can confidently explain a verdict it did not reach.
