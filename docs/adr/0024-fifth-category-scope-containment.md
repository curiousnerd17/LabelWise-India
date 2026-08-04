# ADR-0024 — The fifth validation category is architectural verification only

- **Status:** Accepted
- **Date:** 2026-08-04
- **Related:** ADR-0013 (category-agnostic engine)

## Context

Packaged beverages were selected as a fifth category to verify that adding a category is a data-only change (FR-CAT-06). Its value is that it changes the *basis dimension* — `PER_100ML` rather than `PER_100G` — which is the one blind spot the four mass-based priority categories cannot expose.

A verification set that is useful is also a verification set that invites expansion. "We already handle beverages, we may as well support them properly" is a reasonable-sounding sentence that adds a fifth corpus, a fifth accuracy target, and a fifth set of thresholds to curate.

## Decision

The fifth category remains **architectural verification only** and must not silently expand MVP scope.

| In scope | Out of scope |
|---|---|
| 5 labels, added as rule pack data only | The ≥85% accuracy bar |
| Proving zero `lw_domain` changes are required | A 10-label corpus |
| Proving `PER_100ML` flows end to end | Beverage threshold curation |
| Proving INV-06 reports `INAPPLICABLE` | Per-category accuracy reporting |

**Pass criterion:** the five labels process end to end with correct bases and units and **zero changes to `lw_domain`**. If any Dart file must change, FR-CAT-01 has failed — and that finding matters far more than the parse quality.

Promoting beverages to a supported category is a post-MVP decision requiring a documented scope change.

## Consequences

**Positive.** Preserves the verification value without importing a fifth category's schedule cost. Keeps the MVP's four-category commitment honest.

**Negative.** Beverage parses may be visibly imperfect while beverage support is technically demonstrated. That gap must be stated rather than left for a user to discover.

## Alternatives considered

**Promote beverages to a fifth supported category** — rejected: adds corpus, curation and accuracy obligations to a schedule already assessed as over-committed.
**Drop the fifth category entirely** — rejected: forfeits the only check on the mass-basis assumption, which is precisely the blind spot FR-CAT-06 exists to find.
