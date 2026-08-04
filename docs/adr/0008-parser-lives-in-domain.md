# ADR-0008 — The parser belongs to the domain, not to infrastructure

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

Parsing OCR output *feels* like infrastructure: messy input, mechanical string handling, adjacent to a third-party engine. The instinct is to place it beside the OCR adapter.

## Decision

The parser lives in `lw_domain`. Only text *recognition* is infrastructure.

The reasoning: parsing is where the knowledge lives. That `Energy (kcal)` and `ENERGY, kcal` denote the same nutrient; that a value in the right-hand column is per-serve; that saturated fat cannot exceed total fat. That is domain knowledge, not plumbing.

## Consequences

**Positive.** The parser is testable without a device, which makes the 90% coverage target and fast corpus iteration achievable. It is versioned against the rule pack. Its stages are independently unit- and snapshot-testable.

**Negative.** The domain is larger and more complex than a "pure business rules" layer usually is. Requires a neutral recognition model at the OCR boundary, with its own mapping cost.

## Alternatives considered

**Parser in infrastructure** — rejected: untestable without a device, unversionable against the rule pack, and it would make the project's headline accuracy metric expensive to measure.
