# ADR-0003 — Separate factual (Layer 1) and advisory (Layer 2) analysis

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

The product must both restate what a label declares and interpret whether those values are concerning. These are different kinds of claim with different epistemic standing and different liability exposure. India has no finalised regulatory nutrient-profile model (see ADR-0004), so "is this healthy" cannot be answered with regulatory authority.

## Decision

Analysis is split into two layers, separate in the data model, the rule engine and the UI.

- **Layer 1 (Factual)** restates declared values, gazetted arithmetic (%RDA against FSSAI denominators), serving-size reconciliation, declaration gaps and additive identification. It contains no judgement and emits no comparative language.
- **Layer 2 (Advisory)** interprets Layer 1 against published nutrition evidence. Every output carries a citation and an explanation, and is marked as guidance.

Layer 1 must compile, run and pass its tests in a build where Layer 2 is absent. That test is the boundary's proof.

## Consequences

**Positive.** Layer 1 is defensible because it only restates facts. Layer 2 is defensible because it is explicitly advisory and cited. Survives the regulatory vacuum. Mitigates the risk of advisory output being read as medical advice.

**Negative.** Two finding types, two evaluation paths, two presentation treatments. More UI work to keep the distinction legible — particularly on the 720p reference device.

## Alternatives considered

**Single unified analysis** — rejected: it would blur declared fact and interpretation, which is the precise failure the product exists to correct.
