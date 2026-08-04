# ADR-0010 — Confidence is a four-level lattice; arithmetic invariants are the primary signal

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

Three confidence signals are available: OCR character confidence (S1), parse-rule strength (S2), and arithmetic invariant validation (S3). The intuitive ranking puts S1 first. S1's availability is also unverified until the OCR spike.

## Decision

Confidence has exactly four levels — HIGH, MEDIUM, LOW, ABSENT — forming a totally ordered bounded lattice. **Propagation is the meet (minimum) operation**: a derived value can never be more confident than its least confident input.

Signal priority is **S3 primary, S2 secondary, S1 an optional refinement** added after the spike resolves.

No numeric percentage is ever shown to the user.

## Consequences

**Positive.** S3 is engine-independent and deterministic, and it catches the failure that actually harms users — a misread digit. An OCR engine that reads `3` as `8` reports *high* character confidence; only the arithmetic catches it. Meet being associative, commutative and idempotent makes determinism provable by property test rather than merely intended. Removes a first-class principle from the critical path of an unverified assumption.

**Negative.** Invariants only fire when the participating fields are present, so sparse labels get weaker signal. Tolerance bands must be calibrated empirically, not guessed.

## Alternatives considered

**S1-primary** — rejected: unverified availability, and confidently-wrong OCR is the dominant real failure mode.
**Numeric confidence score** — rejected: implies precision the signals do not possess.
