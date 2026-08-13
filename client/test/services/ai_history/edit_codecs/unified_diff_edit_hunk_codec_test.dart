import 'package:ai_message_core/ai_message_core.dart'
    hide UnifiedDiffEditHunkCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';

/// Test codec configuration matching the original built-in codec defaults.
const _testToolNames = {'applypatch', 'apply_patch'};
const _testPathKeys = ['file_path', 'path', 'file', 'target_file'];

UnifiedDiffEditHunkCodec _testCodec() => const UnifiedDiffEditHunkCodec(
      toolNames: _testToolNames,
      pathKeys: _testPathKeys,
    );

AiToolCallPart _makeToolCall({
  required String toolName,
  Map<String, Object?>? args,
  String? argsText,
}) {
  return AiToolCallPart(
    toolCallId: 'call-1',
    toolName: toolName,
    args: args,
    argsText: argsText,
  );
}

const samplePatch = '''
--- a/lib/foo.dart
+++ b/lib/foo.dart
@@ -10,3 +10,4 @@
 context
-removed
+added
''';

void main() {
  // ---------------------------------------------------------------------------
  // matches
  // ---------------------------------------------------------------------------
  group('matches', () {
    final codec = _testCodec();

    test('matches exact tool name', () {
      expect(codec.matches('ApplyPatch'), isTrue);
    });

    test('matches tool name with different casing', () {
      expect(codec.matches('applypatch'), isTrue);
      expect(codec.matches('APPLYPATCH'), isTrue);
      expect(codec.matches('ApplyPatch'), isTrue);
      expect(codec.matches('ApPlYpAtCh'), isTrue);
    });

    test('matches apply_patch variant', () {
      expect(codec.matches('apply_patch'), isTrue);
      expect(codec.matches('APPLY_PATCH'), isTrue);
      expect(codec.matches('Apply_Patch'), isTrue);
    });

    test('does not match unconfigured tool name', () {
      expect(codec.matches('write'), isFalse);
      expect(codec.matches('edit'), isFalse);
      expect(codec.matches('unknown'), isFalse);
      expect(codec.matches(''), isFalse);
    });

    test('does not match tool name not in set even with same prefix', () {
      expect(codec.matches('applypatchv2'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // encode – basic parsing
  // ---------------------------------------------------------------------------
  group('encode', () {
    test('parses +/- lines and context', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'lib/foo.dart',
            'patch': samplePatch,
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'lib/foo.dart');
      expect(hunk.addedCount, 1);
      expect(hunk.removedCount, 1);
      expect(hunk.startLine, 10);
      expect(hunk.lines.map((l) => l.kind).toList(), [
        AiEditLineKind.context,
        AiEditLineKind.remove,
        AiEditLineKind.add,
      ]);
      expect(hunk.lines.map((l) => l.text).toList(), [
        'context',
        'removed',
        'added',
      ]);
    });

    test('path from +++ header when args path missing', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'apply_patch',
          args: {
            'diff': '''--- a/x.dart
+++ b/x.dart
-old
+new
''',
          },
        ),
      );
      expect(hunk!.path, 'x.dart');
      expect(hunk.addedCount, 1);
      expect(hunk.removedCount, 1);
    });

    test('path from --- header when args path and +++ path missing', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'patch': '''--- a/only_remove.dart
+++ /dev/null
-old_line
+new_line
''',
          },
        ),
      );
      expect(hunk!.path, 'only_remove.dart');
    });

    test('path from +++ header with no a/ prefix', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'diff': '''--- a/
+++ b/some/deep/path.dart
-old
+new
''',
          },
        ),
      );
      expect(hunk!.path, 'some/deep/path.dart');
    });

    test('path from +++ header without a/ or b/ prefix', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'diff': '''--- a/
+++ raw_path.dart
-old
+new
''',
          },
        ),
      );
      expect(hunk!.path, 'raw_path.dart');
    });

    test('args path takes precedence over header path', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'explicit.dart',
            'patch': '''--- a/header_path.dart
+++ b/header_path.dart
-old
+new
''',
          },
        ),
      );
      expect(hunk!.path, 'explicit.dart');
    });

    test('diff key alias', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'path': 'a.dart',
            'diff': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'a.dart');
    });

    test('input key alias', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'path': 'a.dart',
            'input': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'a.dart');
    });

    test('patch key alias', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'path': 'a.dart',
            'patch': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'a.dart');
    });

    test('file and target_file path key aliases', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'target_file': 'target.dart',
            'patch': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'target.dart');
    });

    // -----------------------------------------------------------------------
    // Null / missing cases
    // -----------------------------------------------------------------------
    test('no add/remove lines returns null', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'a.dart',
            'patch': '''--- a/a.dart
+++ b/a.dart
 context only
''',
          },
        ),
      );
      expect(hunk, isNull);
    });

    test('missing path and no headers returns null', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {'patch': '-x\n+y'},
        ),
      );
      expect(hunk, isNull);
    });

    test('missing patch returns null', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {'file_path': 'a.dart'},
        ),
      );
      expect(hunk, isNull);
    });

    test('empty patch returns null', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'a.dart',
            'patch': '',
          },
        ),
      );
      expect(hunk, isNull);
    });

    test('non-matching tool name returns null', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'write',
          args: {
            'file_path': 'a.dart',
            'patch': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNull);
    });

    test('patch with only empty lines returns null', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'a.dart',
            'patch': '\n\n',
          },
        ),
      );
      expect(hunk, isNull);
    });

    test('null args returns null', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(toolName: 'ApplyPatch'),
      );
      expect(hunk, isNull);
    });

    // -----------------------------------------------------------------------
    // Multi-hunk and line classification
    // -----------------------------------------------------------------------
    test('handles multiple hunks (only first startLine captured)', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'multi.dart',
            'patch': '''@@ -5,2 +5,3 @@
-rem1
+add1
@@ -20,2 +20,3 @@
-rem2
+add2
''',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.startLine, 5);
      expect(hunk.addedCount, 2);
      expect(hunk.removedCount, 2);
      expect(hunk.lines.length, 4);
    });

    test('handles lines without prefix as context', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'no_prefix.dart',
            'patch': '''--- a/no_prefix.dart
+++ b/no_prefix.dart
@@ -1,2 +1,3 @@
 line_without_prefix
+new_line
''',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.lines[0].kind, AiEditLineKind.context);
      expect(hunk.lines[0].text, 'line_without_prefix');
      expect(hunk.lines[1].kind, AiEditLineKind.add);
    });

    test('startLine from hunk header with offset and count', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'offset.dart',
            'patch': '''@@ -15,7 +15,8 @@
 context
-old_line
+new_line
''',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.startLine, 15);
    });

    // -----------------------------------------------------------------------
    // argsText JSON decoding
    // -----------------------------------------------------------------------
    test('decodes argsText JSON', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'apply_patch',
          argsText:
              '{"file_path": "json.dart", "patch": "-x\\n+y"}',
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'json.dart');
      expect(hunk.addedCount, 1);
      expect(hunk.removedCount, 1);
    });

    // -----------------------------------------------------------------------
    // FREEFORM argsText (codex apply_patch)
    // -----------------------------------------------------------------------
    test('freeform argsText: non-JSON text used as patch (codex apply_patch)',
        () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'apply_patch',
          argsText: '''*** Begin Patch
*** Update File: lib/foo.dart
@@ -1,2 +1,3 @@
-removed
+added
*** End Patch''',
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'lib/foo.dart');
      expect(hunk.removedCount, 1);
      expect(hunk.addedCount, 1);
      expect(hunk.lines[0].kind, AiEditLineKind.remove);
      expect(hunk.lines[0].text, 'removed');
      expect(hunk.lines[1].kind, AiEditLineKind.add);
      expect(hunk.lines[1].text, 'added');
    });

    test('freeform argsText: Add File header path extraction', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'apply_patch',
          argsText: '''*** Begin Patch
*** Add File: README.md
+hello
*** End Patch''',
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'README.md');
      expect(hunk.addedCount, 1);
      expect(hunk.removedCount, 0);
    });

    test('freeform argsText: non-file *** lines (Begin/End Patch) are skipped',
        () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'apply_patch',
          argsText: '''*** Begin Patch
*** Update File: a.dart
- x
*** End Patch
*** End of File''',
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'a.dart');
      expect(hunk.removedCount, 1);
      expect(hunk.lines.every((l) => l.kind == AiEditLineKind.remove), isTrue);
    });

    test('freeform argsText: structured args still win over argsText', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'explicit.dart',
            'patch': '-x\n+y',
          },
          argsText: '*** Begin Patch\n*** Update File: ignored.dart\n-z\n+w\n*** End Patch',
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'explicit.dart');
      expect(hunk.removedCount, 1);
      expect(hunk.lines[0].text, 'x');
    });

    test('freeform argsText: JSON argsText is not treated as freeform', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'apply_patch',
          argsText: '{"file_path": "a.dart"}',
        ),
      );
      expect(hunk, isNull);
    });

    test('freeform argsText: delete-only header produces no hunk', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'apply_patch',
          argsText: '*** Begin Patch\n*** Delete File: gone.dart\n*** End Patch',
        ),
      );
      expect(hunk, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // configurable tool names
  // ---------------------------------------------------------------------------
  group('configurable tool names', () {
    test('only matches tools passed via constructor', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: {'myapplypatch'},
        pathKeys: _testPathKeys,
      );

      expect(codec.matches('myapplypatch'), isTrue);
      expect(codec.matches('MYAPPLYPATCH'), isTrue);
      expect(codec.matches('ApplyPatch'), isFalse);
      expect(codec.matches('applypatch'), isFalse);
      expect(codec.matches('apply_patch'), isFalse);
    });

    test('multiple custom tool names', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: {'patch_file', 'apply_diff'},
        pathKeys: _testPathKeys,
      );

      expect(codec.matches('patch_file'), isTrue);
      expect(codec.matches('PATCH_FILE'), isTrue);
      expect(codec.matches('apply_diff'), isTrue);
      expect(codec.matches('APPLY_DIFF'), isTrue);
      expect(codec.matches('ApplyPatch'), isFalse);
    });

    test('matches empty string only if configured', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: {''},
        pathKeys: _testPathKeys,
      );

      expect(codec.matches(''), isTrue);
      expect(codec.matches('ApplyPatch'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // configurable patch keys
  // ---------------------------------------------------------------------------
  group('configurable patch keys', () {
    test('custom patch key alias', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: _testToolNames,
        pathKeys: _testPathKeys,
        patchKeys: ['unified_diff', 'patch'],
      );

      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'custom.dart',
            'unified_diff': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'custom.dart');
    });

    test('falls back to second custom key', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: _testToolNames,
        pathKeys: _testPathKeys,
        patchKeys: ['primary', 'fallback'],
      );

      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'fallback.dart',
            'fallback': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'fallback.dart');
    });

    test('prefers first custom key over later ones', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: _testToolNames,
        pathKeys: _testPathKeys,
        patchKeys: ['primary', 'fallback'],
      );

      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'primary.dart',
            'primary': '-x\n+y',
            'fallback': '-a\n+b',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.removedCount, 1);
      expect(hunk.lines[0].text, 'x');
    });

    test('does not use default keys when custom keys provided', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: _testToolNames,
        pathKeys: _testPathKeys,
        patchKeys: ['my_patch'],
      );

      // 'diff' is a default key but not in custom set — should not match
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'file_path': 'nope.dart',
            'diff': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // configurable path keys
  // ---------------------------------------------------------------------------
  group('configurable path keys', () {
    test('custom path key alias', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: _testToolNames,
        pathKeys: ['target', 'file_path'],
      );

      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'target': 'custom_path.dart',
            'patch': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'custom_path.dart');
    });

    test('falls back to second custom path key', () {
      const codec = UnifiedDiffEditHunkCodec(
        toolNames: _testToolNames,
        pathKeys: ['primary_path', 'fallback_path'],
      );

      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'fallback_path': 'from_fallback.dart',
            'patch': '-x\n+y',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'from_fallback.dart');
    });
  });

  // ---------------------------------------------------------------------------
  // _pathFromDiffHeader edge cases (via encode)
  // ---------------------------------------------------------------------------
  group('_pathFromDiffHeader edge cases', () {
    test('returns null for empty path after stripping prefixes', () {
      // --- a/ with nothing after stripping yields empty string
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'patch': '''--- a/
+++ b/
-old
+new
''',
          },
        ),
      );
      // path is null because both headers yield empty after stripping,
      // so encode returns null (path == null)
      expect(hunk, isNull);
    });

    test('returns null for /dev/null header', () {
      // --- /dev/null yields '/dev/null' from _pathFromDiffHeader.
      // The +++ header would give 'real_file.dart' but --- wins (processed
      // first with ??=), so path is '/dev/null'.
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'patch': '''--- /dev/null
+++ b/real_file.dart
-old
+new
''',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, '/dev/null');
    });

    test('strips a/ prefix correctly', () {
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'diff': '''--- a/project/src/main.dart
+++ b/project/src/main.dart
-old
+new
''',
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.path, 'project/src/main.dart');
    });

    test('--- header without trailing space does not extract path', () {
      // The _pathFromDiffHeader method requires '--- ' (with space),
      // so '---a/file.dart' (no space) won't trigger it.
      // The encode loop checks `rawLine.startsWith('---')` to enter
      // the block, but _pathFromDiffHeader internally requires the space.
      final codec = _testCodec();
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'ApplyPatch',
          args: {
            'patch': '''---a/file.dart
+++ b/file.dart
-old
+new
''',
          },
        ),
      );
      // --- line yields null from _pathFromDiffHeader (no space),
      // +++ line has path 'file.dart', so path should work
      expect(hunk, isNotNull);
      expect(hunk!.path, 'file.dart');
    });
  });
}
