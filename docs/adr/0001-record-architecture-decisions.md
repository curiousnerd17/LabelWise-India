# ADR-0001 — Record architecture decisions in an ADR log

- **Status:** Accepted
- **Date:** 2026-08-04
- **Deciders:** Owner, Chief Software Architect

## Context

LabelWise India is built by a solo developer with no peer reviewer. The reasoning behind a decision lives only in the head of the person who made it, and decays quickly. A future contributor — or the same developer in six months — encountering an unusual boundary will either preserve it without understanding it, or remove it without understanding why it was there. Both are failures.

The Phase 1 documents record *what* was decided at length. They are long, and they are revised. A reader cannot easily tell which statements are load-bearing decisions and which are description.

## Decision

Every architecturally significant decision is recorded as a numbered ADR in `docs/adr/`.

- ADRs are **immutable once accepted**. A decision that changes is superseded by a new ADR, never edited in place.
- ADRs are short. If one exceeds roughly two screens, the decision is probably two decisions.
- "Architecturally significant" means: it constrains future change, is expensive to reverse, or would be surprising to a newcomer.
- Code, documents and pull requests cite ADR numbers when a decision is relevant.

## Consequences

**Positive.** Rationale survives the person who held it. Drift becomes visible: a change that contradicts an accepted ADR is detectable in review rather than invisible. New contributors get the *why*, not just the *what*.

**Negative.** Writing overhead on every significant decision. A stale log is worse than none, so superseding must be disciplined.

## Alternatives considered

**Rationale in code comments** — rejected: scattered, unfindable, deleted with the code they explain.
**Rationale only in the Phase 1 documents** — rejected: those documents are revised, so the reasoning behind superseded decisions is lost exactly when it is most needed.
