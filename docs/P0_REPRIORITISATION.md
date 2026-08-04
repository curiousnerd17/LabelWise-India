# P0 Re-Prioritisation Pass

| Field | Value |
|---|---|
| **Document** | `docs/P0_REPRIORITISATION.md` |
| **Version** | 1.0 |
| **Status** | **Approved and applied** — `REQUIREMENTS.md` v1.3 |
| **Deliverable** | `ROADMAP.md` §4.1 item 2.7 |
| **Amends** | `REQUIREMENTS.md` §0.2 |

---

## 1. The Problem

`REQUIREMENTS.md` carries **152 of 181 requirements at P0** — 84%. I raised this in §0.2 of that document as a weakness in my own work: when almost everything is MVP-blocking, the priority field carries no scheduling information. Its purpose is to tell you what gives when the schedule slips, and a list this uniformly P0 answers "nothing", which is not a usable answer.

My original suggestion was to demote polish requirements — framing guidance, correction niceties, accessibility refinements. **Checking that list against the document showed it was wrong: every requirement I named was already P1.** The P0 set contains almost no polish. That is worth stating plainly, because it changes the diagnosis.

---

## 2. A Better Diagnosis

The P0 set is not padded with nice-to-haves. It is large because the product's principles genuinely are non-negotiable: a system that is dishonest about confidence, or that emits unexplained advice, is not a lesser LabelWise India but a different and worse product.

What was actually wrong is subtler. **`REQUIREMENTS.md` was written before the release split existed.** It priorities against a single monolithic MVP. Under ADR-0025 there are now two releases, and "MVP-blocking" is no longer a single question — it is two.

The correct fix is therefore not demotion. It is **re-scoping priority by release**.

> **⚠ Architect's Note — this is a better outcome than the one I proposed, and the difference is worth naming.**
>
> Demoting requirements to hit a target percentage would have been priority theatre: the number improves, nothing real changes, and the demoted requirements get built anyway because they were always necessary.
>
> Scoping by release changes something real. It says *when* each requirement blocks, which is the information the priority field was supposed to carry all along. The percentage falls as a consequence rather than as a goal.

---

## 3. Proposal — Release-Scoped Priority

Replace the single priority column with release scoping:

| Level | Meaning |
|---|---|
| **P0-v0.1** | Blocks the Factual release |
| **P0-v0.2** | Blocks the Advisory release; not required for v0.1 |
| **P1** | Expected in its release unless explicitly deferred with a reason |
| **P2** | Post-MVP; specified because it constrains the architecture |

### 3.1 Requirements moving from P0 to P0-v0.2

Twenty-two requirements are Layer 2 or advisory-explanation concerns. Under ADR-0025 these do not block v0.1.

| Group | Requirements | Count |
|---|---|---|
| Layer 2 advisory engine | FR-L2-01 … 07, FR-L2-09 … 14 | 13 |
| Advisory explanations | FR-EXP-01 … 08, FR-EXP-11 | 9 |

**FR-EXP-09 remains P0-v0.1.** Layer 1 findings must carry their derivation — the arithmetic and inputs used — from the first release. Explainability is a principle (P3), not a Layer 2 feature, and v0.1 must be able to show its working even though it is not yet giving advice.

**FR-L2-08 (severity ranking) is already P1** and stays there.

### 3.2 Requirements moving from P0 to P1

Five, on the grounds that v0.1 is genuinely usable without them and each has an honest degraded behaviour:

| ID | Requirement | Degraded behaviour if deferred |
|---|---|---|
| FR-HIS-04 | Stored scan records rule pack version | v0.1 ships one pack version; the field is recorded but nothing yet reads it |
| FR-CAP-09 | Degrade to gallery import if camera permission denied | Gallery import (FR-CAP-02) already exists as a separate path |
| FR-KB-13 | All message text in the catalogue | Enforced anyway by CI-10 and FR-LOC-01; the requirement is redundant at P0 |
| NFR-CMP-02 | Functions on a 3 GB device | The reference device is 4 GB (ADR-0018). 3 GB is a broader claim we cannot yet verify. |
| NFR-SIZ-03 | Only required OCR script models bundled | Only one script ships in v0.1, so the constraint is vacuous until Devanagari arrives |

**NFR-CMP-02 deserves comment.** Demoting it is not weakening a commitment — it is refusing to make a claim we have no device to test. Asserting 3 GB support while measuring only on 4 GB hardware would be the kind of unverified statement this project exists to avoid.

### 3.3 The result

| Scope | Count | Share |
|---|---|---|
| **P0-v0.1** | **128** | 70% |
| **P0-v0.2** | 22 | 12% |
| P1 | 32 | 17% |
| P2 | 2 | 1% |

70% for the v0.1 release — at the top of the 60–70% band, and honestly arrived at. Counts include the three requirements added by Q19: FR-PAR-18 and FR-CNF-14 are v0.1; FR-L2-14 is v0.2.

---

## 4. What Was Deliberately Not Demoted

Naming these matters as much as the demotions, because they are what a future schedule squeeze will reach for first.

| Group | Why it stays P0-v0.1 |
|---|---|
| **FR-CNF-01 … 13** (12) | Confidence is a first-class principle (P2) and the disclaimer instructs users to act on it. Demoting confidence would make the approved disclaimer text untrue. |
| **FR-CAT-01 … 08** (8) | Category-agnosticism verified late is category-agnosticism not achieved. These are cheap to satisfy while building and expensive to retrofit. |
| **FR-ERR-01 … 06** (6) | Honest failure handling *is* the product (P1). A version without it is not a smaller LabelWise, it is a different one. |
| **NFR-PRV-01 … 06** (6) | Privacy retrofitted is privacy not delivered. |
| **NFR-OFF-01 … 04** (4) | Offline is the product's premise. |
| **NFR-TST-01 … 07** (7) | Testing demoted is the quality bar demoted, which contradicts `PROJECT_VISION.md` §7.6. |
| **FR-PAR-15** | The accuracy bar. Non-negotiable under ADR-0023. |

---

## 5. Consequential Changes

If approved:

1. `REQUIREMENTS.md` §0.2 gains the release-scoped priority scheme; the priority column is updated for the 26 requirements listed in §3.
2. `TEST_STRATEGY.md` CI-15 asserts coverage of **P0-v0.1** during v0.1 development, widening to include P0-v0.2 when Phase 7 begins.
3. `ROADMAP.md` §13 gate conditions are read against P0-v0.1 for the v0.1 release.
4. A new ADR records release-scoped prioritisation, since it changes how every requirement is read.

---

## 6. Approval

| Item | Status |
|---|---|
| Diagnosis corrected — the P0 set is not padded | ✅ §2 |
| Release-scoped priority proposed | ✅ Approved and applied |
| 22 requirements identified as P0-v0.2 | ✅ §3.1 |
| 5 requirements identified as P1 | ✅ §3.2 |
| Non-negotiable groups named and defended | ✅ §4 |
