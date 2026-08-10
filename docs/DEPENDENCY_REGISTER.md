# Dependency Register

| Field | Value |
|---|---|
| **Document** | `docs/DEPENDENCY_REGISTER.md` |
| **Version** | 1.0 |
| **Status** | Phase 2 bootstrap artefact |
| **Enforced by** | CI-13 (`tool/check_licences.sh`) |
| **Requirements** | NFR-MNT-02, CON-11, ADR-0017 |

---

## Rules

**Every third-party dependency requires an entry here before it is added to any `pubspec.yaml`.** CI-13 fails the build on an unregistered dependency — the register is a gate, not a record kept afterwards.

Each entry must state:

1. **What it does** and why we cannot reasonably do it ourselves.
2. **Licence** — must be Apache-2.0 compatible. **GPL, LGPL, AGPL, SSPL and BUSL are rejected at selection time** (CON-11).
3. **Maintenance signals** — publisher, release cadence, whether it is actively maintained.
4. **Exit path** — what replacing it would cost. A dependency with no exit path is a dependency we have not thought about.
5. **Layer** — a domain dependency requires a far stronger justification than a UI one. `lw_domain` accepts **none**.

### Standing constraints

- `lw_domain` declares zero dependencies (ADR-0007, CI-01). This is not negotiable and is not a stylistic preference — it is what makes device-free testing and the 90% coverage target achievable.
- No dependency may assume network access. The MVP ships without the `INTERNET` permission (ADR-0016).
- Prefer first-party Flutter and Google-maintained packages (§7.4 of `PROJECT_VISION.md`).
- Heavy or abandoned packages are rejected regardless of convenience.

---

## Registered dependencies

### Development-only

| Package | Version | Licence | Purpose | Layer | Exit path |
|---|---|---|---|---|---|
| `lints` | ^4.0.0 | BSD-3-Clause | Dart lint rule set | dev, all | Trivial — inline the rules |
| `test` | ^1.25.0 | BSD-3-Clause | Dart test runner | dev, all | None realistic; first-party |
| `coverage` | latest | BSD-3-Clause | Coverage reporting for CI-05 | dev, CI | Trivial |

Development dependencies do not ship in the APK and carry no runtime or licence-distribution risk.

### Runtime

| Package | Version | Licence | Purpose | Layer | Exit path |
|---|---|---|---|---|---|
| `crypto` | ^3.0.0 | BSD-3-Clause | SHA-256 for rule pack integrity verification (FR-ERR-06, FR-KB-09) | `lw_rulepack` only | Swap the one call site in `integrity.dart` |

#### `crypto` — full justification

| Aspect | Assessment |
|---|---|
| **What it does** | SHA-256 over the pack's content files, per the normative algorithm in §7.2 of `DATA_MODEL.md`. Nothing else in the package is used |
| **Why not ourselves** | We could — SHA-256 is ~140 lines of fully specified bit arithmetic. **Rejected deliberately.** A hand-rolled primitive that is subtly wrong still produces a plausible 64-hex digest and passes any test written against its own output. Cryptographic primitives are not where a solo project spends its novelty budget |
| **Licence** | BSD-3-Clause — Apache-2.0 compatible (CON-11) |
| **Maintenance** | Published by the Dart team under `dart.dev`; part of the core package ecosystem, released alongside the SDK. Not an abandonment risk |
| **Layer** | `lw_rulepack`. **Not `lw_domain`**, which keeps its zero-dependency guarantee (CI-01, ADR-0007) untouched. `lw_rulepack` exists precisely so the domain never learns what JSON — or a digest — is |
| **Size** | Pure Dart, no native code, no platform channels. Negligible against NFR-SIZ-01 |
| **Network** | None. Compatible with ADR-0016 |
| **Exit path** | One call site behind `RulePackIntegrity`. Replacing it is an afternoon, and the NIST test vectors in the suite would catch a bad substitution |

---

## Anticipated dependencies

Not yet approved. Recorded so the licence and exit-path questions are answered **before** selection, not after.

### OCR — expected: `google_mlkit_text_recognition`

| Aspect | Assessment |
|---|---|
| **Purpose** | On-device text recognition. Building this ourselves is out of the question. |
| **Licence** | Must be verified as Apache-2.0 compatible before adoption. **Check the underlying ML Kit terms as well as the Flutter plugin wrapper** — they are separate. |
| **Layer** | `lw_infrastructure` only, behind port `P-OCR` |
| **Size impact** | ~4 MB bundled per script; ~260 KB unbundled. Counts against the 40 MB budget (NFR-SIZ-01, NFR-SIZ-03). |
| **Network** | **Must be verified to work with no `INTERNET` permission.** The bundled model variant is required; unbundled downloads models at runtime and is incompatible with ADR-0016. |
| **Exit path** | Adapter rewrite behind `P-OCR`. This is the single most important reason B2 exists (R10). |
| **Risk** | Highest-consequence dependency in the project. |

> **⚠ Architect's Note — verify the no-network constraint during the Q2 spike, not later.**
>
> ADR-0016 commits the MVP to shipping without the `INTERNET` permission, which makes offline operation OS-enforced. If the chosen OCR package requires network access to fetch a model on first use — as the *unbundled* variant does — that commitment breaks, and it breaks at runtime on a user's device rather than in CI.
>
> **Fold this check into the Q2 spike:** install a release build on the reference device with networking disabled, clear app data, and confirm first-run OCR works. It costs ten minutes and it validates an ADR.

### Camera — expected: `camera` (Flutter first-party)

| Aspect | Assessment |
|---|---|
| **Purpose** | Camera capture with preview |
| **Licence** | BSD-3-Clause — compatible |
| **Layer** | `lw_infrastructure` only, behind port `P-IMG` |
| **Constraint** | Must support bounded-resolution decode. A full 50 MP decode is ~200 MB against ~1.5 GB available on the reference device (ADR-0018). |
| **Exit path** | Adapter rewrite; `image_picker` as a fallback |

### Persistence — undecided (Q15)

| Aspect | Assessment |
|---|---|
| **Purpose** | Local scan history |
| **Constraint** | App-private storage only (NFR-SEC-03); no network path may exist (FR-HIS-02) |
| **Layer** | `lw_infrastructure` only, behind port `P-STORE` |
| **Note** | Plain JSON files may be sufficient. Prefer no dependency over a small one; a database is not automatically the right answer for a list of scans. |

### Property testing — undecided (Q17)

| Aspect | Assessment |
|---|---|
| **Purpose** | PT-01…16 (§3 of `TEST_STRATEGY.md`) |
| **Layer** | dev-only, `lw_domain` tests |
| **Constraint** | Must be Apache-2.0 compatible. Dart's property-testing ecosystem is thin — if nothing suitable exists, hand-rolled generators are acceptable and preferable to a poorly maintained package. |

---

## Rejected

| Package | Reason |
|---|---|
| *(none yet)* | Rejections are recorded here with reasons, so the same option is not re-evaluated from scratch later. |
