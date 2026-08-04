# LabelWise India

**Understand what is actually in the packet — offline, on your phone, with no account and no cloud.**

LabelWise India reads the nutrition panel and ingredient list on Indian packaged food, entirely on-device, and explains them in plain language. It uses deterministic rules, not cloud AI. It has no backend, no login, no analytics, and — in this release — no internet permission at all.

> ### Disclaimer
>
> LabelWise India provides educational and informational guidance based on information declared on product labels and publicly available nutrition guidance. It does not provide medical advice, diagnose health conditions, or determine allergen safety. Always consult a qualified healthcare professional for medical or dietary decisions. If OCR confidence is low or information is missing, verify the product label directly before making decisions.

---

## Status

**Phase 1 complete — architecture and planning. Implementation has not started.**

The full engineering document set is in [`docs/`](docs/). Nothing here is code yet, deliberately: the design was settled first, and the reasoning is preserved in an immutable [decision log](docs/adr/README.md).

| Release | Contents | Status |
|---|---|---|
| **v0.1 — Factual** | Capture, OCR, parser, confidence, correction, Layer 1 analysis, history | Not started |
| **v0.2 — Advisory** | Layer 2 nutrition guidance with cited explanations | Not started |

---

## What it does

**Reads the label.** On-device OCR plus a deterministic parser that turns a photographed nutrition panel into typed, unit-aware values.

**Normalises the numbers.** Everything expressed per 100 g, per serve *and* per pack, so a small declared serving size cannot flatter the figures. Serving-size reconciliation is a first-class feature, because manipulating the serve is the most effective legal deception on packaged food.

**Identifies additives by INS number.** Indian regulation requires additives to be declared as class title plus INS number — "Preservative (INS 211)". That is precise and completely opaque to a shopper. LabelWise resolves the number to a name, a function, and a plain-language description.

**Tells you what it is unsure about.** Every extracted value carries a visible confidence level. A field we could not read is reported as unread — never guessed, and never quietly filled in.

**Explains itself.** Every piece of nutrition guidance states the rule that produced it, the threshold applied, the margin, and the published source it came from.

## What it deliberately does not do

No cloud AI. No barcode database. No accounts or sync. No composite "health score". No allergen-safety determination. No personalised medical advice. No ads, subscriptions or affiliate links — ever.

Each of these is a recorded decision with stated reasoning, not an omission. See the [decision log](docs/adr/README.md).

---

## How it works

```
Photo ─▶ On-device OCR ─▶ Parser (8 stages) ─▶ Confidence ─▶ Layer 1: facts
                                                          └─▶ Layer 2: guidance
```

**Layer 1 restates what the label declares** and the arithmetic that Indian regulation defines. It contains no judgement.

**Layer 2 interprets those facts** against published nutrition evidence — WHO South-East Asia Region nutrient profile model, supplemented by ICMR-NIN guidance — and says clearly that it is guidance.

The separation is deliberate. India has no finalised regulatory nutrient-profile model: the 2022 draft Indian Nutrition Rating was never operationalised and FSSAI has moved to withdraw it. Facts can be stated with authority; interpretation cannot, and the product should not pretend otherwise.

---

## Repository layout

| Path | Contents | Licence |
|---|---|---|
| `packages/lw_domain/` | Domain core — parser, confidence, rules, analysis. **Zero dependencies.** | Apache 2.0 |
| `packages/lw_ports/` | Contracts the outside world must satisfy | Apache 2.0 |
| `packages/lw_application/` | Use cases | Apache 2.0 |
| `packages/lw_infrastructure/` | Adapters: OCR, camera, storage | Apache 2.0 |
| `packages/lw_rulepack/` | Rule pack schema binding | Apache 2.0 |
| `app/` | Flutter presentation layer | Apache 2.0 |
| `rulepack/` | **Knowledge base** — thresholds, additives, citations, messages | **CC BY 4.0** |
| `corpus/` | Golden corpus — real labels with hand-verified ground truth | CC BY 4.0 |
| `docs/` | Engineering documentation and decision log | Apache 2.0 |

**Two licences, deliberately.** Code is Apache 2.0. The curated knowledge base is CC BY 4.0, so it can be reused and cited as a standalone dataset. See [`NOTICE`](NOTICE) and [ADR-0017](docs/adr/0017-separate-code-and-content-licences.md).

---

## Contributing

The easiest and most valuable contributions require **no Dart at all**. The rule pack is plain JSON, validated in CI:

- **Add a label synonym** — spotted a nutrition panel wording the parser misses? Add it to `rulepack/nutrients/synonyms.json`.
- **Add an additive record** — an INS number we do not yet identify goes in `rulepack/additives/ins.json`, with a citation.
- **Add a corpus entry** — photograph a label, transcribe it from the packet, and follow the [Annotation Guide](docs/ANNOTATION_GUIDE.md).

Every threshold and additive claim must cite a source in `rulepack/sources.json`. An uncited claim fails the build; this is not a formality.

Before contributing code, read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). The dependency rules are enforced by CI, not convention — the domain package declares zero dependencies and a Flutter import there is a build failure.

---

## Documentation

| Document | Purpose |
|---|---|
| [Project Vision](docs/PROJECT_VISION.md) | Mission, scope, design principles, risks |
| [Requirements](docs/REQUIREMENTS.md) | 181 verifiable requirements with traceability |
| [Architecture](docs/ARCHITECTURE.md) | Boundaries, dependency rules, parser pipeline, data flow |
| [Data Model](docs/DATA_MODEL.md) | Types, confidence lattice, rule pack schema |
| [Test Strategy](docs/TEST_STRATEGY.md) | Accuracy definition, corpus methodology, CI gates |
| [Roadmap](docs/ROADMAP.md) | Phases, gates, readiness checklist |
| [Annotation Guide](docs/ANNOTATION_GUIDE.md) | How corpus ground truth is produced |
| [Decision Log](docs/adr/README.md) | 26 immutable architecture decision records |

---

## Accuracy

Parser accuracy will be published here — overall and per category — as measured against the golden corpus, **whatever the number says**.

Two metrics are reported, because they are not equally important:

- **Field Accuracy** — how many declared fields we read correctly.
- **Critical Error Rate** — how often we return a *wrong value* rather than admitting we could not read it.

The second is the one that governs whether a release ships. A parser that admits its failures is trustworthy; one that confidently reports wrong sodium values is not. Comparison is **exact match** — tolerance never enters accuracy measurement.

---

## Privacy

Photographs stay on your device. There is no telemetry, no analytics SDK, no crash reporting that transmits data, and no account.

This release does not declare the `INTERNET` permission, which means offline operation is enforced by Android rather than promised by us. You can verify that yourself in the app listing.

---

## Licence

Code: [Apache License 2.0](LICENSE) · Knowledge base: [CC BY 4.0](rulepack/LICENSE) · See [`NOTICE`](NOTICE).
