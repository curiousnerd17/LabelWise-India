# LabelWise India — Golden Corpus Annotation Guide

| Field | Value |
|---|---|
| **Document** | `docs/ANNOTATION_GUIDE.md` |
| **Version** | 1.2 |
| **Status** | **Approved** — Phase 2 Day 1 deliverable |
| **Author** | Chief Software Architect |
| **Date** | 4 August 2026 |
| **Parents** | `TEST_STRATEGY.md` §5, `DATA_MODEL.md` v1.3, ADR-0020, ADR-0023, ADR-0027 |
| **Applies to** | Every entry in `corpus/` |

---

## 0. Why This Document Exists

Fifty-five labels annotated by four slightly different implicit conventions is not a corpus — it is noise with a schema. Because the corpus is **append-only** (ADR-0023), inconsistent early annotations persist permanently and cannot be quietly tidied later.

This guide fixes the conventions **before label 9**. Everything in it is a rule, not a suggestion. Where it is silent, stop and extend the guide rather than deciding in the moment; a decision made once at the desk becomes a convention, and a convention nobody wrote down becomes an inconsistency nobody can find.

---

## 1. The Three Rules

### Rule 1 — Transcribe from the physical packet

**Ground truth is read off the packet in your hand. Never from the photograph. Never from OCR output.**

Annotating from the image inherits the image's ambiguity: an unclear digit becomes a guess, and the parser is then measured against a guess. Annotating from OCR output is circular and measures nothing at all.

If you cannot read a field on the physical packet under good light, it is `ILLEGIBLE_ON_PACKET` (§4.6) — not a guess, and not a value borrowed from the manufacturer's website.

### Rule 2 — Record what is printed, not what is meant

If the packet prints `2.50 g`, record `2.50 g`. If it prints `Energy 478 kCal`, record the value as printed and the unit as printed. Do not normalise, tidy, correct an obvious typo, or convert. Normalisation is the parser's job and is measured; performing it during annotation destroys the thing being measured.

The one exception is structural: values are recorded in the canonical field/basis structure of §3. That is transcription into a form, not alteration of content.

### Rule 3 — Ground truth is never edited to make a test pass

If the parser disagrees with an annotation, the parser is wrong until re-examination of the **physical packet** proves otherwise. Corrections require §6 procedure. A commit that changes both a parser and a ground-truth value is rejected on sight (ADR-0023).

---

## 2. Corpus Entry Structure

One directory per entry:

```
corpus/entries/<entry-id>/
├─ label.jpg           primary image, captured on the reference device
├─ ocr.json            recorded OCR output for this image
├─ truth.json          hand-transcribed ground truth
└─ meta.json           sourcing, difficulty tags, annotation history
```

`<entry-id>` is `<category>-<nnn>`, e.g. `biscuits-004`, `beverages-002`. Assigned sequentially, never reused.

---

## 3. What To Annotate

### 3.1 Critical fields — always

Every critical field gets an entry, including those the label does not declare.

`ENERGY` · `PROTEIN` · `CARBOHYDRATE` · `TOTAL_SUGARS` · `ADDED_SUGARS` · `TOTAL_FAT` · `SATURATED_FAT` · `TRANS_FAT` · `SODIUM` · `servingSize` · `servingsPerPack` · `netQuantity`

### 3.2 Non-critical nutrients — when declared

`DIETARY_FIBRE` · `CHOLESTEROL` · `MONOUNSATURATED_FAT` · `POLYUNSATURATED_FAT`

Recorded when present. Not counted in accuracy metrics.

### 3.3 Bases

For every nutrient, record each basis the label declares, and mark the others `NOT_DECLARED`. Do **not** compute a missing basis yourself — deriving per-serve from per-100 g is the parser's job, and pre-computing it in ground truth would make a derivation test pass by construction.

### 3.4 Ingredients

Ordered list exactly as printed, preserving:

- **Declaration order** — legally meaningful (descending by weight)
- **Nesting** — parenthetical sub-ingredients stay attached to their parent
- **INS numbers** — recorded as integers, with the class title as printed
- **Original text** — the raw string for each entry, before any interpretation

