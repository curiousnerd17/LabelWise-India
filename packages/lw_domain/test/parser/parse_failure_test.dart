import 'package:lw_domain/lw_domain.dart';
import 'package:test/test.dart';

void main() {
  /// A failure built with a runtime-computed message id, so two calls yield
  /// equal but distinct instances. Dart canonicalises identical const
  /// instances, and comparing two of those asserts identity rather than value.
  ParseFailure freshFailure(ParseFailureKind kind, PipelineStage stage) =>
      ParseFailure(
        kind: kind,
        stage: stage,
        detailMessageId: String.fromCharCodes('msg.parse.detail'.codeUnits),
      );

  group('ParseFailure — structured, never an empty success (FR-PAR-17)', () {
    test('FR-PAR-17 records what failed and at which stage', () {
      const ParseFailure f = ParseFailure(
        kind: ParseFailureKind.unsupportedScript,
        stage: PipelineStage.normalisation,
      );
      expect(f.kind, ParseFailureKind.unsupportedScript);
      expect(f.stage, PipelineStage.normalisation);
      expect(f.region, isNull);
    });

    test('FR-ERR-01 every failure kind is specific, not generic', () {
      // A single generic error would make FR-ERR-01's "specific, actionable
      // message" impossible for the presentation layer to produce.
      expect(ParseFailureKind.values, hasLength(5));
      expect(
        ParseFailureKind.values.map((ParseFailureKind k) => k.name),
        <String>[
          'unsupportedScript',
          'noTextRecognised',
          'layoutIndeterminate',
          'regionNotFound',
          'internalInconsistency',
        ],
      );
    });

    test('FR-ERR-01 a failure may localise itself to a region', () {
      final ParseFailure f = ParseFailure(
        kind: ParseFailureKind.regionNotFound,
        stage: PipelineStage.regionClassification,
        region: RegionRef(left: 0, top: 0, right: 100, bottom: 100),
      );
      expect(f.region, isNotNull);
    });

    test('P4 compares by value, not identity', () {
      // Two const literals would be canonicalised into one object, so `==`
      // would return true from its `identical` guard without comparing a
      // single field — the assertion would pass while testing nothing.
      final ParseFailure a = freshFailure(
        ParseFailureKind.noTextRecognised,
        PipelineStage.normalisation,
      );
      final ParseFailure b = freshFailure(
        ParseFailureKind.noTextRecognised,
        PipelineStage.normalisation,
      );
      final ParseFailure otherKind = freshFailure(
        ParseFailureKind.regionNotFound,
        PipelineStage.normalisation,
      );
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(otherKind), reason: 'kind must participate in equality');
    });
  });

  group('StageResult — every stage is total (ARCHITECTURE 6.2)', () {
    test('FR-PAR-17 success carries a value', () {
      const StageResult<int> r = StageSuccess<int>(42);
      expect(r, isA<StageSuccess<int>>());
      expect((r as StageSuccess<int>).value, 42);
      expect(r.valueOrNull, 42);
      expect(r.failureOrNull, isNull);
      expect(r.isSuccess, isTrue);
    });

    test('FR-PAR-17 failure carries a reason and no value', () {
      const ParseFailure f = ParseFailure(
        kind: ParseFailureKind.layoutIndeterminate,
        stage: PipelineStage.layoutReconstruction,
      );
      const StageResult<int> r = StageFailure<int>(f);
      expect(r.valueOrNull, isNull);
      expect(r.failureOrNull, f);
      expect(r.isSuccess, isFalse);
    });

    test('FR-PAR-17 a switch over StageResult is exhaustive', () {
      // Sealed, so omitting a variant does not compile. This asserts the
      // runtime behaviour of both arms.
      String describe(StageResult<int> r) => switch (r) {
            StageSuccess<int>() => 'success',
            StageFailure<int>() => 'failure',
          };
      expect(describe(const StageSuccess<int>(1)), 'success');
      expect(
        describe(const StageFailure<int>(ParseFailure(
          kind: ParseFailureKind.internalInconsistency,
          stage: PipelineStage.tokenisation,
        ))),
        'failure',
      );
    });

    test('FR-PAR-01 a stage never throws for an expected condition', () {
      // Exceptions are for programming errors only (ARCHITECTURE section 5).
      // An expected failure is a value.
      const StageResult<int> r = StageFailure<int>(ParseFailure(
        kind: ParseFailureKind.noTextRecognised,
        stage: PipelineStage.normalisation,
      ));
      expect(() => r.valueOrNull, returnsNormally);
      expect(() => r.failureOrNull, returnsNormally);
      expect(() => r.isSuccess, returnsNormally);
    });

    test('P4 stage results compare by value, not identity', () {
      // PT-06 asserts determinism by comparing stage outputs. That comparison
      // is only meaningful if two independently produced results with the same
      // content are equal, and a failure never equals a success.
      final StageResult<int> a = StageSuccess<int>(int.parse('42'));
      final StageResult<int> b = StageSuccess<int>(int.parse('42'));
      expect(identical(a, b), isFalse, reason: 'must be distinct instances');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(StageSuccess<int>(int.parse('43'))));

      final StageResult<int> c = StageFailure<int>(freshFailure(
        ParseFailureKind.regionNotFound,
        PipelineStage.tokenisation,
      ));
      final StageResult<int> d = StageFailure<int>(freshFailure(
        ParseFailureKind.regionNotFound,
        PipelineStage.tokenisation,
      ));
      expect(identical(c, d), isFalse, reason: 'must be distinct instances');
      expect(c, d);
      expect(c.hashCode, d.hashCode);
      expect(c, isNot(a), reason: 'a failure must never equal a success');
    });

    test('FR-PAR-13 toString names the outcome and the reason', () {
      // The diagnostic surface for the approved goal "keep stage outputs
      // traceable". A failure that prints only its type tells a maintainer
      // nothing about why the stage stopped.
      expect(const StageSuccess<int>(42).toString(), 'StageSuccess(42)');
      expect(
        const StageFailure<int>(ParseFailure(
          kind: ParseFailureKind.noTextRecognised,
          stage: PipelineStage.normalisation,
        )).toString(),
        'StageFailure(ParseFailure(noTextRecognised at normalisation))',
      );
    });
  });
}
