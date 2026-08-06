/// The reconciliation of a pack's declared serving figures — **Layer 1**.
///
/// `DATA_MODEL.md` §6.2 calls this "the product's signature Layer 1 output":
/// it compares the declared serve against the net quantity and the servings
/// per pack, and reports whether they tell a consistent story. Serving-size
/// manipulation is the primary legal deception on Indian packaging
/// (`PROJECT_VISION.md` §2.1), which is why it earns a type of its own.
///
/// **Declared here as a contract with no implementation.** `ParsedLabel` must
/// name the type to give `ServingInfo.reconciliation` compile-time safety, but
/// the parser can never produce a value: §6.2's shape needs whole-pack
/// nutrient values that only Layer 1 computes, and Layer 1 consumes the
/// `ParsedLabel` this sits inside. Requiring a value would close that cycle,
/// which is what `DATA_MODEL.md` v1.6 made optional. Naming the *type* costs
/// nothing — a type reference is not a dependency on a value.
///
/// **`abstract interface`, not `sealed`.** Dart confines the subtypes of a
/// sealed class to its own library, so sealing this would make it permanently
/// unimplementable from the analysis layer — the opposite of the intent. An
/// interface is open to exactly one future implementor and closed to
/// extension by anyone who has not thought about §6.2's four fields.
///
/// The implementation belongs in this directory, and arrives with the Layer 1
/// engine (`ROADMAP.md` §4.3 item 4.4). Until then no value of this type
/// exists anywhere in the codebase, and `ServingInfo.reconciliation` is null.
abstract interface class ServingReconciliation {}
