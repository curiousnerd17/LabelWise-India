# ADR-0023 — Parser accuracy measurement is not tunable

- **Status:** Accepted
- **Date:** 2026-08-04
- **Related:** ADR-0020 (golden corpus), ADR-0010 (confidence)

## Context

The project's headline quality claim is a published parser accuracy figure. Any measurement that can be adjusted without changing the thing being measured will eventually be adjusted — not through bad faith, but through the ordinary pressure of a disappointing number arriving late in a schedule.

Three specific routes to a flattering number exist, and all three are quiet: widening a tolerance, letting silent wrong answers hide inside an aggregate percentage, and editing ground truth that "looked ambiguous anyway".

## Decision

Three rules, permanent. They are recorded together because they defend a single property — that the number means what it says — and because they will always be cited together.

**1. Correctness is exact match, permanently.** Label reading is transcription, not measurement: the label prints a symbol and we either read it or we did not. **Tolerance must never enter parser accuracy measurement.** Tolerance bands exist only for invariant evaluation, where they test the *manufacturer's* independently rounded arithmetic. The two must remain structurally separate and must never share a configuration value — tolerance lives in the rule pack, accuracy comparison lives in the test harness.

**2. Critical Error Rate is the primary release-quality metric.** Where it conflicts with Field Accuracy, **the error rate takes precedence**. A parser at 85% accuracy with 15% misses and no errors is trustworthy; one at 90% with 10% errors is dangerous. Misses obey honesty-over-completeness; errors violate it.

**3. The golden corpus is append-only, and ground truth is never modified to satisfy parser behaviour.** Corrections are versioned, require a recorded reason citing re-examination of the *physical packet*, and may never be bundled with a parser change. A commit touching both a parser and a ground-truth value is rejected on sight.

## Consequences

**Positive.** The published figure cannot be improved except by improving the parser. Silent wrong answers cannot hide behind an aggregate. The corpus cannot drift into certifying the parser against itself.

**Negative.** The reported number will be lower, and sometimes uncomfortably so, than a tolerant metric would give. Exact match makes some legitimate-looking near-misses count as failures. Append-only means genuine annotation errors persist visibly in history rather than disappearing.

Those costs are the mechanism, not a side effect. A metric that cannot embarrass you is not measuring anything.

## Alternatives considered

**Tolerance-based accuracy** — rejected: makes the headline number tunable with no code change and nothing appearing wrong.
**Single aggregate accuracy figure** — rejected: allows a high error rate to hide behind a low miss rate, which inverts the product's stated priorities.
**Editable ground truth with review** — rejected: review by the same person who wrote the parser is not review.
