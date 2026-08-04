# ADR-0018 — Motorola Moto G34 5G (4 GB) is the performance reference device

- **Status:** Accepted
- **Date:** 2026-08-04

## Context

"Mid-range device" is not a measurable target. Every performance requirement is unverifiable until a specific handset is named, and measuring on a flagship development phone produces a comfortable, meaningless result.

## Decision

All performance and size requirements are measured against the **Moto G34 5G, 4 GB variant** — Snapdragon 695, 4 GB LPDDR4x, 6.5″ LCD at HD+ 720×1600, 50 MP main camera, Android 14. A measurement on any other handset is not evidence of compliance.

## Consequences

**Positive.** Performance requirements become falsifiable. Representative of the primary user's actual hardware.

**Negative.** A one-time hardware cost, accepted under CON-07.

**Three constraints follow directly:**

1. **Memory.** A 50 MP decode is ~200 MB uncompressed against ~1.5 GB available. Full-resolution bitmaps must never be materialised; decode with a bounded sample size, long edge ≤ 1600 px.
2. **Display.** At 720p, confidence indicators and the Layer 1/Layer 2 distinction must be legible without relying on colour. Design this visual language *on the device* from the first sketch, not as a late verification step.
3. **Compute.** Snapdragon 695 has no high-end NPU. Budget OCR in seconds, not milliseconds.
