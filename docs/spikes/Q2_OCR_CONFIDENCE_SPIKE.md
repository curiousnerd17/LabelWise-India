# Spike Q2 — Does the OCR engine expose usable per-element confidence?

| Field | Value |
|---|---|
| **Document** | `docs/spikes/Q2_OCR_CONFIDENCE_SPIKE.md` |
| **Status** | Not started — **Phase 2, week 1** |
| **Timebox** | **1 working day. Hard stop.** |
| **Blocks** | FR-CNF-02, FR-CNF-03; §4.2 of `DATA_MODEL.md`; §7.3 of `TEST_STRATEGY.md` |
| **Tests** | Assumption A2 |

---

## Question

`DATA_MODEL.md` §4.2 models three confidence signals. **S1 — the OCR engine's own per-element confidence — is assumed to exist and is unverified.**

Two sub-questions, and the second matters more:

1. **Availability.** Does the engine expose a per-element or per-line confidence value through the Flutter binding at all?
2. **Calibration.** If it does, does it *predict correctness*? A confidence value that is high on both correct and incorrect reads is worse than no value, because it invites the parser to trust it.

A third question rides along, cheaply:

3. **Offline model loading.** Does a release build perform OCR on first run with networking fully disabled? ADR-0016 commits the MVP to shipping without the `INTERNET` permission. The unbundled ML Kit variant fetches models at runtime and would break that commitment — on a user's device, not in CI.

---

## Why this is timeboxed to one day

The confidence design does **not** depend on the answer. ADR-0010 already places **S3 (arithmetic invariants) primary, S2 secondary, S1 as an optional refinement**. The shipping baseline is S2 + S3, and §7.3 of `TEST_STRATEGY.md` requires that configuration to meet the calibration targets on its own.

So this spike cannot block implementation. It determines whether S1 is worth wiring in at all — a refinement question, not a foundation question.

> **⚠ Architect's Note — the deeper reason S1 is demoted is worth restating, because it is counter-intuitive.**
>
> The failure that actually harms a user is a *confidently misread digit*: the engine reads `3` as `8`, reports high character confidence, and the app displays 850 mg of sodium instead of 350 mg. S1 is blind to exactly the error class that matters most.
>
> S3 catches it, because 850 mg will not reconcile with the per-serve column or the Atwater estimate. That is why the arithmetic is primary and the engine's self-report is a bonus.

---

## Method

Run on the **reference device** (Moto G34 5G, 4 GB — ADR-0018). Results from a development machine or emulator do not answer the question.

### Step 1 — Availability *(~1 hour)*

Recognise text in three corpus label images. Inspect the returned structure and record:

| Question | Record |
|---|---|
| Is a confidence value present on any returned element? | yes / no |
| At what granularity — block, line, element, symbol? | |
| What is its range and type? | |
| Is it ever null or absent for some elements? | |
| Does the Flutter plugin surface it, or does the native API expose it while the binding drops it? | |

**If unavailable:** stop. Record the finding, close Q2, and implement the S2 + S3 model. Total spike cost: one hour.

### Step 2 — Calibration *(~4 hours, only if Step 1 succeeds)*

Availability is not usefulness. Using the first **8 annotated corpus labels** (`ROADMAP.md` §4.1 deliverable 2.10):

1. Run OCR and capture every element with its confidence value.
2. Manually mark each element as correctly or incorrectly recognised, against ground truth transcribed from the physical packet.
3. Bucket by confidence decile and compute correctness per bucket.

**S1 is useful only if correctness rises monotonically with confidence, with meaningful separation between the top and bottom buckets.**

| Outcome | Decision |
|---|---|
| Clear monotonic separation | Adopt S1 as a refinement. Record weights in `rulepack/rules/confidence.json`. |
| Weak or flat relationship | **Reject S1.** Ship S2 + S3. Record why. |
| High confidence on known-wrong reads | **Reject S1 emphatically** — it would actively mislead the assignment table. |

Eight labels is a small sample and cannot settle this finely. That is acceptable: the decision being made is adopt-or-ignore a bonus signal, not a foundation.

### Step 3 — Offline model verification *(~15 minutes)*

1. Build a release APK with the bundled model variant.
2. Install on the reference device.
3. **Enable airplane mode. Clear app data.**
4. Launch and run a scan.

| Outcome | Consequence |
|---|---|
| OCR works | ADR-0016 holds. Record as verified. |
| OCR fails or hangs | **Blocking.** The bundled variant is mandatory; if it cannot work offline, either the package is unsuitable or ADR-0016 needs revisiting via a new ADR. Escalate immediately — this is more important than the confidence question. |

---

## Deliverables

1. **A written result appended to this file** — findings, decision, and reasoning. Recorded whether the answer is interesting or dull.
2. **An ADR** if S1 is adopted or rejected. Q2 leaves the "not yet recorded" list in `docs/adr/README.md` either way.
3. **Confidence assignment entries** in `rulepack/rules/confidence.json` reflecting the decision.
4. **Offline verification recorded** against ADR-0016.

---

## Stopping rule

**One working day. Hard stop.**

If Step 2 is inconclusive at the timebox, the answer is **reject S1 and ship S2 + S3**. An inconclusive signal is not a signal, and a spike that runs long is a spike that has quietly become implementation.

---

## Result

*To be completed during Phase 2, week 1.*

| Field | Value |
|---|---|
| Date run | |
| Device | |
| S1 available? | |
| S1 granularity | |
| S1 calibrated? | |
| **Decision** | |
| ADR raised | |
| Offline OCR verified (Step 3)? | |
| Notes | |
