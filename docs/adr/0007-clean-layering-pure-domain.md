# ADR-0007 — Clean layering with a pure domain and an inward dependency rule

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

A solo developer building a 30-day MVP has strong reason to prefer a simple structure. But the parser must be iterated dozens of times against a 50-label golden corpus, and the OCR engine is the dependency most likely to need replacing.

## Decision

Five layers — Domain, Application, Ports, Infrastructure, Presentation — as separate Dart packages. Source dependencies point inward only. `lw_domain` declares **zero** dependencies: no Flutter, no packages, not even JSON.

Enforcement is mechanical, not cultural: package manifests, import lints, a no-Flutter-binding test run, and a static scan for `DateTime.now`, `Random`, `Platform` and `Locale` in the domain. All fail CI.

## Consequences

**Positive.** The whole corpus runs in seconds without a device — the difference between a parser that reaches 85% accuracy and one that does not. OCR becomes an adapter swap. Framework choices become cheap and reversible. Pure functions move across isolate boundaries safely.

**Negative.** More packages, more files, more mapping between layer representations. Real daily friction for one developer. Tempts a spanning "shortcut" module.

## Alternatives considered

**Three-layer UI/logic/data** — cheaper and adequate for CRUD. Rejected: no natural home for ports, so OCR types leak into logic, forfeiting both device-free testing and engine replaceability. Saves days; costs the project's central quality property.

**Escape hatch (see ADR-0019):** if layering measurably slows delivery, merge Application into Domain before relaxing any other boundary.
