import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  MessageCatalogue catalogue({
    String locale = 'en',
    bool reviewed = true,
    Map<MessageId, String>? messages,
  }) =>
      MessageCatalogue(
        locale: locale,
        reviewed: reviewed,
        messages: messages ??
            <MessageId, String>{
              MessageId('msg.category.biscuits'): 'Biscuits',
              MessageId('msg.additive.ins-100'):
                  'A yellow colour taken from turmeric.',
            },
      );

  group('MessageCatalogue — B8, where identity becomes words', () {
    test('FR-LOC-01 a known identifier resolves to its text', () {
      expect(
          catalogue().resolve(MessageId('msg.category.biscuits')), 'Biscuits');
      expect(catalogue().contains(MessageId('msg.additive.ins-100')), isTrue);
      expect(catalogue().length, 2);
    });

    test('FR-LOC-01 an unknown identifier resolves to null', () {
      // Null must be reported by the caller, never papered over. Falling back
      // to the identifier shows a defect that gets fixed; falling back to
      // another language hides one that ships.
      expect(catalogue().resolve(MessageId('msg.nothing.here')), isNull);
      expect(catalogue().contains(MessageId('msg.nothing.here')), isFalse);
    });

    test('the catalogue exposes the identifiers it defines', () {
      expect(
        catalogue().ids.map((MessageId m) => m.value).toList()..sort(),
        <String>['msg.additive.ins-100', 'msg.category.biscuits'],
      );
    });
  });

  group('MessageCatalogue — FR-LOC-04, review is a shipping condition', () {
    test('R11 an unreviewed non-English catalogue cannot be constructed', () {
      // The type refuses to represent the state the requirement forbids,
      // rather than trusting a check somewhere downstream.
      expect(
        () => catalogue(locale: 'hi', reviewed: false),
        throwsArgumentError,
      );
    });

    test('FR-LOC-03 a reviewed non-English catalogue is accepted', () {
      final MessageCatalogue hi = MessageCatalogue(
        locale: 'hi',
        reviewed: true,
        reviewedBy: 'A reviewer',
        messages: <MessageId, String>{
          MessageId('msg.category.biscuits'): 'बिस्कुट',
        },
      );
      expect(hi.locale, 'hi');
      expect(hi.reviewedBy, 'A reviewer');
      expect(hi.resolve(MessageId('msg.category.biscuits')), 'बिस्कुट');
    });

    test('English is exempt because it is the source language', () {
      // Nothing to review against — the English catalogue IS the original.
      expect(catalogue(reviewed: false).locale, 'en');
    });
  });

  group('MessageCatalogue — immutability', () {
    test('FR-KB-01 the map is unmodifiable once built', () {
      final Map<MessageId, String> supplied = <MessageId, String>{
        MessageId('msg.a'): 'A',
      };
      final MessageCatalogue c = catalogue(messages: supplied);
      // Mutating the caller's map must not reach inside the catalogue.
      supplied[MessageId('msg.b')] = 'B';
      expect(c.length, 1);
      expect(c.resolve(MessageId('msg.b')), isNull);
    });

    test('an empty catalogue is representable and resolves nothing', () {
      final MessageCatalogue c = catalogue(messages: <MessageId, String>{});
      expect(c.length, 0);
      expect(c.resolve(MessageId('msg.a')), isNull);
    });

    test('toString reports the locale and size, never the text', () {
      expect(catalogue().toString(), contains('en'));
      expect(catalogue().toString(), contains('2'));
      expect(catalogue().toString(), isNot(contains('Biscuits')));
    });
  });
}
