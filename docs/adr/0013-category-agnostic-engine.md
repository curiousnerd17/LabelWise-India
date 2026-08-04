# ADR-0013 — The parser and rule engine are category-agnostic

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

Schedule pressure suggested narrowing the MVP to two product categories. That would have narrowed the architecture to solve a scheduling problem.

## Decision

Validation scope and architectural scope are separate decisions.

The domain core contains **no category-specific branching**. Category is an optional attribute, never a precondition — the pipeline must produce a useful result for a product of unknown category. Where a rule applies only to certain categories, that scoping is a declarative selector in rule pack data.

Four categories are prioritised for **validation and corpus construction**: biscuits, chips, namkeen, instant noodles. They are chosen to be adversarial — the worst OCR surface (metallised film), the longest ingredient lists, the most aggressive serving-size manipulation, and the most structurally ambiguous panels (multi-component packs).

Verified by a "fifth category" dry run: a category outside the four, added as data only, processed end to end with no code change.

## Consequences

**Positive.** Scope reduction becomes a data decision rather than a code rewrite. Expansion after MVP is content work. No temporary schedule constraint baked into permanent design.

**Negative.** Category-specific optimisations are unavailable — anything category-aware must be expressible as a data selector.

## Alternatives considered

**Two-category architecture** — rejected: conflates validation surface with architectural surface.
