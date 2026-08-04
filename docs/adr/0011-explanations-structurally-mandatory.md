# ADR-0011 — An advisory finding without an explanation is unrepresentable

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

Requiring explanations by convention produces explanations that are present in the happy path and missing at the edges. Generating them lazily on user request invites reconstruction separately from the decision, allowing explanation and verdict to drift.

## Decision

Advisory findings have no public constructor. Only the rule evaluator can create one, and creation **requires** a complete Explanation, produced by the same evaluation that produced the finding. Dangling rule or source references fail build-time validation.

## Consequences

**Positive.** The requirement is enforced by the compiler and the build rather than by test coverage or reviewer attention. Explanation and decision cannot diverge. Severity ranking becomes free, since the margin is already recorded.

**Negative.** The evaluator is harder to write — explanation construction must be threaded through every path. Findings are heavier and serialise larger.

## Alternatives considered

**Explanation generated on demand** — rejected: allows a system to confidently explain a verdict it did not actually reach, which is disqualifying for a product whose proposition is honesty.
