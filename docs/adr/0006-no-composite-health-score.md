# ADR-0006 — No composite health score in the MVP

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

A single 0–100 score or A–E grade is the most requested feature in this product category and the easiest to display.

## Decision

The MVP emits **per-nutrient flags only**. No composite score, grade, star rating or ranking. Revisit only after v1.0, and only if user testing shows flags are genuinely not actionable. If ever built, it must be a transparent, published, reproducible function of the flags.

## Consequences

**Positive.** Avoids making an unanchored health claim about a third party's product in a jurisdiction with no sanctioned model. Preserves information — "high in sodium" and "high in sugar" stay distinct and actionable. Sidesteps a category of regulatory attention.

**Negative.** Less immediately satisfying than a single number. Requires more UI to communicate. Users may perceive it as less decisive.

## Alternatives considered

**Nutri-Score-style grade** — rejected with ADR-0004: no Indian anchor.
**Internal proprietary score** — rejected: an opaque number is exactly what the product exists to replace.
