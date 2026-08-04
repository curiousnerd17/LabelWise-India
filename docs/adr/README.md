# Architecture Decision Records

This log records **why** LabelWise India is built the way it is. The Phase 1 documents describe the system; these records preserve the reasoning, so that a future contributor — or the same developer in six months — can tell a load-bearing decision from an incidental one.

## Process

- One decision per record, numbered sequentially, named `NNNN-short-slug.md`.
- **New records are created with `Status: Proposed` and move to `Accepted` only on approval.** Completing a draft and editing an accepted record must not be a judgement call — an immutability rule that depends on judgement is not a rule.
- **Records are immutable once accepted.** A decision that changes is *superseded* by a new record; the original is marked `Superseded by ADR-NNNN` and left in place. Never edit an accepted record's reasoning.
- Keep them short. A record longer than about two screens is probably two decisions.
- "Architecturally significant" means: it constrains future change, is expensive to reverse, or would surprise a newcomer.
- Cite ADR numbers in code comments, pull requests and documents where the decision is relevant.

Format: **Context → Decision → Consequences (positive *and* negative) → Alternatives considered.** A record with no stated downside has not been thought through.

### Since the Phase 1 freeze

Phase 1 closed with ADR-0027. From that point, **new records are written only for implementation-driven discoveries or verified defects — not for speculative design expansion.**

The bar: something was *learned by building or measuring* that the design did not anticipate. ADR-0021 (a modelling error found while reviewing) and ADR-0027 (a gap found while writing the annotation guide) are the right shape. "We could also support X" is not, however reasonable X sounds.

This exists because a decision log that keeps growing during implementation stops being a record of load-bearing choices and becomes a design diary — and a future contributor can no longer tell which records matter.

## Index

| # | Decision | Status |
|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions in an ADR log | Accepted |
| [0002](0002-offline-first-deterministic-no-cloud-ai.md) | Offline-first, deterministic analysis; no cloud AI | Accepted |
| [0003](0003-two-layer-analysis.md) | Separate factual (Layer 1) and advisory (Layer 2) analysis | Accepted |
| [0004](0004-advisory-thresholds-who-searo.md) | Anchor advisory thresholds on WHO SEARO, not FSSAI | Accepted |
| [0005](0005-ins-number-as-additive-key.md) | Key the additive knowledge base on INS number | Accepted |
| [0006](0006-no-composite-health-score.md) | No composite health score in the MVP | Accepted |
| [0007](0007-clean-layering-pure-domain.md) | Clean layering with a pure domain and inward dependency rule | Accepted |
| [0008](0008-parser-lives-in-domain.md) | The parser belongs to the domain, not infrastructure | Accepted |
| [0009](0009-provenance-unifying-abstraction.md) | Provenance unifies confidence and explainability | Accepted |
| [0010](0010-confidence-lattice-s3-primary.md) | Confidence lattice; arithmetic invariants are the primary signal | Accepted |
| [0011](0011-explanations-structurally-mandatory.md) | An advisory finding without an explanation is unrepresentable | Accepted |
| [0012](0012-rules-as-data-json.md) | Rules, thresholds and content live in a JSON rule pack | Accepted |
| [0013](0013-category-agnostic-engine.md) | The parser and rule engine are category-agnostic | Accepted |
| [0014](0014-nutrients-typed-not-data-driven.md) | Nutrients are a typed closed set; adding one requires code | Accepted |
| [0015](0015-english-ocr-mvp.md) | English-only OCR for the MVP; detect and decline other scripts | Accepted |
| [0016](0016-no-internet-permission.md) | The MVP ships without the INTERNET permission | Accepted |
| [0017](0017-separate-code-and-content-licences.md) | Apache 2.0 for code, CC BY 4.0 for the knowledge base | Accepted |
| [0018](0018-reference-device.md) | Moto G34 5G (4 GB) is the performance reference device | Accepted |
| [0019](0019-ar1-concession-order.md) | If layering must be simplified, merge Application into Domain first | Accepted |
| [0020](0020-golden-corpus-first-class.md) | The golden corpus is a deliverable, not test scaffolding | Accepted |
| [0021](0021-unit-scale-is-a-unit-invariant.md) | Unit scale is an invariant of the Unit, not state on Quantity | Accepted |
| [0022](0022-version-as-semantic-value-object.md) | Version is a semantic value object, not an opaque string | Accepted |
| [0023](0023-measurement-integrity.md) | Parser accuracy measurement is not tunable | Accepted |
| [0024](0024-fifth-category-scope-containment.md) | The fifth validation category is architectural verification only | Accepted |
| [0025](0025-layer-split-release-boundary.md) | The Layer 1 / Layer 2 split is the release boundary | Accepted |
| [0026](0026-contingency-order-frozen.md) | The contingency order is frozen | Accepted |
| [0027](0027-qualified-quantities.md) | Quantities carry a qualifier and denote intervals | Accepted |

**Phase 1 is frozen as of 4 August 2026 (ADR-0001 … 0027).**

## Decisions deliberately *not* yet recorded

These are open questions, not decisions. They get an ADR when they are settled, not before — recording a guess as a decision is how an ADR log loses its authority.

| Question | Blocked on |
|---|---|
| Does the OCR engine expose usable per-element confidence? (Q2) | Phase 2 week-1 spike |
| State management approach for presentation (Q10) | Before UI work |
| Isolate strategy — per-scan or pooled worker (Q11) | Before performance tuning |
| Does the rule pack need build-time compilation? (Q12) | After first cold-start measurement |
| Corpus-calibrated tolerance bands for INV-07/08/10 (Q14) | Before the MVP gate |
| `StoredScan` serialisation format (Q15) | Before history is built |
