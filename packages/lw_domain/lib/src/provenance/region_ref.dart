/// Where on the label a value was found.
///
/// A **normalised bounding box**: coordinates are scaled integers in
/// `0 … `[coordinateScale]`, not pixels. The domain never holds image
/// dimensions or bitmaps (ADR-0007), and scaled integers keep the exact
/// arithmetic discipline of ADR-0021 rather than introducing floating point
/// into a value the golden corpus will compare.
///
/// Present only for extracted values. Derived and user-supplied values were
/// never on the label and so have no position (`DATA_MODEL.md` §3.1).
final class RegionRef {
  /// Creates a normalised bounding box.
  ///
  /// Throws [ArgumentError] when any coordinate falls outside
  /// `0 … `[coordinateScale], or when the box is inverted.
  RegionRef({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) {
    for (final int c in <int>[left, top, right, bottom]) {
      if (c < 0 || c > coordinateScale) {
        throw ArgumentError(
          'Coordinate $c is outside 0..$coordinateScale. Region references '
          'are normalised, not pixel values.',
        );
      }
    }
    if (right < left || bottom < top) {
      throw ArgumentError(
        'Inverted region: ($left,$top)-($right,$bottom). '
        'A degenerate box is permitted; an inverted one is a defect.',
      );
    }
  }

  /// The upper bound of the normalised coordinate space.
  ///
  /// A box spanning the full label runs `0 … 10000` on both axes, giving
  /// resolution of one part in ten thousand — finer than any OCR bounding box
  /// warrants, and independent of the captured image's size.
  static const int coordinateScale = 10000;

  /// Left edge, normalised.
  final int left;

  /// Top edge, normalised.
  final int top;

  /// Right edge, normalised. Never less than [left].
  final int right;

  /// Bottom edge, normalised. Never less than [top].
  final int bottom;

  /// Width in normalised units. Zero for a degenerate box.
  int get width => right - left;

  /// Height in normalised units. Zero for a degenerate box.
  int get height => bottom - top;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegionRef &&
          left == other.left &&
          top == other.top &&
          right == other.right &&
          bottom == other.bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'RegionRef($left,$top)-($right,$bottom)';
}