---

## 4. Canonical Representations

These are the cases that produce silent inconsistency. Each has exactly one correct annotation.

### 4.1 Explicit zero

| Printed | Annotate as |
|---|---|
| `0`, `0 g`, `0.0 g`, `Nil`, `NIL` | value `0`, unit as printed (default `g`), `declaredAs: "ZERO"` |

A declared zero is a **declaration**, not an absence. It counts as present for accuracy purposes, and the parser is expected to extract it.

### 4.2 Below-threshold declarations

| Printed | Annotate as |
|---|---|
| `< 0.5 g`, `<0.5g`, `Less than 0.5 g` | value `0.5`, unit `g`, `qualifier: "LESS_THAN"` |

Common on trans fat. **Never annotate as `0`** — that discards information the label deliberately provided — and never as a bare `0.5`, which overstates.

**Q19 is resolved and approved (ADR-0027).** The qualifier is part of the value model: `EXACT` (default) | `LESS_THAN` | `GREATER_THAN` | `APPROXIMATELY`. A qualified quantity denotes an interval, exact-match comparison includes the qualifier, invariants treat it as a bound, and no code path may coerce it to a point value.

Two consequences for annotation:

- **Annotate the qualifier as printed.** `< 0.5 g` is `LESS_THAN 0.5 g`. Never `0`, never a bare `0.5`.
- **A qualifier is not a defect.** A label declaring `< 0.5 g` is being precise about its imprecision. The parser is expected to read it exactly, and reading it as `0.5` counts as an **Error** in accuracy measurement, not a near-miss.
- **Omit `qualifier` entirely for ordinary values.** An absent qualifier means `EXACT`. Writing `"qualifier": "EXACT"` fails CI-16 — the canonical form is normative so that annotations serialise identically regardless of who or what wrote them (ADR-0027 decision 5).

### 4.3 Trace and allergen language

| Printed | Annotate as |
|---|---|
| `Traces`, `May contain traces of X` | **Not a nutrition value.** Record in `meta.json` notes only. |

Allergen statements are explicitly out of scope (FR-L2-10). They are never nutrition ground truth.

### 4.4 Approximations

| Printed | Annotate as |
|---|---|
| `About 4 servings`, `Approx. 4 servings`, `~4` | value `4`, `qualifier: "APPROXIMATELY"` |

Recorded with `qualifier: "APPROXIMATELY"`. The interval half-width is rule pack data (`approximationDeltas`), which is what lets INV-10 absorb an approximate serving count without a special case.

### 4.5 Not declared

| Situation | Annotate as |
|---|---|
| The label genuinely does not carry this field | `NOT_DECLARED` |

This is correct behaviour by the manufacturer in some cases and a compliance gap in others. Either way it is the label's state, not our failure, and it is excluded from the accuracy denominator (§4.4 of `TEST_STRATEGY.md`).

### 4.6 Illegible on the physical packet

| Situation | Annotate as |
|---|---|
| Print is genuinely unreadable on the packet itself, under good light | `ILLEGIBLE_ON_PACKET` |

**Excluded from the accuracy denominator.** We cannot fairly measure a parser against a value no human can read.

If **three or more critical fields** are `ILLEGIBLE_ON_PACKET`, the entry is unsuitable and should be replaced with a fresh purchase of the same product. Record the rejection in `meta.json` rather than deleting the entry — a systematically unreadable product is itself a finding.

### 4.7 Units as printed

Record the unit exactly: `g`, `gm`, `gms`, `mg`, `kcal`, `kCal`, `Kcal`, `kJ`, `ml`. Unit normalisation is a measured parser behaviour (FR-PAR-06); normalising during annotation would make that test vacuous.

### 4.8 Energy declared in both kcal and kJ

Record both, as separate basis-qualified values. The parser's conversion behaviour (FR-PAR-07) is then testable against a real dual declaration.

### 4.9 Multi-component packs

Instant noodles typically carry a noodle cake plus a seasoning sachet. Three patterns occur:

