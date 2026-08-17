import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

/// The marker table is the whole of S5b's vocabulary, so what it refuses
/// matters as much as what it matches. A wrong serving size scales every
/// per-serve figure downstream.
void main() {
  final ServingMarkerTable table = ServingMarkerTable.defaults;

  ServingField? fieldFor(String line) => table.strongestMatch(line)?.field;
  ParseStrength? strengthFor(String line) =>
      table.strongestMatch(line)?.strength;

  group('ServingMarker — a value type stored case-folded', () {
    test('text is lower-cased so callers need not normalise', () {
      final ServingMarker m = ServingMarker(
        text: 'Serving Size',
        field: ServingField.servingSize,
        strength: ParseStrength.exact,
      );
      expect(m.text, 'serving size');
      expect(m.field, ServingField.servingSize);
      expect(m.strength, ParseStrength.exact);
    });

    test('P4 compares by value across every field', () {
      ServingMarker marker({
        String text = 'net wt',
        ServingField field = ServingField.netQuantity,
        ParseStrength strength = ParseStrength.normalised,
      }) =>
          ServingMarker(text: text, field: field, strength: strength);

      expect(marker(), marker());
      expect(marker().hashCode, marker().hashCode);
      expect(marker(), isNot(marker(text: 'net qty')));
      expect(marker(), isNot(marker(field: ServingField.servingSize)));
      expect(marker(), isNot(marker(strength: ParseStrength.exact)));
    });

    test('toString names the wording and what it means', () {
      final ServingMarker m = ServingMarker(
        text: 'net wt',
        field: ServingField.netQuantity,
        strength: ParseStrength.normalised,
      );
      expect(m.toString(), contains('net wt'));
      expect(m.toString(), contains('netQuantity'));
    });
  });

  group('the specified vocabulary — the regulation\'s own terms', () {
    test('FSSAI 2020 serving size matches at EXACT', () {
      expect(fieldFor('Serving Size: 30 g'), ServingField.servingSize);
      expect(strengthFor('Serving Size: 30 g'), ParseStrength.exact);
    });

    test('FSSAI 2020 servings per pack matches at EXACT', () {
      expect(fieldFor('Servings per pack: 4'), ServingField.servingsPerPack);
      expect(strengthFor('Servings per pack: 4'), ParseStrength.exact);
    });

    test('Legal Metrology 2011 net quantity matches at EXACT', () {
      expect(fieldFor('Net Quantity: 120 g'), ServingField.netQuantity);
      expect(strengthFor('Net Quantity: 120 g'), ParseStrength.exact);
    });

    test('matching is case-insensitive', () {
      // S1 collapses whitespace but does not fold case.
      expect(fieldFor('SERVING SIZE 30 G'), ServingField.servingSize);
      expect(fieldFor('net quantity 120 g'), ServingField.netQuantity);
    });
  });

  group('compatibility aliases — convention, at reduced strength', () {
    test('printed variants resolve to the right field', () {
      for (final (String line, ServingField field) in <(String, ServingField)>[
        ('Serve size 30 g', ServingField.servingSize),
        ('Servings per package: 4', ServingField.servingsPerPack),
        ('Servings per container: 4', ServingField.servingsPerPack),
        ('Number of servings: 4', ServingField.servingsPerPack),
        ('No. of servings: 4', ServingField.servingsPerPack),
        ('Net Weight 120 g', ServingField.netQuantity),
        ('Net Wt. 120 g', ServingField.netQuantity),
        ('Net Qty. 120 g', ServingField.netQuantity),
        ('Net content 120 g', ServingField.netQuantity),
      ]) {
        expect(fieldFor(line), field, reason: line);
      }
    });

    test('an alias never scores EXACT', () {
      // Convention is not specification, and the confidence model must be able
      // to tell them apart.
      for (final String line in <String>[
        'Serve size 30 g',
        'Servings per package: 4',
        'Net Wt. 120 g',
      ]) {
        expect(strengthFor(line), ParseStrength.normalised, reason: line);
      }
    });
  });

  group('the heuristic plural', () {
    test('a bare "servings" reads a pack count at HEURISTIC', () {
      // Meaningful only because the singular "per serving" is a column header
      // and the plural is not. This is what makes "About 4 servings" readable.
      expect(fieldFor('About 4 servings'), ServingField.servingsPerPack);
      expect(strengthFor('About 4 servings'), ParseStrength.heuristic);
    });

    test('the singular "per serving" is not a marker', () {
      // The nutrition panel column header. Reading it as a declaration would
      // invent a serving figure from a table heading.
      expect(table.strongestMatch('Per serving'), isNull);
      expect(table.strongestMatch('Energy per serving'), isNull);
    });
  });

  group('longest match wins — the rule that keeps strength honest', () {
    test('a specific wording beats the bare plural it contains', () {
      // "servings" is a substring of "servings per pack". Preferring the
      // shorter would read every pack-count line at HEURISTIC when an EXACT
      // wording was printed.
      expect(strengthFor('Servings per pack: 4'), ParseStrength.exact);
      expect(
          strengthFor('Servings per container: 4'), ParseStrength.normalised);
    });

    test('the choice does not depend on declaration order', () {
      // Same markers, reversed table: longest still wins.
      final ServingMarkerTable reversed =
          ServingMarkerTable(table.markers.reversed.toList());
      expect(
        reversed.strongestMatch('Servings per pack: 4')?.strength,
        ParseStrength.exact,
      );
    });
  });

  group('deliberately unsupported patterns stay unsupported', () {
    test('ambiguous count and container phrasings match nothing', () {
      // Each could be a serving count, a multipack count or a net quantity,
      // and nothing in the text settles which. No marker means the figure is
      // reported absent rather than guessed.
      for (final String line in <String>[
        'Pack of 4',
        '4 x 30 g',
        '30 g x 4',
        '250 ml bottle',
        'Contains 4 pieces',
      ]) {
        expect(table.strongestMatch(line), isNull, reason: line);
      }
    });

    test('bare "quantity" and "weight" are too broad to be markers', () {
      expect(table.strongestMatch('Quantity 120 g'), isNull);
      expect(table.strongestMatch('Weight 120 g'), isNull);
    });

    test('an empty line matches nothing', () {
      expect(table.strongestMatch(''), isNull);
    });

    test('an unrelated line matches nothing', () {
      expect(table.strongestMatch('Ingredients: Wheat flour, Sugar'), isNull);
      expect(table.strongestMatch('Energy 450 kcal'), isNull);
    });
  });

  group('ServingMarkerTable — construction', () {
    test('FR-KB-01 the marker list is unmodifiable once built', () {
      expect(
        () => table.markers.add(ServingMarker(
          text: 'x',
          field: ServingField.servingSize,
          strength: ParseStrength.exact,
        )),
        throwsUnsupportedError,
      );
    });

    test('an empty table matches nothing rather than failing', () {
      final ServingMarkerTable empty =
          ServingMarkerTable(const <ServingMarker>[]);
      expect(empty.strongestMatch('Serving Size: 30 g'), isNull);
    });

    test('the default table covers all three fields', () {
      for (final ServingField f in ServingField.values) {
        expect(
          table.markers.any((ServingMarker m) => m.field == f),
          isTrue,
          reason: '${f.name} needs at least one wording',
        );
      }
    });

    test('toString reports the size', () {
      expect(table.toString(), contains('${table.markers.length}'));
    });
  });
}
