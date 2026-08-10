import 'dart:convert';
import 'dart:io';

import 'package:lw_rulepack/lw_rulepack.dart';
import 'package:test/test.dart';

import 'pack_fixture.dart';

void main() {
  group('PackPaths — the §7.2 scope rule, in one place', () {
    test('content files contribute to the digest', () {
      expect(PackPaths.isContentFile('sources.json'), isTrue);
      expect(PackPaths.isContentFile('nutrients/rda.json'), isTrue);
      expect(PackPaths.isContentFile('messages/en.json'), isTrue);
      expect(PackPaths.isContentFile('messages/hi.json'), isTrue,
          reason: 'a catalogue added later is covered without a code change');
    });

    test('the manifest cannot contain its own digest', () {
      expect(PackPaths.isContentFile('manifest.json'), isFalse);
    });

    test('schema/ is excluded, deliberately', () {
      // The runtime never reads it — CI is the authority on schema validity.
      // Hashing it would let a schema typo-fix break the shipped pack.
      expect(PackPaths.isContentFile('schema/common.schema.json'), isFalse);
      expect(PackPaths.isContentFile('schema/ins.schema.json'), isFalse);
    });

    test('LICENSE is excluded — legal text, not knowledge', () {
      expect(PackPaths.isContentFile('LICENSE'), isFalse);
    });

    test('the digest scope is exactly the eight content files', () {
      final List<String> content =
          PackPaths.contentFilesIn(PackFixture.defaults.keys);
      expect(content, <String>[
        'additives/ins.json',
        'categories/categories.json',
        'messages/en.json',
        'nutrients/rda.json',
        'nutrients/synonyms.json',
        'rules/confidence.json',
        'rules/thresholds.json',
        'sources.json',
      ]);
    });

    test('ordering is byte-wise ascending, not insertion order', () {
      // The order must not depend on the machine that computed the digest.
      expect(
        PackPaths.contentFilesIn(<String>['z.json', 'a.json', 'm/b.json']),
        <String>['a.json', 'm/b.json', 'z.json'],
      );
    });
  });

  group('RulePackIntegrity — the algorithm §7.2 specifies', () {
    test('the digest is stable across repeated computation', () async {
      final InMemoryRulePackSource s = PackFixture.pack();
      expect(await RulePackIntegrity.compute(s),
          await RulePackIntegrity.compute(s));
    });

    test('the digest does not depend on the order files were supplied', () {
      // Two Maps with the same entries in different insertion order.
      final Map<String, String> a = <String, String>{
        'sources.json': '{}',
        'messages/en.json': '{}',
      };
      final Map<String, String> b = <String, String>{
        'messages/en.json': '{}',
        'sources.json': '{}',
      };
      expect(PackFixture.computeDigest(a), PackFixture.computeDigest(b));
    });

    test('changing a content byte changes the digest', () async {
      final String clean = await RulePackIntegrity.compute(PackFixture.pack());
      final String edited = await RulePackIntegrity.compute(
        PackFixture.pack(overrides: <String, String>{
          'rules/thresholds.json': '{"rules":[] }',
        }),
      );
      expect(edited, isNot(clean));
    });

    test('changing an EXCLUDED file does not change the digest', () async {
      // The property that made the content-only scope the right choice: a
      // schema fix must not invalidate a pack whose knowledge is unchanged.
      final String clean = await RulePackIntegrity.compute(PackFixture.pack());
      final String schemaEdited = await RulePackIntegrity.compute(
        PackFixture.pack(overrides: <String, String>{
          'schema/common.schema.json': '{"\$defs":{"added":{}}}',
          'LICENSE': 'CC BY 4.0 (revised wording)',
        }),
      );
      expect(schemaEdited, clean);
    });

    test('the path is hashed, so swapping two bodies is detected', () {
      // Without hashing the path, two files whose contents were exchanged
      // would produce an identical digest.
      final String straight = PackFixture.computeDigest(<String, String>{
        'sources.json': 'A',
        'messages/en.json': 'B',
      });
      final String swapped = PackFixture.computeDigest(<String, String>{
        'sources.json': 'B',
        'messages/en.json': 'A',
      });
      expect(swapped, isNot(straight));
    });

    test('the digest is lower-case hex behind a sha256: prefix', () async {
      final String d = await RulePackIntegrity.compute(PackFixture.pack());
      expect(d, startsWith('sha256:'));
      expect(d, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
    });

    test('the loader and the fixture agree, being separate code paths',
        () async {
      expect(
        await RulePackIntegrity.compute(PackFixture.pack()),
        PackFixture.computeDigest(PackFixture.defaults),
      );
    });

    test('matches is an exact comparison, not case-insensitive', () {
      const String d = 'sha256:abc';
      expect(RulePackIntegrity.matches(computed: d, recorded: d), isTrue);
      expect(
        RulePackIntegrity.matches(computed: d, recorded: 'sha256:ABC'),
        isFalse,
        reason: 'both sides are canonical; tolerating case would mask a '
            'manifest that escaped validation',
      );
    });
  });

  group('RulePackIntegrity — against the shipped pack', () {
    // The regression guard for the defect this milestone opened by finding:
    // the recorded digest described a wider file set than it covered, and
    // nothing recomputed it. This is the Dart half; CI-17 is the Python half.
    test('the recorded hash matches the recipe, on the real pack', () async {
      final Directory? root = _findPackRoot();
      if (root == null) {
        fail('rulepack/ not found from ${Directory.current.path}');
      }
      final Map<String, String> files = <String, String>{};
      for (final FileSystemEntity e in root.listSync(recursive: true)) {
        if (e is File) {
          final String rel =
              e.path.substring(root.path.length + 1).replaceAll('\\', '/');
          files[rel] = utf8.decode(e.readAsBytesSync());
        }
      }
      final Map<String, Object?> manifest =
          jsonDecode(files['manifest.json']!) as Map<String, Object?>;
      expect(
        PackFixture.computeDigest(files),
        manifest['integrityHash']! as String,
      );
    });
  });
}

/// Walks up from the working directory to find `rulepack/`.
Directory? _findPackRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 5; i++) {
    final Directory candidate = Directory('${dir.path}/rulepack');
    if (candidate.existsSync()) {
      return candidate;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      return null;
    }
    dir = parent;
  }
  return null;
}
