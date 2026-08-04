# ADR-0017 — Apache 2.0 for code, CC BY 4.0 for the knowledge base

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

The repository contains two different kinds of work: source code, and a curated, cited nutrition and additive knowledge base. A long-term goal is publishing that knowledge base as a standalone citable dataset. A software licence fits a dataset badly, and a content licence fits code badly.

## Decision

- **Source code:** Apache License 2.0.
- **Rule pack / knowledge base content (`rulepack/`):** CC BY 4.0.
- The two are stated separately, and the boundary between them is the `rulepack/` directory.

## Consequences

**Positive.** Apache 2.0 gives an explicit patent grant and an operative "AS IS" warranty disclaimer, reinforcing the no-warranty posture the in-product disclaimer states in plain language. CC BY 4.0 makes the knowledge base reusable and citable by other projects with attribution — directly enabling the Stage 4 goal.

**Negative.** Contributors must understand which licence applies to their contribution. The directory boundary must stay clean: a stray rule in Dart is now a licensing inconsistency as well as an architectural violation.

**Obligation:** every third-party dependency's licence must be Apache-2.0 compatible and recorded. **GPL-family dependencies must be rejected at selection time**, not discovered at release.

## Alternatives considered

**Single Apache 2.0 licence for everything** — rejected: a software licence applied to a dataset creates ambiguity for exactly the downstream reuse Stage 4 wants to encourage.
