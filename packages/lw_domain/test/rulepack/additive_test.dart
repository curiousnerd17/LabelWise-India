import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  PermissionEvidence evidence({String entry = 'Curcumin or turmeric'}) =>
      PermissionEvidence(
        sourceRef: SourceId('src.fssai.additives.2011'),
        scheduleRef: 'Appendix A, Table 1, section G.a, item 3',
        entryName: entry,
        foodProducts: 'Biscuits',
        limit: 'GMP',
      );

  IndianPermission permitted() => IndianPermission(
        status: PermissionStatus.permitted,
        evidence: <PermissionEvidence>[evidence()],
      );

  AdditiveRecord additive(
    int ins, {
    String name = 'Curcumin',
    IndianPermission? permission,
    List<String> alternates = const <String>[],
    EvidenceStrength strength = EvidenceStrength.established,
  }) =>
      AdditiveRecord(
        insNumber: InsNumber(ins),
        commonName: name,
        alternateNames: alternates,
        functionalClass: FunctionalClass.colour,
        descriptionMessageId: MessageId('msg.additive.ins-$ins'),
        evidenceStrength: strength,
        sourceRefs: <SourceId>[SourceId('src.fssai.additives.2011')],
        indianPermission: permission ?? permitted(),
      );

  group('IndianPermission — P1, not a boolean', () {
    test('there is no PROHIBITED status, and that is the point', () {
      // Appendix A lists additives by name per food product and contains no
      // INS numbers. Finding nothing is not evidence of prohibition, so the
      // type offers no way to say so.
      expect(PermissionStatus.values, hasLength(2));
      expect(
        PermissionStatus.values.map((PermissionStatus s) => s.name),
        <String>['permitted', 'unknown'],
      );
    });

    test('FR-KB-04 PERMITTED without a citation is refused', () {
      // A permission claim with no evidence is the exact failure the
      // requirement exists to prevent, so the type refuses it rather than
      // leaving it to validation somebody might skip.
      expect(
        () => IndianPermission(status: PermissionStatus.permitted),
        throwsArgumentError,
      );
      expect(
        () => IndianPermission(
          status: PermissionStatus.permitted,
          evidence: const <PermissionEvidence>[],
        ),
        throwsArgumentError,
      );
    });

    test('P1 UNKNOWN needs no citation, because we found nothing', () {
      final IndianPermission p =
          IndianPermission(status: PermissionStatus.unknown);
      expect(p.status, PermissionStatus.unknown);
      expect(p.evidence, isEmpty);
    });

    test('UNKNOWN carries an optional curator note about scope', () {
      final IndianPermission p = IndianPermission(
        status: PermissionStatus.unknown,
        note: 'Tables 3-15 were not examined.',
      );
      expect(p.note, contains('not examined'));
    });

    test('P4 compares by value, including the evidence list', () {
      expect(permitted(), permitted());
      expect(permitted().hashCode, permitted().hashCode);
      expect(permitted(),
          isNot(IndianPermission(status: PermissionStatus.unknown)));
      expect(
        permitted(),
        isNot(IndianPermission(
          status: PermissionStatus.permitted,
          evidence: <PermissionEvidence>[evidence(entry: 'Something else')],
        )),
      );
    });

    test('FR-KB-01 the evidence list is unmodifiable once built', () {
      expect(
          () => permitted().evidence.add(evidence()), throwsUnsupportedError);
    });
  });

  group('PermissionEvidence — every field is there to be checked', () {
    test('the printed entry name records our inference, auditably', () {
      // The INS-to-name mapping is ours, not the regulation's. Recording the
      // name as printed is what makes that inference checkable.
      expect(evidence().entryName, 'Curcumin or turmeric');
      expect(evidence().scheduleRef, contains('Table 1'));
    });

    test('permission never extends beyond the cited food products', () {
      expect(evidence().foodProducts, 'Biscuits');
    });

    test('the limit is a printed string, not a fabricated number', () {
      // 'GMP' and '100 ppm max' do not share a scale. Coercing them to a
      // number would invent precision the regulation does not state.
      expect(evidence().limit, isA<String>());
      expect(evidence().limit, 'GMP');
    });

    test('P4 compares by value across every field', () {
      expect(evidence(), evidence());
      expect(evidence().hashCode, evidence().hashCode);
      expect(evidence(), isNot(evidence(entry: 'Other')));
    });

    test('toString names the entry and its scope', () {
      expect(evidence().toString(), contains('Curcumin or turmeric'));
      expect(evidence().toString(), contains('Biscuits'));
    });
  });

  group('AdditiveRecord — a record, not an engine', () {
    test('ADR-0005 the INS number is the key', () {
      expect(additive(100).insNumber, InsNumber(100));
    });

    test('FR-KB-06 name, class and description are all present', () {
      final AdditiveRecord a = additive(100);
      expect(a.commonName, 'Curcumin');
      expect(a.functionalClass, FunctionalClass.colour);
      expect(a.descriptionMessageId, MessageId('msg.additive.ins-100'));
    });

    test('B8 the plain-language description is an id, not text', () {
      // The common name is a proper name — what the substance is called in any
      // language. The explanation is catalogue content.
      expect(additive(100).descriptionMessageId, isA<MessageId>());
    });

    test('CXG 36-1989 the functional classes are a closed set', () {
      // Defined by an international standard, not by us. Inventing a class
      // would make our vocabulary untraceable to the standard it follows.
      expect(FunctionalClass.values, hasLength(22));
      expect(FunctionalClass.values, contains(FunctionalClass.preservative));
      expect(FunctionalClass.values, contains(FunctionalClass.sweetener));
    });

    test('FR-KB-04 a record with no citation is refused', () {
      expect(
        () => AdditiveRecord(
          insNumber: InsNumber(100),
          commonName: 'Curcumin',
          functionalClass: FunctionalClass.colour,
          descriptionMessageId: MessageId('msg.additive.ins-100'),
          evidenceStrength: EvidenceStrength.established,
          sourceRefs: const <SourceId>[],
          indianPermission: permitted(),
        ),
        throwsArgumentError,
      );
    });

    test('FR-KB-07 evidence strength is recorded per additive', () {
      expect(
          additive(102, strength: EvidenceStrength.contested).evidenceStrength,
          EvidenceStrength.contested);
    });

    test('alternate names are preserved in order', () {
      final AdditiveRecord a =
          additive(100, alternates: <String>['Turmeric yellow', 'E100']);
      expect(a.alternateNames, <String>['Turmeric yellow', 'E100']);
    });

    test('P4 compares by value across every field', () {
      expect(additive(100), additive(100));
      expect(additive(100).hashCode, additive(100).hashCode);
      expect(additive(100), isNot(additive(101)));
      expect(additive(100), isNot(additive(100, name: 'Other')));
      expect(additive(100),
          isNot(additive(100, alternates: <String>['Turmeric yellow'])));
      expect(
        additive(100),
        isNot(additive(100,
            permission: IndianPermission(status: PermissionStatus.unknown))),
      );
    });

    test('FR-KB-01 both lists are unmodifiable once built', () {
      final AdditiveRecord a = additive(100);
      expect(() => a.sourceRefs.add(SourceId('src.x')), throwsUnsupportedError);
      expect(() => a.alternateNames.add('x'), throwsUnsupportedError);
    });

    test('toString names the number and the substance', () {
      expect(additive(100).toString(), contains('100'));
      expect(additive(100).toString(), contains('Curcumin'));
    });
  });

  group('AdditiveTable — the lazily loaded segment', () {
    test('a known INS number resolves', () {
      final AdditiveTable t =
          AdditiveTable(<AdditiveRecord>[additive(100), additive(322)]);
      expect(t[InsNumber(322)]!.insNumber.value, 322);
      expect(t.contains(InsNumber(100)), isTrue);
      expect(t.length, 2);
    });

    test('P1 an unknown INS number resolves to null, not a guess', () {
      // The common case, and not a failure. An unrecognised number is reported
      // to the user as unidentified with the number shown, which is useful.
      // Guessing would not be.
      final AdditiveTable t = AdditiveTable(<AdditiveRecord>[additive(100)]);
      expect(t[InsNumber(999)], isNull);
      expect(t.contains(InsNumber(999)), isFalse);
    });

    test('a duplicate INS number is refused', () {
      expect(
        () => AdditiveTable(<AdditiveRecord>[additive(100), additive(100)]),
        throwsArgumentError,
      );
    });

    test('the empty table is a real table, not null', () {
      // A pack whose additives have not been loaded yet has an empty table,
      // which resolves nothing and throws nothing.
      expect(AdditiveTable.empty.length, 0);
      expect(AdditiveTable.empty[InsNumber(100)], isNull);
    });

    test('FR-PAR-02 pack order is preserved', () {
      final AdditiveTable t = AdditiveTable(<AdditiveRecord>[
        additive(322),
        additive(100),
      ]);
      expect(
        t.additives.map((AdditiveRecord a) => a.insNumber.value),
        <int>[322, 100],
      );
    });

    test('FR-KB-01 the list is unmodifiable once built', () {
      final AdditiveTable t = AdditiveTable(<AdditiveRecord>[additive(100)]);
      expect(() => t.additives.add(additive(101)), throwsUnsupportedError);
    });
  });
}
