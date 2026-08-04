/// How much trust an extracted field warrants.
///
/// A **totally ordered bounded lattice** whose meet is the minimum
/// (`DATA_MODEL.md` §4.1, ADR-0010). Exactly four levels, and deliberately no
/// numeric percentage: a number would imply a precision the underlying signals
/// do not possess (FR-CNF-10).
///
/// The governing property, which [meet] guarantees and property tests enforce:
/// **a derived value can never be more confident than its least confident
/// input.**
enum Confidence {
  /// Not present on the label, or not found. Nothing to trust.
  absent,

  /// Poor recognition, heuristic-only parse, or a failed invariant.
  /// The user should check this by hand.
  low,

  /// Recognised with minor uncertainty or via a normalising rule, with all
  /// applicable invariants satisfied. Probably right.
  medium,

  /// Clean recognition, exact parse-rule match, all applicable invariants
  /// satisfied. Trust this.
  high;

  /// The lattice meet — the lesser of this and [other].
  ///
  /// Meet is commutative, associative and idempotent, so propagation order
  /// cannot affect the result. That is what makes FR-CNF-06's determinism
  /// provable by property test rather than merely intended.
  Confidence meet(Confidence other) => index <= other.index ? this : other;

  /// Whether this level is at least [other].
  bool isAtLeast(Confidence other) => index >= other.index;

  /// The next level down, or [absent] when already at the bottom.
  ///
  /// Used where a derivation is itself approximate and should cost one level
  /// beyond the meet of its inputs.
  Confidence get downgraded =>
      this == Confidence.absent ? this : Confidence.values[index - 1];

  /// The meet of every level in [levels], or [absent] when empty.
  ///
  /// An empty input yields [absent] because a value derived from nothing is a
  /// value with nothing to trust — not a value that is trusted by default.
  static Confidence meetAll(Iterable<Confidence> levels) {
    if (levels.isEmpty) {
      return Confidence.absent;
    }
    return levels.reduce(
      (Confidence acc, Confidence next) => acc.meet(next),
    );
  }
}
