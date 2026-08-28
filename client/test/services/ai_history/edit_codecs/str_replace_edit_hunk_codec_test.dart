import 'package:ai_message_core/ai_message_core.dart'
    hide StrReplaceEditHunkCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';

/// Test codec configuration matching the original built-in codec defaults.
const _testToolNames = {'strreplace', 'edit', 'notebookedit'};
const _testPathKeys = ['file_path', 'path'];
const _testOldStringKeys = ['old_string', 'old_str'];
const _testNewStringKeys = ['new_string', 'new_str'];
const _testStartLineKeys = ['start_line', 'start_line_num'];

StrReplaceEditHunkCodec _testCodec() => const StrReplaceEditHunkCodec(
      toolNames: _testToolNames,
      pathKeys: _testPathKeys,
      oldStringKeys: _testOldStringKeys,
      newStringKeys: _testNewStringKeys,
      startLineKeys: _testStartLineKeys,
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

void main() {
  // ---------------------------------------------------------------------------
  // matches
  // ---------------------------------------------------------------------------
  group('matches', () {
    final codec = _testCodec();

    test('matches exact tool name', () {
      expect(codec.matches('edit'), isTrue);
    });

    test('matches tool name with different casing', () {
      expect(codec.matches('Edit'), isTrue);
      expect(codec.matches('EDIT'), isTrue);
      expect(codec.matches('eDiT'), isTrue);
    });

    test('matches all configured tool names', () {
      expect(codec.matches('strreplace'), isTrue);
      expect(codec.matches('notebookedit'), isTrue);
    });

    test('does not match unconfigured tool name', () {
      expect(codec.matches('write'), isFalse);
      expect(codec.matches('unknown'), isFalse);
      expect(codec.matches(''), isFalse);
    });

    test('does not match tool name not in set even with same prefix', () {
      expect(codec.matches('editnotebook'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // encode
  // ---------------------------------------------------------------------------
  group('encode', () {
    test('returns correct AiEditHunk for a simple edit', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/src/main.dart',
          'old_string': 'hello\nworld',
          'new_string': 'goodbye',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/src/main.dart'));
      expect(hunk.addedCount, equals(1));
      expect(hunk.removedCount, equals(2));

      expect(hunk.lines.length, equals(3));

      // First two lines are removes from old_string
      expect(hunk.lines[0].kind, equals(AiEditLineKind.remove));
      expect(hunk.lines[0].text, equals('hello'));
      expect(hunk.lines[0].lineNumber, isNull);

      expect(hunk.lines[1].kind, equals(AiEditLineKind.remove));
      expect(hunk.lines[1].text, equals('world'));
      expect(hunk.lines[1].lineNumber, isNull);

      // Last line is add from new_string
      expect(hunk.lines[2].kind, equals(AiEditLineKind.add));
      expect(hunk.lines[2].text, equals('goodbye'));
      expect(hunk.lines[2].lineNumber, isNull);

      expect(hunk.startLine, isNull);
    });

    test('uses start_line to set line numbers', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'strreplace',
        args: {
          'file_path': '/lib/app.dart',
          'old_string': 'lineA\nlineB',
          'new_string': 'lineC',
          'start_line': 10,
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);

      // old_string lines at line 10, 11
      expect(hunk!.lines[0].lineNumber, equals(10));
      expect(hunk.lines[1].lineNumber, equals(11));

      // new_string line continues after old lines
      expect(hunk.lines[2].lineNumber, equals(12));

      expect(hunk.startLine, equals(10));
    });

    test('uses start_line_num alias for line numbers', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/x.txt',
          'old_string': 'x',
          'new_string': 'y',
          'start_line_num': 5,
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.startLine, equals(5));
    });

    test('prefers start_line over start_line_num', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/x.txt',
          'old_string': 'x',
          'new_string': 'y',
          'start_line': 20,
          'start_line_num': 5,
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.startLine, equals(20));
    });

    test('uses path alias key', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'path': '/alt/path.dart',
          'old_string': 'a',
          'new_string': 'b',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/alt/path.dart'));
    });

    test('prefers file_path over path alias', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/primary.dart',
          'path': '/fallback.dart',
          'old_string': 'a',
          'new_string': 'b',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/primary.dart'));
    });

    test('uses old_str alias key', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/f.txt',
          'old_str': 'search',
          'new_string': 'replace',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.removedCount, equals(1));
      expect(hunk.lines[0].text, equals('search'));
    });

    test('uses new_str alias key', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/f.txt',
          'old_string': 'a',
          'new_str': 'replaced',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.addedCount, equals(1));
      expect(hunk.lines[1].text, equals('replaced'));
    });

    test('decodes argsText JSON', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'notebookedit',
        argsText:
            '{"file_path": "/nb.ipynb", "old_string": "x", "new_string": "y"}',
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/nb.ipynb'));
      expect(hunk.addedCount, equals(1));
      expect(hunk.removedCount, equals(1));
    });

    test('returns null for missing path', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'old_string': 'a',
          'new_string': 'b',
        },
      );

      expect(codec.encode(part), isNull);
    });

    test('missing old_string produces pure-add hunk (NotebookEdit style)', () {
      const codec = StrReplaceEditHunkCodec(
        toolNames: {'notebookedit'},
        pathKeys: ['notebook_path'],
        oldStringKeys: _testOldStringKeys,
        newStringKeys: ['new_source'],
      );
      final part = _makeToolCall(
        toolName: 'NotebookEdit',
        args: {
          'notebook_path': '/nb.ipynb',
          'new_source': 'print(1)',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/nb.ipynb'));
      expect(hunk.addedCount, equals(1));
      expect(hunk.removedCount, equals(0));
    });

    test('caps encoded lines at 500 and keeps full add/remove counts', () {
      final codec = _testCodec();
      final oldLines = List.generate(400, (i) => 'old $i').join('\n');
      final newLines = List.generate(400, (i) => 'new $i').join('\n');
      final hunk = codec.encode(
        _makeToolCall(
          toolName: 'edit',
          args: {
            'file_path': '/f.txt',
            'old_string': oldLines,
            'new_string': newLines,
          },
        ),
      );
      expect(hunk, isNotNull);
      expect(hunk!.removedCount, 400);
      expect(hunk.addedCount, 400);
      expect(hunk.lines.length, 500);
      expect(hunk.lines.first.text, 'old 0');
      expect(hunk.lines[399].text, 'old 399');
      expect(hunk.lines[400].text, 'new 0');
      expect(hunk.lines.last.text, 'new 99');
    });

    test('missing new_string produces pure-remove hunk', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/f.txt',
          'old_string': 'a',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/f.txt'));
      expect(hunk.addedCount, equals(0));
      expect(hunk.removedCount, equals(1));
    });

    test('returns null when both old_string and new_string missing', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {'file_path': '/f.txt'},
      );

      expect(codec.encode(part), isNull);
    });

    test('returns null for non-matching tool name', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'old_string': 'a',
          'new_string': 'b',
        },
      );

      expect(codec.encode(part), isNull);
    });

    test('returns null for empty old_string and new_string', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/f.txt',
          'old_string': '',
          'new_string': '',
        },
      );

      expect(codec.encode(part), isNull);
    });

    test('returns null for null args and argsText', () {
      final codec = _testCodec();
      final part = _makeToolCall(toolName: 'edit');

      expect(codec.encode(part), isNull);
    });

    test('handles multi-line replace with equal line counts', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/f.txt',
          'old_string': 'A\nB\nC',
          'new_string': 'X\nY\nZ',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.addedCount, equals(3));
      expect(hunk.removedCount, equals(3));
      expect(hunk.lines.length, equals(6));

      for (var i = 0; i < 3; i++) {
        expect(hunk.lines[i].kind, equals(AiEditLineKind.remove));
      }
      for (var i = 3; i < 6; i++) {
        expect(hunk.lines[i].kind, equals(AiEditLineKind.add));
      }
    });

    test('handles notebookedit tool name (case-insensitive)', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'NotebookEdit',
        args: {
          'file_path': '/nb.ipynb',
          'old_string': 'old',
          'new_string': 'new',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/nb.ipynb'));
    });

    test('handles empty new_string but non-empty old_string (delete)', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/f.txt',
          'old_string': 'delete\nme',
          'new_string': '',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.addedCount, equals(0));
      expect(hunk.removedCount, equals(2));
      expect(hunk.lines.length, equals(2));
      for (final line in hunk.lines) {
        expect(line.kind, equals(AiEditLineKind.remove));
      }
    });

    test('handles empty old_string but non-empty new_string (insert)', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/f.txt',
          'old_string': '',
          'new_string': 'inserted',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.addedCount, equals(1));
      expect(hunk.removedCount, equals(0));
      expect(hunk.lines.length, equals(1));
      expect(hunk.lines[0].kind, equals(AiEditLineKind.add));
      expect(hunk.lines[0].text, equals('inserted'));
    });
  });

  // ---------------------------------------------------------------------------
  // configurable tool names
  // ---------------------------------------------------------------------------
  group('configurable tool names', () {
    test('only matches tools passed via constructor', () {
      final codec = const StrReplaceEditHunkCodec(
        toolNames: {'myedit'},
        pathKeys: _testPathKeys,
        oldStringKeys: _testOldStringKeys,
        newStringKeys: _testNewStringKeys,
      );

      expect(codec.matches('myedit'), isTrue);
      expect(codec.matches('MYEDIT'), isTrue);
      expect(codec.matches('edit'), isFalse);
      expect(codec.matches('strreplace'), isFalse);
    });

    test('matches empty string only if configured', () {
      final codec = const StrReplaceEditHunkCodec(
        toolNames: {''},
        pathKeys: _testPathKeys,
        oldStringKeys: _testOldStringKeys,
        newStringKeys: _testNewStringKeys,
      );

      expect(codec.matches(''), isTrue);
      expect(codec.matches('edit'), isFalse);
    });
  });
}
