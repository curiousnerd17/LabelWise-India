import 'package:lw_domain/src/rulepack/pack_ids.dart';

/// The resolved message text for one locale.
///
/// `DATA_MODEL.md` §7.11. **This is B8's other half.** The domain emits
/// [MessageId]s; this is where an identifier becomes words, and it is loaded
/// from the pack rather than written in Dart.
///
/// > **⚠ On MI-06.** "No domain type contains display text" forbids display
/// > text *in a type's definition* — a literal in `lib/`, which is what CI-10
/// > greps for and what makes localisation a content problem rather than an
/// > engineering one. It does not forbid a runtime container of loaded content;
/// > something must hold the catalogue after it is read, and a `Map` of
/// > `String` to `String` outside the type system would be worse in every way
/// > this project cares about.
/// >
/// > The line that matters is upstream of here and unmoved: **no domain type
/// > that models a label, a finding or a confidence may hold text.** Those
/// > carry identifiers, and identifiers resolve here, at the presentation
/// > boundary.
final class MessageCatalogue {
  /// Records a catalogue.
  ///
  /// Throws [ArgumentError] when a non-English catalogue is unreviewed:
  /// FR-LOC-04 and R11 make human review a shipping condition for Hindi, and
  /// the type refuses to represent the state the requirement forbids.
  MessageCatalogue({
    required this.locale,
    required this.reviewed,
    required Map<MessageId, String> messages,
    this.reviewedBy,
  }) : _messages = Map<MessageId, String>.unmodifiable(messages) {
    if (locale != 'en' && !reviewed) {
      throw ArgumentError.value(
        locale,
        'reviewed',
        'A non-English catalogue must be reviewed before it ships.',
      );
    }
  }

  /// The language tag — `en` or `hi`.
  final String locale;

  /// Whether a human has reviewed this catalogue (FR-LOC-04).
  final bool reviewed;

  /// Who reviewed it, when recorded.
  final String? reviewedBy;

  final Map<MessageId, String> _messages;

  /// The text for [id], or null when this catalogue has no entry.
  ///
  /// > **Null must be reported, never papered over.** Do not fall back to the
  /// > identifier and do not fall back to English. Showing a user
  /// > `msg.additive.ins-322` is a visible defect that gets fixed; silently
  /// > substituting another language is an invisible one that ships.
  String? resolve(MessageId id) => _messages[id];

  /// Whether [id] resolves in this catalogue.
  bool contains(MessageId id) => _messages.containsKey(id);

  /// Every identifier this catalogue defines.
  Iterable<MessageId> get ids => _messages.keys;

  /// How many messages the catalogue holds.
  int get length => _messages.length;

  @override
  String toString() =>
      'MessageCatalogue($locale, ${_messages.length} messages)';
}
