# ADR-0019 — If layering must be simplified, merge Application into Domain first

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

ADR-0007 accepts more structure than a 30-day solo MVP normally warrants. That is a real schedule risk (AR1). Under pressure, the temptation will be to relax whichever boundary is causing friction that week — which is how the wrong thing gets conceded.

## Decision

The order of concessions is fixed **now, while calm**:

1. **First concession:** merge `lw_application` into `lw_domain`. The use cases are thin; the domain stays pure and testable. Cheapest boundary to lose.
2. **Not negotiable under schedule pressure:** the Flutter boundary (B1), the OCR boundary (B2), and domain purity. These are load-bearing for device-free testing, corpus iteration speed, and OCR replaceability.

## Consequences

**Positive.** Removes an in-the-moment judgement call made under stress. Protects the boundaries that carry the project's central quality property.

**Negative.** Merging layers is still work, and doing it mid-project has its own cost. The concession must be taken decisively when needed rather than debated repeatedly.

## Trigger

Invoke when layering is *measurably* slowing delivery by mid-Phase 2 — not on the basis of felt friction.
