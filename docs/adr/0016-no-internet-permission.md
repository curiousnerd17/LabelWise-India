# ADR-0016 — The MVP ships without the INTERNET permission

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

The product claims to be offline-first and to keep user data on-device. Claims are cheap; users have no way to verify them.

## Decision

The MVP does not declare the `INTERNET` permission.

## Consequences

**Positive.** Offline operation and no-egress become **OS-enforced facts** rather than promises. A sceptical user can verify them from the app listing. Eliminates an entire class of accidental-egress bug, including via a dependency.

**Negative.** Optional rule pack refresh cannot be enabled without adding the permission in a later release — visible to users as a permission change and requiring honest explanation. Rules out any third-party dependency that assumes network access.

The architecture keeps the door open: the rule pack loader is source-agnostic, so enabling refresh is a new source, not a redesign. But **adding a network permission later is a product decision to be made deliberately**, not a routine follow-up.

## Alternatives considered

**Declare the permission but never use it** — rejected: forfeits the entire verifiability benefit for no gain.
