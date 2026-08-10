import 'package:ai_message_core/ai_message_core.dart'
    hide WriteEditHunkCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/edit_codecs/write_edit_hunk_codec.dart';

/// Test codec configuration matching the original built-in codec defaults.
const _testToolNames = {
  'write',
  'writefile',
  'write_file',
  'create',
  'create_file',
};
const _testPathKeys = ['file_path', 'path'];
const _testContentKeys = ['content', 'contents'];

WriteEditHunkCodec _testCodec() => const WriteEditHunkCodec(
      toolNames: _testToolNames,
      pathKeys: _testPathKeys,
      contentKeys: _testContentKeys,
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
      expect(codec.matches('write'), isTrue);
    });

    test('matches tool name with different casing', () {
      expect(codec.matches('Write'), isTrue);
      expect(codec.matches('WRITE'), isTrue);
      expect(codec.matches('wRiTe'), isTrue);
    });

    test('matches all configured tool names', () {
      expect(codec.matches('writefile'), isTrue);
      expect(codec.matches('write_file'), isTrue);
      expect(codec.matches('create'), isTrue);
      expect(codec.matches('create_file'), isTrue);
    });

    test('does not match unconfigured tool name', () {
      expect(codec.matches('edit'), isFalse);
      expect(codec.matches('unknown'), isFalse);
      expect(codec.matches(''), isFalse);
    });

    test('does not match tool name not in set even with same prefix', () {
      expect(codec.matches('writefilex'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // encode
  // ---------------------------------------------------------------------------
  group('encode', () {
    test('returns correct AiEditHunk for a simple write', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/src/main.dart',
          'content': 'hello\nworld\nfoo',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/src/main.dart'));
      expect(hunk.addedCount, equals(3));
      expect(hunk.removedCount, equals(0));

      expect(hunk.lines.length, equals(3));

      expect(hunk.lines[0].kind, equals(AiEditLineKind.add));
      expect(hunk.lines[0].text, equals('hello'));
      expect(hunk.lines[0].lineNumber, isNull);

      expect(hunk.lines[1].kind, equals(AiEditLineKind.add));
      expect(hunk.lines[1].text, equals('world'));

      expect(hunk.lines[2].kind, equals(AiEditLineKind.add));
      expect(hunk.lines[2].text, equals('foo'));
    });

    test('uses path alias key', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'path': '/alt/path.dart',
          'content': 'data',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/alt/path.dart'));
    });

    test('prefers file_path over path alias', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/primary.dart',
          'path': '/fallback.dart',
          'content': 'data',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/primary.dart'));
    });

    test('uses contents alias key', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'contents': 'some content',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.addedCount, equals(1));
      expect(hunk.lines[0].text, equals('some content'));
    });

    test('prefers content over contents', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'content': 'primary content',
          'contents': 'fallback content',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.lines[0].text, equals('primary content'));
    });

    test('decodes argsText JSON', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        argsText:
            '{"file_path": "/nb.ipynb", "content": "line1\\nline2\\nline3"}',
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/nb.ipynb'));
      expect(hunk.addedCount, equals(3));
      expect(hunk.removedCount, equals(0));
    });

    test('returns null for missing path', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'content': 'data',
        },
      );

      expect(codec.encode(part), isNull);
    });

    test('returns null for missing content', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
        },
      );

      expect(codec.encode(part), isNull);
    });

    test('returns null for non-matching tool name', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'edit',
        args: {
          'file_path': '/f.txt',
          'content': 'data',
        },
      );

      expect(codec.encode(part), isNull);
    });

    test('returns null for empty content', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'content': '',
        },
      );

      expect(codec.encode(part), isNull);
    });

    test('returns null for null args and argsText', () {
      final codec = _testCodec();
      final part = _makeToolCall(toolName: 'write');

      expect(codec.encode(part), isNull);
    });

    test('case-insensitive tool name matching in encode', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'WriteFile',
        args: {
          'file_path': '/f.txt',
          'content': 'data',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/f.txt'));
    });

    test('handles single-line content', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'content': 'single line',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.addedCount, equals(1));
      expect(hunk.lines.length, equals(1));
      expect(hunk.lines[0].text, equals('single line'));
    });

    test('enforces max encoded lines limit', () {
      final codec = _testCodec();
      // Create content with 600 lines
      final lines = List.generate(600, (i) => 'line $i').join('\n');
      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'content': lines,
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      // addedCount reflects full count, but encoded lines are capped
      expect(hunk!.addedCount, equals(600));
      expect(hunk.lines.length, equals(500));
      expect(hunk.lines.first.text, equals('line 0'));
      expect(hunk.lines.last.text, equals('line 499'));
    });

    test('create tool name works for encode', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'create',
        args: {
          'file_path': '/new_file.dart',
          'content': 'class NewFile {}',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/new_file.dart'));
    });

    test('create_file tool name works for encode', () {
      final codec = _testCodec();
      final part = _makeToolCall(
        toolName: 'create_file',
        args: {
          'file_path': '/another.dart',
          'content': 'void main() {}',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.path, equals('/another.dart'));
    });
  });

  // ---------------------------------------------------------------------------
  // configurable tool names
  // ---------------------------------------------------------------------------
  group('configurable tool names', () {
    test('only matches tools passed via constructor', () {
      final codec = const WriteEditHunkCodec(
        toolNames: {'mywrite'},
        pathKeys: _testPathKeys,
      );

      expect(codec.matches('mywrite'), isTrue);
      expect(codec.matches('MYWRITE'), isTrue);
      expect(codec.matches('write'), isFalse);
      expect(codec.matches('create'), isFalse);
    });

    test('matches empty string only if configured', () {
      final codec = const WriteEditHunkCodec(
        toolNames: {''},
        pathKeys: _testPathKeys,
      );

      expect(codec.matches(''), isTrue);
      expect(codec.matches('write'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // configurable content keys
  // ---------------------------------------------------------------------------
  group('configurable content keys', () {
    test('uses custom content keys', () {
      final codec = const WriteEditHunkCodec(
        toolNames: {'write'},
        pathKeys: ['file_path'],
        contentKeys: ['body', 'text'],
      );

      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'body': 'custom body content',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.lines[0].text, equals('custom body content'));
    });

    test('prefers first custom content key', () {
      final codec = const WriteEditHunkCodec(
        toolNames: {'write'},
        pathKeys: ['file_path'],
        contentKeys: ['body', 'text'],
      );

      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'body': 'first choice',
          'text': 'second choice',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.lines[0].text, equals('first choice'));
    });

    test('falls back to second custom content key', () {
      final codec = const WriteEditHunkCodec(
        toolNames: {'write'},
        pathKeys: ['file_path'],
        contentKeys: ['body', 'text'],
      );

      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'text': 'second choice',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.lines[0].text, equals('second choice'));
    });

    test('default contentKeys are content and contents', () {
      final codec = const WriteEditHunkCodec(
        toolNames: {'write'},
        pathKeys: ['file_path'],
      );

      final part = _makeToolCall(
        toolName: 'write',
        args: {
          'file_path': '/f.txt',
          'contents': 'contents key works',
        },
      );

      final hunk = codec.encode(part);
      expect(hunk, isNotNull);
      expect(hunk!.lines[0].text, equals('contents key works'));
    });
  });
}
