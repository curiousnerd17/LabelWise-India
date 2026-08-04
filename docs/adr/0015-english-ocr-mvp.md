# ADR-0015 — English-only OCR for the MVP; detect and decline other scripts

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

A common assumption is that Indian packaged food labels always carry English. They do not: FSSAI requires mandatory declarations in **English *or* Hindi in Devanagari**, with regional languages permitted only as additions. A Hindi-only label is fully compliant.

In practice, national FMCG brands label in English almost universally.

## Decision

The MVP recognises English only. Devanagari-dominant images are **detected and explicitly declined** — "this label is not in a language I can read yet" — never mis-parsed. The OCR adapter interface stays script-agnostic so Devanagari is an adapter change, not a redesign.

The limitation is stated plainly in-product and in the README.

## Consequences

**Positive.** Captures the large majority of the target market at a fraction of the OCR risk. Keeps the 30-day MVP plausible. An honest refusal preserves trust; a bad parse destroys it.

**Negative.** A real, legally permitted blind spot concentrated in regional and smaller brands — invisible to us until users hit it.

## Alternatives considered

**Devanagari OCR in the MVP** — deferred to Stage 2: significant accuracy risk on curved, glossy packaging, and it would compete with the parser for the schedule.
**Attempt a parse anyway** — rejected: violates honesty over completeness.
