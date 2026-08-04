# ADR-0005 — Key the additive knowledge base on INS number

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

Indian regulation requires additives to be declared by functional class title **plus INS number** — "Preservative (INS 211)", "Colour (INS 102)". Most label-reading products elsewhere must match additives by name string, which is fuzzy, language-dependent and error-prone.

## Decision

Additive records are keyed on the INS number as an integer. Name-based matching exists only as a secondary path at explicitly lower confidence.

## Consequences

**Positive.** Exact, deterministic, language-independent lookup — a structural advantage a US- or EU-targeted product does not have. Trivially testable. Survives Hindi labels, since the digits are the same.

**Negative.** Depends on the INS number being printed and legible (assumption A4). Where it is absent or unreadable, we fall back to weaker name matching and must say so.

## Alternatives considered

**Name-based matching as primary** — rejected: discards a legally mandated machine-readable identifier in favour of fuzzy string work.
