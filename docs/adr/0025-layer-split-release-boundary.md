# ADR-0025 — The Layer 1 / Layer 2 split is the release boundary

- **Status:** Accepted
- **Date:** 2026-08-04
- **Related:** ADR-0003 (two-layer analysis)

## Context

The specified MVP was assessed at 50–61 solo working days against a 30-day target — roughly 2.5× over. The scope had also grown after the target was set: confidence and explainability became first-class subsystems, category-agnostic verification was added, and the corpus grew to 55 labels with a holdout split. Every addition improved the product; none made it faster.

The quality bar is fixed and scope is the variable (`PROJECT_VISION.md` §7.6), so the question was where to cut.

## Decision

Ship in two releases, split at the Layer 1 / Layer 2 boundary:

- **v0.1 — Factual** (~30 working days): capture, OCR, parser, confidence, correction, Layer 1 (normalisation, %RDA, serving reconciliation, declaration gaps, common additives), history, English UI.
- **v0.2 — Advisory** (~20 further working days): Layer 2 thresholds, full Explanations, complete evidence curation, severity ranking, expanded additive coverage.

## Consequences

**Positive.** The architecture already required this seam: FR-L2-01 states that *"Layer 1 must remain fully functional with Layer 2 disabled."* That requirement existed for testability and regulatory defensibility, and turns out to describe a shippable product.

v0.1 is useful alone — it answers what a packet contains per 100 g and per pack, and whether the serving arithmetic reconciles. It is also the half carrying all the parsing risk, so the risky work ships first and gets real feedback.

Critically, it moves **knowledge base curation off the critical path**. That work is 5–8 days of non-parallelisable research needed almost entirely for Layer 2. v0.1 needs only the six FSSAI RDA denominators, the nutrient synonym table, and additive records for the ~60–80 INS numbers common to the four priority categories.

**Negative.** v0.1 ships without the advisory guidance that motivates much of the product's appeal. Users may find a purely factual release underwhelming, and that must be communicated honestly rather than oversold. Unknown INS numbers will be reported as unidentified with the number shown — correct under P1, but visibly incomplete.

## Alternatives considered

**Single MVP at ~55 working days** — legitimate if the date does not matter, but nothing ships until everything works, and the parser gets no real-world feedback for eleven weeks.
**Full MVP in 30 days** — rejected: achievable only by lowering the quality bar, which contradicts the project's premise.
