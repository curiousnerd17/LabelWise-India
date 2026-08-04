import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Version — semantic ordering (ADR-0022)', () {
    test('FR-KB-02 1.10.0 follows 1.9.0', () {
      // The defect a string version would produce: lexicographically
      // "1.10.0" < "1.9.0", which silently mis-gates rule pack loading.
      expect(Version(1, 10, 0) > Version(1, 9, 0), isTrue);
    });

    test('FR-KB-02 ordering compares major, then minor, then patch', () {
      expect(Version(2, 0, 0) > Version(1, 99, 99), isTrue);
      expect(Version(1, 2, 0) > Version(1, 1, 99), isTrue);
      expect(Version(1, 1, 2) > Version(1, 1, 1), isTrue);
    });

    test('FR-KB-02 equal versions compare equal', () {
      expect(Version(1, 2, 3), Version(1, 2, 3));
      expect(Version(1, 2, 3) <= Version(1, 2, 3), isTrue);
      expect(Version(1, 2, 3) >= Version(1, 2, 3), isTrue);
    });

    test('FR-KB-02 parse accepts major.minor.patch', () {
      expect(Version.parse('1.10.3'), Version(1, 10, 3));
    });

    test('FR-KB-03 a malformed version fails at parse time', () {
      // Malformed versions fail in CI rather than at load time on a device.
      expect(() => Version.parse('1.2'), throwsFormatException);
      expect(() => Version.parse('1.2.x'), throwsFormatException);
      expect(() => Version(1, -1, 0), throwsA(isA<ArgumentError>()));
    });
  });

  group('Version — rule pack compatibility (FR-ERR-06)', () {
    test('FR-KB-02 a matching major at or above the minimum is compatible', () {
      expect(
        Version(1, 4, 0)
            .isCompatibleWith(supportedMajor: 1, minimum: Version(1, 2, 0)),
        isTrue,
      );
    });

    test('FR-ERR-06 a major mismatch is refused, not best-effort loaded', () {
      expect(
        Version(2, 0, 0)
            .isCompatibleWith(supportedMajor: 1, minimum: Version(1, 0, 0)),
        isFalse,
      );
    });

    test('FR-ERR-06 a pack below the minimum is refused', () {
      expect(
        Version(1, 1, 0)
            .isCompatibleWith(supportedMajor: 1, minimum: Version(1, 2, 0)),
        isFalse,
      );
    });
  });
}