| Pattern | Annotation |
|---|---|
| Single combined panel | Annotate normally; `components: ["combined"]` |
| Separate panels per component | Annotate each component separately under `components` |
| Panel for one component only | Annotate what is declared; note the omission in `meta.json` |

**Never sum components yourself.** If the label does not declare a total, there is no total in ground truth.

### 4.10 Serve equals the whole pack

Common on beverages: a 250 ml bottle declaring per 100 ml and per bottle. Annotate `servingSize` as the declared serve (`250 ml`) and `servingsPerPack` as `1` **only if the label says so**. If the label does not state servings per pack, it is `NOT_DECLARED` — do not infer it.

### 4.11 Two-column panels

Record which physical column each basis came from in `meta.json`. Column-to-basis association is a measured S4/S5 behaviour, and knowing the physical truth makes layout regressions diagnosable.

---

## 5. Annotation Workflow

1. **Purchase** the product. Keep the packet until annotation and re-annotation are both complete.
2. **Photograph** on the reference device (Moto G34 5G) in conditions matching the entry's intended difficulty tags.
3. **Record OCR output** for the image and store as `ocr.json`.
4. **Transcribe** every field per §3 and §4, with the packet in hand under good light. Do not open the photograph during this step.
5. **Record sourcing and difficulty tags** in `meta.json`.
6. **Sign** the entry: annotator, date, guide version, corpus schema version.

Realistic pace is 20–30 minutes per entry done properly. At 2–3 entries per working day alongside engineering, 55 entries takes roughly four weeks — which is why the content track starts on day 1 (`ROADMAP.md` §3).

### 5.1 Difficulty tags

At least half of each category's entries must carry one or more:

`metallised` · `curved` · `low_light` · `poor_print` · `two_column` · `multi_component` · `small_text` · `glossy` · `creased`

A corpus of flat, well-lit cardboard reports a flattering accuracy that predicts nothing about a chip packet in a shop.

---

## 6. Quality Control

### 6.1 Re-annotation

Re-annotate a random **20%** of entries **at least two weeks** after first annotation, without reference to the original, with the physical packet in hand.

- Target self-agreement: **≥ 98%** of critical fields.
- Below that, the **guide is under-specified** — extend §4 rather than resolving to be more careful. Carefulness does not transmit to a future contributor; a written rule does.
- Every disagreement is investigated and its resolution recorded.

### 6.2 Correction procedure

Corrections are **append-only**. Never overwrite a value.

1. Re-examine the **physical packet**. Not the image, not parser output.
2. Append a correction record to `meta.json` with: date, field, old value, new value, and the reason.
3. Commit as a **standalone corpus-correction commit**. Never bundle with a code change.
4. If the packet is no longer available, the correction cannot be made. Mark the field `DISPUTED` and exclude it from metrics.

`DISPUTED` exists so that an unresolvable doubt is visible rather than silently resolved in the parser's favour.

---

## 7. Set Assignment

| Set | Rule |
|---|---|
| **Development** (40) | Default for new entries. Used for iteration, debugging, calibration. |
| **Holdout** (10) | Assigned at creation and **never moved**. Never opened for debugging. Measured only at phase gates. |
| **Fifth-category** (5, beverages) | Architectural verification only. Not held to the accuracy bar (ADR-0024). |

Once an entry is in the holdout, looking at its parse output outside a gate contaminates it. If that happens, say so and move it to development — a contaminated holdout reported as clean is worse than no holdout.

---

## 8. Question Raised By This Guide — Resolved

| # | Question | Outcome |
|---|---|---|
| **Q19** | Should extracted quantities carry a qualifier, and how should bounds propagate? | ✅ **Approved** — ADR-0027; `DATA_MODEL.md` v1.2 §2.2a, §4.3a, §6.3a |

Raising this was the point of writing the guide before the parser. The gap was invisible from the requirements and the architecture, and became obvious the moment someone had to write down what `< 0.5 g` means. Two pages of annotation rules surfaced a model defect that would otherwise have been discovered by a parser silently reporting zero trans fat.
