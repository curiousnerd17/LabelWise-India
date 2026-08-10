import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  group('SourceId — MI-05 begins at construction', () {
    test('FR-KB-04 a well-formed registry key is accepted', () {
      expect(SourceId('src.fssai.labelling.2020').value,
          'src.fssai.labelling.2020');
      expect(SourceId('src.who-searo').value, 'src.who-searo');
      expect(SourceId('src.icmr_nin.2020').value, 'src.icmr_nin.2020');
    });

    test('MI-05 a malformed key is refused, not carried', () {
      // An identifier that cannot exist cannot dangle. Rejecting here is what
      // makes the build-time reference check meaningful at all.
      expect(() => SourceId('fssai.2020'), throwsFormatException);
      expect(() => SourceId('src.'), throwsFormatException);
      expect(() => SourceId('SRC.fssai'), throwsFormatException,
          reason: 'upper case is not the pack convention');
      expect(() => SourceId('src.fssai 2020'), throwsFormatException);
      expect(() => SourceId(''), throwsFormatException);
    });

    test('isValid answers without throwing', () {
      expect(SourceId.isValid('src.a'), isTrue);
      expect(SourceId.isValid('rule.a'), isFalse);
    });

    test('P4 compares by value', () {
      expect(SourceId('src.a'), SourceId('src.a'));
      expect(SourceId('src.a').hashCode, SourceId('src.a').hashCode);
      expect(SourceId('src.a'), isNot(SourceId('src.b')));
    });
  });

  group('MessageId — B8, identity is not text', () {
    test('FR-LOC-01 a well-formed catalogue key is accepted', () {
      expect(MessageId('msg.additive.ins-322').value, 'msg.additive.ins-322');
      expect(MessageId('msg.category.instant-noodles').value,
          'msg.category.instant-noodles');
    });

    test('FR-LOC-01 display text cannot be smuggled in as an identifier', () {
      // The whole point of the type: a sentence is not a message id, so a
      // literal cannot reach a domain field by being renamed.
      expect(() => MessageId('High in sodium'), throwsFormatException);
      expect(() => MessageId('msg.'), throwsFormatException);
      expect(() => MessageId('message.foo'), throwsFormatException);
    });

    test('P4 compares by value', () {
      expect(MessageId('msg.a'), MessageId('msg.a'));
      expect(MessageId('msg.a').hashCode, MessageId('msg.a').hashCode);
      expect(MessageId('msg.a'), isNot(MessageId('msg.b')));
    });
  });

  group('ConstantId — a third kind, deliberately not interchangeable', () {
    test('NFR-MNT-06 a gazetted constant key is accepted', () {
      expect(ConstantId('const.rda.sodium').value, 'const.rda.sodium');
    });

    test('a source or message key is not a constant key', () {
      // Three String-typed identifiers would be accepted in any order by any
      // function taking all three. Three types cannot be.
      expect(() => ConstantId('src.fssai'), throwsFormatException);
      expect(() => ConstantId('msg.foo'), throwsFormatException);
    });

    test('P4 compares by value', () {
      expect(ConstantId('const.a'), ConstantId('const.a'));
      expect(ConstantId('const.a').hashCode, ConstantId('const.a').hashCode);
      expect(ConstantId('const.a'), isNot(ConstantId('const.b')));
    });

    test('the three identifier types never compare equal to one another', () {
      expect(SourceId('src.a'), isNot(MessageId('msg.a')));
      expect(ConstantId('const.a'), isNot(SourceId('src.a')));
    });
  });

  group('identifier patterns match the shipped schema', () {
    test('every pattern accepts dot, hyphen, underscore and digits', () {
      // common.schema.json permits [a-z0-9_.-] for all three. A domain type
      // stricter than the schema would reject a pack CI had passed.
      expect(SourceId.isValid('src.a_b-c.9'), isTrue);
      expect(MessageId.isValid('msg.a_b-c.9'), isTrue);
      expect(ConstantId.isValid('const.a_b-c.9'), isTrue);
    });

    test('toString is the identifier itself', () {
      expect(SourceId('src.a').toString(), 'src.a');
      expect(MessageId('msg.a').toString(), 'msg.a');
      expect(ConstantId('const.a').toString(), 'const.a');
    });
  });
}
