# ADR-0022 — Version is a semantic value object, not an opaque string

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

Rule pack versions and rule versions are recorded on every finding and every stored scan, and are compared in two places that matter: `minAppVersion` compatibility at load time, and FR-HIS-05 (a stored scan viewed under a newer pack).

Modelled as a string, comparison is lexicographic. Lexicographically, `"1.10.0" < "1.9.0"` — which is wrong, and whose failure mode is a rule pack silently refusing to load, or silently loading when it should not.

## Decision

`Version` is a structured value object of `major.minor.patch` integers. Ordering and compatibility are defined operations on the type, not ad-hoc handling at each call site.

**Compatibility rule:** a pack loads when its `major` matches the application's supported major and its `minor.patch` is at least `minAppVersion`. A major mismatch is an explicit reported refusal (FR-ERR-06), never a best-effort load.

## Consequences

**Positive.** Comparison is correct by construction. Compatibility logic exists once and is unit-testable in isolation. Malformed versions fail at parse time, in CI, rather than at load time on a user's device.

**Negative.** A parsing and formatting step at the serialisation boundary. Marginally more ceremony than a string.

## Alternatives considered

**Opaque string with comparison helpers** — rejected: the helpers would be correct, and someone would eventually compare the strings directly. The type makes that impossible rather than merely discouraged.
