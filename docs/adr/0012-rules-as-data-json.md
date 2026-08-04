# ADR-0012 — Rules, thresholds and content live in a JSON rule pack

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

Nutrition thresholds change, additive science changes, and FSSAI regulation changes. Rules compiled into Dart conditionals become stale and stay stale. Non-engineer contributors — nutrition reviewers — must be able to contribute.

## Decision

All thresholds, rules, additive records, nutrient synonyms, citations and message text live in a versioned, schema-validated JSON rule pack, authored in `rulepack/` at the repository root. Full validation runs in CI and fails the build; the runtime performs an integrity check only.

The pack version is recorded on every finding and every stored scan.

## Consequences

**Positive.** Content evolves without a code change. Diffable and reviewable in a pull request by a non-engineer. Rules carry the identity, version and citation that explanations need. Makes the Stage 3 expansion to cosmetics a new pack rather than a new application.

**Negative.** The rule language is a language, and will be less expressive than Dart. Some future rule will not fit the schema. **When that happens, extend the schema — never bypass it.** One exception is how rules-as-data dies. Expect two or three schema extensions during Phase 2 and budget for them as normal work.

## Alternatives considered

**YAML** — rejected: needs a parsing dependency, and its implicit typing creates silent-error risk in a file that must be exactly right.
**SQLite** — rejected: binary, not diffable, hostile to contribution — which defeats the boundary's main purpose.
**Binary/protobuf** — rejected as premature: no measurement yet says JSON is too slow. If cold start is later threatened, add a build-time compilation step from the same JSON source rather than changing the authoring format.
