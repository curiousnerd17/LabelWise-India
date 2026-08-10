import 'dart:convert';

import 'package:lw_domain/lw_domain.dart';
import 'package:lw_rulepack/src/json_view.dart';
import 'package:test/test.dart';

void main() {
  JsonView view(String json) => JsonView(jsonDecode(json), 'a.json');

  RulePackFailureKind kindOf(void Function() body) {
    try {
      body();
    } on DecodeException catch (e) {
      return e.kind;
    }
    fail('expected a DecodeException');
  }

  String pointerOf(void Function() body) {
    try {
      body();
    } on DecodeException catch (e) {
      return e.pointer;
    }
    fail('expected a DecodeException');
  }

  group('JsonView — positions, so a contributor can find their typo', () {
    test('a nested failure names its full path', () {
      final JsonView v = view('{"additives":[{"insNumber":"x"}]}');
      expect(
        pointerOf(() =>
            v.required('additives').elements.first.required('insNumber').asInt),
        'a.json/additives/0/insNumber',
      );
    });

    test('a missing property names the property', () {
      final JsonView v = view('{"a":1}');
      expect(pointerOf(() => v.required('b')), 'a.json');
      expect(
          kindOf(() => v.required('b')), RulePackFailureKind.schemaViolation);
    });

    test('elements are numbered from zero', () {
      final JsonView v = view('{"xs":[1,2,3]}');
      expect(
        v.required('xs').elements.map((JsonView e) => e.pointer),
        <String>['a.json/xs/0', 'a.json/xs/1', 'a.json/xs/2'],
      );
    });
  });

  group('JsonView — typed accessors refuse rather than coerce', () {
    test('an object, array, string and boolean read correctly', () {
      final JsonView v = view('{"o":{},"a":[],"s":"x","b":true}');
      expect(v.required('o').asObject, isEmpty);
      expect(v.required('a').asArray, isEmpty);
      expect(v.required('s').asString, 'x');
      expect(v.required('b').asBool, isTrue);
    });

    test('MI-11 a fractional number is not truncated to an integer', () {
      // Truncation would silently change a scaled quantity by up to a whole
      // increment — exactly the class of error the model excludes.
      final JsonView v = view('{"n":1.5}');
      expect(kindOf(() => v.required('n').asInt),
          RulePackFailureKind.schemaViolation);
    });

    test('an integral double reads as an integer', () {
      // JSON has one number type; 20000.0 and 20000 must mean the same thing.
      expect(view('{"n":20000.0}').required('n').asInt, 20000);
    });

    test('a string is never coerced to a number', () {
      final JsonView v = view('{"n":"20000"}');
      expect(kindOf(() => v.required('n').asInt),
          RulePackFailureKind.schemaViolation);
    });

    test('the failure says what was expected and what was found', () {
      try {
        view('{"n":[]}').required('n').asInt;
        fail('expected a DecodeException');
      } on DecodeException catch (e) {
        expect(e.detail, contains('integer'));
        expect(e.detail, contains('array'));
      }
    });

    test('null is described as null, not as a missing type', () {
      try {
        view('{"n":null}').required('n').asString;
        fail('expected a DecodeException');
      } on DecodeException catch (e) {
        expect(e.detail, contains('null'));
      }
    });

    test('asObject and asArray refuse the wrong shape', () {
      // Every decoder starts by asserting a shape. A scalar where an object is
      // expected is the commonest hand-edit mistake in a nested pack file, and
      // it must name the position rather than fail somewhere downstream.
      final JsonView v = view('{"o":3,"a":{}}');
      expect(kindOf(() => v.required('o').asObject),
          RulePackFailureKind.schemaViolation);
      expect(kindOf(() => v.required('a').asArray),
          RulePackFailureKind.schemaViolation);
      expect(pointerOf(() => v.required('a').asArray), 'a.json/a');
    });

    test('asBool refuses a string that merely looks boolean', () {
      // "true" is not true. Coercing it would let `reviewed:"false"` ship an
      // unreviewed catalogue (FR-LOC-04) on a technicality.
      final JsonView v = view('{"b":"true"}');
      expect(kindOf(() => v.required('b').asBool),
          RulePackFailureKind.schemaViolation);
    });

    test('asNum refuses a non-number', () {
      // The one accessor that admits a fraction, used for relativeFraction and
      // severityWeight. It still refuses a string.
      final JsonView v = view('{"n":"0.15"}');
      expect(kindOf(() => v.required('n').asNum),
          RulePackFailureKind.schemaViolation);
      expect(view('{"n":0.15}').required('n').asNum, 0.15);
    });

    test('a non-string-keyed map is still described as an object', () {
      // jsonDecode never produces one, so this arm guards a JsonView built
      // directly — which the decoders' own unit tests do. Describing it as
      // "an unexpected value" would be misleading about what was found.
      const JsonView v = JsonView(<int, int>{1: 2}, 'a.json');
      expect(kindOf(() => v.asString), RulePackFailureKind.schemaViolation);
      try {
        v.asString;
        fail('expected a DecodeException');
      } on DecodeException catch (e) {
        expect(e.detail, contains('object'));
      }
    });
  });

  group('JsonView — closed sets stay closed', () {
    test('a known member maps to its domain value', () {
      expect(
        view('{"u":"GRAM"}').required('u').asEnum(<String, Unit>{
          'GRAM': Unit.gram,
        }),
        Unit.gram,
      );
    });

    test('an unknown member is refused and the permitted set is listed', () {
      try {
        view('{"u":"STONE"}').required('u').asEnum(<String, Unit>{
          'GRAM': Unit.gram,
          'MILLIGRAM': Unit.milligram,
        });
        fail('expected a DecodeException');
      } on DecodeException catch (e) {
        expect(e.detail, contains('STONE'));
        expect(e.detail, contains('GRAM'));
        expect(e.detail, contains('MILLIGRAM'));
      }
    });

    test('the permitted set is listed in a stable order', () {
      // A diagnostic that reorders between runs is a diagnostic nobody trusts.
      String detail() {
        try {
          view('{"u":"X"}').required('u').asEnum(<String, int>{
            'B': 1,
            'A': 2,
            'C': 3,
          });
        } on DecodeException catch (e) {
          return e.detail;
        }
        return '';
      }

      expect(detail(), detail());
      expect(detail(), contains('A, B, C'));
    });
  });

  group('JsonView — identifiers', () {
    test('a well-formed identifier is built', () {
      expect(
        view('{"id":"src.a"}').required('id').asId(SourceId.new).value,
        'src.a',
      );
    });

    test('a malformed identifier becomes a positioned failure, not a throw',
        () {
      // The value objects throw FormatException, which is right for a
      // programming error and wrong for a malformed pack. This is where one
      // becomes the other.
      final JsonView v = view('{"id":"nope"}');
      expect(kindOf(() => v.required('id').asId(SourceId.new)),
          RulePackFailureKind.schemaViolation);
      expect(pointerOf(() => v.required('id').asId(SourceId.new)), 'a.json/id');
    });
  });

  group('JsonView — presence and explicit rejection', () {
    test('has distinguishes absent from present-and-null', () {
      final JsonView v = view('{"a":1,"b":null}');
      expect(v.has('a'), isTrue);
      expect(v.has('b'), isFalse,
          reason: 'an explicit null is treated as absent, matching the schema '
              'where every optional field is simply omitted');
      expect(v.has('c'), isFalse);
    });

    test('reject raises the kind the caller names', () {
      final JsonView v = view('{"a":1}');
      expect(
        kindOf(() => v
            .required('a')
            .reject(RulePackFailureKind.unrepresentableValue, 'because')),
        RulePackFailureKind.unrepresentableValue,
      );
    });

    test('toString names the position', () {
      expect(view('{}').toString(), contains('a.json'));
    });
  });
}
