# ADR-0004 — Anchor advisory thresholds on WHO SEARO, not FSSAI

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

The instinctive anchor for an Indian product is FSSAI. But FSSAI has no finalised front-of-pack nutrient-profile model: the 2022 draft Indian Nutrition Rating was never operationalised, and as of early 2026 FSSAI has told the Supreme Court it intends to withdraw the draft pending further research. There is no legally sanctioned Indian answer to "is this product healthy."

## Decision

Layer 2 thresholds derive from the **WHO South-East Asia Region Nutrient Profile Model (2017)**, supplemented by ICMR-NIN dietary guidance. Thresholds live in the rule pack with citations.

FSSAI regulation remains authoritative for **Layer 1** — mandatory declarations, RDA denominators, additive declaration rules — where it does have force.

## Consequences

**Positive.** Published, citable, regionally calibrated, and independently validated against the Indian market (31,516 products). Every threshold traces to a source.

**Negative.** Not a regulatory endorsement, and must not be presented as one. Applied to the Indian market, SEARO flags roughly two thirds of products — an advisory layer that warns about most of the shelf risks becoming noise, which is a UX problem to be solved by ranking and magnitude, never by weakening the science.

## Alternatives considered

**FSSAI INR thresholds** — rejected: the model is being withdrawn and has no operative force.
**Nutri-Score** — rejected: calibrated to European diets, not recognised in India.
