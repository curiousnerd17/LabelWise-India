# ADR-0002 — Offline-first, deterministic analysis; no cloud AI

- **Status:** Accepted
- **Date:** 2026-08-04
- **Supersedes:** —

## Context

The product is used in shops with no signal, on metered data, by users for whom a photograph of their shopping is sensitive. A cloud-AI label interpreter would be easier to build and would handle messy labels better.

## Decision

All analysis runs on-device using a deterministic rule engine. No cloud AI, no LLM inference, no per-scan network dependency. The MVP ships without the `INTERNET` permission (see ADR-0016).

## Consequences

**Positive.** Works where it is needed. Zero recurring cost (CON-02). Same input always yields the same output, so the system is testable, auditable and reproducible. No egress path for user data.

**Negative.** We must build parsing and analysis ourselves rather than delegating to a model. Handles messy labels worse than a large model would. Improvement requires engineering, not a prompt change.

## Alternatives considered

**Cloud AI interpretation** — rejected on four independent grounds: offline requirement, recurring cost, privacy, and non-determinism. The last is decisive on its own: a model that can confidently invent a sodium value cannot be tested or trusted.
**On-device small model** — rejected for the MVP: still non-deterministic, and adds size and complexity for a problem that deterministic parsing can address.
