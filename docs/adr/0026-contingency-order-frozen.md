# ADR-0026 — The contingency order is frozen

- **Status:** Accepted
- **Date:** 2026-08-04
- **Related:** ADR-0019 (AR1 concession order), ADR-0023 (measurement integrity)

## Context

`ROADMAP.md` §6 fixes the order in which scope is conceded under schedule pressure, and lists what is never conceded. Such a list is only useful if it survives the pressure it was written for. A concession order that can be revised in the moment is not an order — it is a suggestion, and the thing conceded will be whatever is causing friction that week.

## Decision

The contingency order in `ROADMAP.md` §6 is **frozen**. It may not be renegotiated under schedule pressure. Changing it requires a **new ADR**, written and accepted before the change takes effect.

Concessions, in order: defer Layer 2 → reduce priority categories from four to three (publishing the gap) → defer history → merge `lw_application` into `lw_domain` → defer localisation scaffolding.

**Never conceded for schedule:** domain purity, the OCR boundary, the Flutter boundary, exact-match accuracy measurement, the Critical Error Rate bar, and golden corpus integrity.

## Consequences

**Positive.** Removes an in-the-moment judgement made under stress, when judgement is worst. The friction of writing an ADR is deliberate: it forces the decision to be argued in writing rather than taken quietly. The protected list keeps schedule pressure away from the properties carrying the project's central claim.

**Negative.** Genuine new information may make a different concession correct, and the ADR requirement adds delay before acting on it. That delay is accepted as the cost of the guarantee — and writing the ADR is an hour, not a week.

## Alternatives considered

**Advisory ordering** — rejected: an ordering that can be ignored provides nothing precisely when it is needed.
**No fixed order** — rejected: guarantees that the concession is chosen by whatever hurts most that week rather than by what costs least overall.
