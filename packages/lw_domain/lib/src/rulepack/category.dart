import 'package:lw_domain/src/invariants/invariant_id.dart';
import 'package:lw_domain/src/label/basis.dart';
import 'package:lw_domain/src/label/category_id.dart';
import 'package:lw_domain/src/rulepack/pack_ids.dart';

/// How much validation a category has had.
///
/// Not a quality ranking of the products — a statement about *our* evidence.
enum CategoryStatus {
  /// One of the four categories the corpus validates against (ADR-0013).
  priority,

  /// The fifth category, present to prove the architecture is data-driven and
  /// **explicitly not held to the accuracy bar** (ADR-0024, FR-CAT-06).
  verificationOnly,

  /// Supported, but outside the validated set.
  supported,
}

/// One product category record.
///
/// `DATA_MODEL.md` §7.10. **Category is an attribute, never a precondition**
/// (FR-CAT-02): nothing here gates the pipeline, and a product of unknown
/// category must still produce a complete result (FR-CAT-05).
final class Category {
  /// Records a category.
  Category({
    required this.categoryId,
    required this.nameMessageId,
    required this.defaultBasis,
    required this.status,
    List<InvariantId> inapplicableInvariants = const <InvariantId>[],
  }) : inapplicableInvariants =
            List<InvariantId>.unmodifiable(inapplicableInvariants);

  /// Stable key.
  final CategoryId categoryId;

  /// The display name's catalogue key — never the name itself (B8).
  final MessageId nameMessageId;

  /// The basis this category's panels usually declare.
  ///
  /// > **A presentation hint, never a substitute for the basis read from the
  /// > label.** A beverage declaring per-100 g is unusual, not wrong, and a
  /// > consumer that trusted this field over the panel would silently report
  /// > millilitres as grams.
  final Basis defaultBasis;

  /// How much validation this category has had.
  final CategoryStatus status;

  /// Invariants that do not apply to this category.
  ///
  /// **The FR-CAT-04 selector**, and the reason this record exists at all: it
  /// is how `INV-06` stops applying to beverages with no category branch
  /// anywhere in Dart (FR-CAT-01, FR-KB-11).
  ///
  /// The outcome is `INAPPLICABLE`, a first-class result the user can see
  /// (FR-CNF-04) — never a silent skip. In aggregate the two look identical and
  /// mean opposite things.
  final List<InvariantId> inapplicableInvariants;

  /// Whether [id] is inapplicable to this category.
  bool excludes(InvariantId id) => inapplicableInvariants.contains(id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          categoryId == other.categoryId &&
          nameMessageId == other.nameMessageId &&
          defaultBasis == other.defaultBasis &&
          status == other.status &&
          _sameInvariants(other.inapplicableInvariants);

  bool _sameInvariants(List<InvariantId> other) {
    if (inapplicableInvariants.length != other.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (inapplicableInvariants[i] != other[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        categoryId,
        nameMessageId,
        defaultBasis,
        status,
        Object.hashAll(inapplicableInvariants),
      );

  @override
  String toString() => 'Category($categoryId, ${status.name})';
}

/// Every category the pack declares.
///
/// Adding one is a data-only change (FR-CAT-03), which is what the fifth
/// category dry run exists to prove.
final class CategoryTable {
  /// Records the table, indexing by identifier.
  ///
  /// Throws [ArgumentError] on a duplicate `categoryId`.
  CategoryTable(List<Category> categories)
      : categories = List<Category>.unmodifiable(categories),
        _byId = _index(categories);

  static Map<CategoryId, Category> _index(List<Category> categories) {
    final Map<CategoryId, Category> index = <CategoryId, Category>{};
    for (final Category c in categories) {
      if (index.containsKey(c.categoryId)) {
        throw ArgumentError.value(
          c.categoryId.value,
          'categories',
          'Duplicate category identifier.',
        );
      }
      index[c.categoryId] = c;
    }
    return index;
  }

  /// Every category, in pack order.
  final List<Category> categories;

  final Map<CategoryId, Category> _byId;

  /// The category for [id], or null when the pack declares no such category.
  ///
  /// **Null is a normal answer, not a failure.** An unknown category is a
  /// supported state (FR-CAT-05); the caller carries on without one.
  Category? operator [](CategoryId id) => _byId[id];

  /// Whether [id] resolves.
  bool contains(CategoryId id) => _byId.containsKey(id);

  /// How many categories the pack declares.
  int get length => categories.length;

  @override
  String toString() => 'CategoryTable(${categories.length} categories)';
}
