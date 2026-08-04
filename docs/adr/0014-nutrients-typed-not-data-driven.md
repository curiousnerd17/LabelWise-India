# ADR-0014 — Nutrients are a typed closed set; adding one requires code

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

ADR-0012 data-drives rules, thresholds, additives and text. Consistency argues for data-driving the nutrient set too. This is the one place the pattern is deliberately broken.

## Decision

Nutrients are a closed, typed set in the domain. Adding one is a deliberate code change plus rule pack content.

## Consequences

**Positive.** Compile-time guarantees that a nutrient exists. Invariants resolve against types, not runtime string lookups. Typos fail the build rather than a user's scan.

**Negative.** Adding a nutrient is not a contributor-only change. Inconsistent with the data-driven pattern elsewhere, which must be explained rather than discovered.

## Rationale

The set of nutrients FSSAI mandates is small, stable and legally defined; it changes on a regulatory timescale of years, not a contribution timescale of days. A stringly-typed domain would pay a cost on every line, forever, to buy flexibility on an axis that barely moves.

**General principle:** data-drive what changes often (rules, thresholds, additives, synonyms, text); type what changes rarely (nutrients, units, bases, confidence levels). Data-driving everything is not more flexible — it is just untyped.
