import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Unit — scale is a property of the unit (ADR-0021)', () {
    test('ADR-0021 every unit fixes its own tracked precision', () {
      expect(Unit.gram.scale, 100, reason: 'grams tracked to 0.01 g');
      expect(Unit.milligram.scale, 10, reason: 'milligrams tracked to 0.1 mg');
      expect(Unit.microgram.scale, 1, reason: 'micrograms tracked to 1 ug');
    });

    test('ADR-0021 base-unit increments make mass conversion exact', () {
      // 0.01 g == 10 000 ug, 0.1 mg == 100 ug, 1 ug == 1 ug.
      expect(Unit.gram.baseUnitsPerIncrement, 10000);
      expect(Unit.milligram.baseUnitsPerIncrement, 100);
      expect(Unit.microgram.baseUnitsPerIncrement, 1);
    });

    test('ADR-0021 energy increments are integers in millijoules', () {
      // 1 kcal == 4.184 kJ exactly, so 0.1 kcal == 418 400 mJ and
      // 0.1 kJ == 100 000 mJ. Both integral, so kcal/kJ comparison is exact.
      expect(Unit.kilocalorie.baseUnitsPerIncrement, 418400);
      expect(Unit.kilojoule.baseUnitsPerIncrement, 100000);
    });
  });

  group('Unit — conversion is closed within a dimension', () {
    test('FR-PAR-06 units of the same dimension are convertible', () {
      expect(Unit.gram.isConvertibleTo(Unit.milligram), isTrue);
      expect(Unit.kilocalorie.isConvertibleTo(Unit.kilojoule), isTrue);
    });

    test('FR-PAR-06 units of different dimensions are not convertible', () {
      expect(Unit.gram.isConvertibleTo(Unit.millilitre), isFalse);
      expect(Unit.percent.isConvertibleTo(Unit.count), isFalse,
          reason: 'a percentage is not a serving count');
    });

    test('FR-PAR-06 finerOf picks the smaller increment', () {
      expect(Unit.gram.finerOf(Unit.milligram), Unit.milligram);
      expect(Unit.microgram.finerOf(Unit.gram), Unit.microgram);
      expect(Unit.kilocalorie.finerOf(Unit.kilojoule), Unit.kilojoule);
    });

    test('FR-PAR-06 finerOf rejects a cross-dimension pair', () {
      expect(
        () => Unit.gram.finerOf(Unit.millilitre),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
