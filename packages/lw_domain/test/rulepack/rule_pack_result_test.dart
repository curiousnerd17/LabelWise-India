import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  const RulePackFailure corrupt = RulePackFailure(
    kind: RulePackFailureKind.integrityMismatch,
    file: 'manifest.json',
  );

  group('RulePackFailure — identity, never display text', () {
    test('FR-ERR-01 each kind is specific enough to act on', () {
      // A single generic failure would make an actionable message impossible.
      // "Corrupt" and "your build is too old" need different remedies.
      expect(RulePackFailureKind.values, hasLength(9));
      expect(
        RulePackFailureKind.values.map((RulePackFailureKind k) => k.name),
        containsAll(<String>[
          'packMissing',
          'malformedJson',
          'schemaViolation',
          'integrityMismatch',
          'schemaVersionUnsupported',
          'appVersionTooOld',
          'danglingReference',
          'duplicateKey',
          'unrepresentableValue',
        ]),
      );
    });

    test('malformed and schema-invalid are distinct kinds', () {
      // "Unreadable" and "readable and wrong" send a contributor to different
      // places. Conflating them sends them to the wrong one.
      expect(RulePackFailureKind.malformedJson,
          isNot(RulePackFailureKind.schemaViolation));
    });

    test('a record-local failure points at the record', () {
      const RulePackFailure f = RulePackFailure(
        kind: RulePackFailureKind.duplicateKey,
        file: 'additives/ins.json',
        pointer: 'additives/3/insNumber',
        detail: 'Duplicate INS number 322.',
      );
      expect(f.pointer, 'additives/3/insNumber');
      expect(f.toString(), contains('additives/3/insNumber'));
    });

    test('a whole-file failure carries no pointer', () {
      expect(corrupt.pointer, isNull);
      expect(corrupt.toString(), contains('manifest.json'));
      expect(corrupt.toString(), isNot(contains('at ')));
    });

    test('P4 compares by value', () {
      expect(
        corrupt,
        const RulePackFailure(
          kind: RulePackFailureKind.integrityMismatch,
          file: 'manifest.json',
        ),
      );
      expect(
        corrupt.hashCode,
        const RulePackFailure(
          kind: RulePackFailureKind.integrityMismatch,
          file: 'manifest.json',
        ).hashCode,
      );
      expect(
        corrupt,
        isNot(const RulePackFailure(
          kind: RulePackFailureKind.packMissing,
          file: 'manifest.json',
        )),
      );
    });

    test('every field participates in equality', () {
      const RulePackFailure base = RulePackFailure(
        kind: RulePackFailureKind.schemaViolation,
        file: 'a.json',
        pointer: 'p',
        detail: 'd',
      );
      expect(
          base,
          isNot(const RulePackFailure(
              kind: RulePackFailureKind.schemaViolation,
              file: 'b.json',
              pointer: 'p',
              detail: 'd')));
      expect(
          base,
          isNot(const RulePackFailure(
              kind: RulePackFailureKind.schemaViolation,
              file: 'a.json',
              pointer: 'q',
              detail: 'd')));
      expect(
          base,
          isNot(const RulePackFailure(
              kind: RulePackFailureKind.schemaViolation,
              file: 'a.json',
              pointer: 'p',
              detail: 'e')));
    });
  });

  group('RulePackResult — failure is a value, not an exception', () {
    test('a load that succeeded exposes its value and no failure', () {
      const RulePackResult<int> r = RulePackLoaded<int>(7);
      expect(r.isSuccess, isTrue);
      expect(r.valueOrNull, 7);
      expect(r.failureOrNull, isNull);
    });

    test('a load that was rejected exposes its failure and no value', () {
      const RulePackResult<int> r = RulePackRejected<int>(corrupt);
      expect(r.isSuccess, isFalse);
      expect(r.valueOrNull, isNull);
      expect(r.failureOrNull, corrupt);
    });

    test('FR-ERR-06 there is no partial load to mistake for a result', () {
      // A rejected load has no value at all. Falling back to unvalidated data
      // is exactly what the requirement forbids, and the type cannot express
      // it: valueOrNull is null whenever isSuccess is false.
      const RulePackResult<int> r = RulePackRejected<int>(corrupt);
      expect(r.valueOrNull, isNull);
    });

    test('the union is sealed, so a switch must handle both', () {
      // Exhaustiveness is a compile-time guarantee for switch expressions.
      // This exercises both arms rather than asserting the guarantee.
      String describe(RulePackResult<int> r) => switch (r) {
            RulePackLoaded<int>(value: final int v) => 'loaded $v',
            RulePackRejected<int>(failure: final RulePackFailure f) =>
              'rejected ${f.kind.name}',
          };
      expect(describe(const RulePackLoaded<int>(3)), 'loaded 3');
      expect(describe(const RulePackRejected<int>(corrupt)),
          'rejected integrityMismatch');
    });

    test('P4 compares by value', () {
      expect(const RulePackLoaded<int>(3), const RulePackLoaded<int>(3));
      expect(const RulePackLoaded<int>(3).hashCode,
          const RulePackLoaded<int>(3).hashCode);
      expect(const RulePackLoaded<int>(3), isNot(const RulePackLoaded<int>(4)));
      expect(const RulePackRejected<int>(corrupt),
          const RulePackRejected<int>(corrupt));
      expect(const RulePackRejected<int>(corrupt).hashCode,
          const RulePackRejected<int>(corrupt).hashCode);
    });

    test('a loaded result never equals a rejected one', () {
      expect(const RulePackLoaded<int>(3),
          isNot(const RulePackRejected<int>(corrupt)));
    });

    test('toString names the outcome', () {
      expect(const RulePackLoaded<int>(3).toString(), contains('Loaded'));
      expect(const RulePackRejected<int>(corrupt).toString(),
          contains('Rejected'));
    });
  });
}
