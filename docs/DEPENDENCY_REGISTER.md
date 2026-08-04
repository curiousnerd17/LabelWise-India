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

*None registered yet.* Entries are added as Phase 2 proceeds.

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
