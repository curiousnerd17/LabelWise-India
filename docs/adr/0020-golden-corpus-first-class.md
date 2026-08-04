# ADR-0020 — The golden corpus is a deliverable, not test scaffolding

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

A deterministic parser is only as good as the evidence that it is correct. Parser accuracy is the project's headline quality claim, and without measurement it is an opinion.

## Decision

The golden corpus — real label photographs paired with hand-verified expected parses, plus recorded OCR output — lives at `corpus/` as a top-level directory, not under a test folder. It is built in parallel with the parser from Phase 2, not retrofitted.

Target for the MVP gate: **≥ 50 labels, ≥ 10 per priority category**, deliberately over-sampling adversarial cases — metallised film, curved surfaces, low light, poor print, two-column panels, multi-component packs.

Parser accuracy is published in the README, overall and per category.

## Consequences

**Positive.** Accuracy becomes a measured number rather than a claim. Regressions are caught. Storing recorded OCR output alongside each image lets parser tests run without OCR at all — separating parser regressions from OCR-version drift.

**Negative.** Slow, unglamorous, non-engineering work that gates an engineering deliverable. This is the schedule risk most likely to be underestimated.

**Discipline:** a corpus of easy labels proves nothing. If the initial pass rate is not uncomfortable, the corpus is wrong. When accuracy disappoints, improve the parser — do not curate an easier corpus or quietly redefine "critical field".
