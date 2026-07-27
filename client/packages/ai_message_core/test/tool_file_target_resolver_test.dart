import 'package:ai_message_core/ai_message_core.dart';
import 'package:test/test.dart';

void main() {
  const resolver = DefaultAiToolFileTargetResolver();

  AiToolCallPart part({
    required String toolName,
    Map<String, Object?>? args,
    String? argsText,
  }) {
    return AiToolCallPart(
      toolCallId: 'tc1',
      toolName: toolName,
      args: args,
      argsText: argsText,
    );
  }

  group('DefaultAiToolFileTargetResolver', () {
    test('Read file_path + offset/limit → start 110 end 189', () {
      final target = resolver.resolve(
        part(
          toolName: 'Read',
          args: {
            'file_path': 'lib/foo.dart',
            'offset': 110,
            'limit': 80,
          },
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/foo.dart');
      expect(target.startLine, 110);
      expect(target.endLine, 189);
    });

    test('WriteFile path; no lines', () {
      final target = resolver.resolve(
        part(
          toolName: 'WriteFile',
          args: {'path': 'lib/bar.dart'},
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/bar.dart');
      expect(target.startLine, isNull);
      expect(target.endLine, isNull);
    });

    test('StrReplace start_line/end_line', () {
      final target = resolver.resolve(
        part(
          toolName: 'StrReplace',
          args: {
            'file_path': 'lib/edit.dart',
            'start_line': 5,
            'end_line': 12,
          },
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/edit.dart');
      expect(target.startLine, 5);
      expect(target.endLine, 12);
    });

    test('L-range from argsText', () {
      final target = resolver.resolve(
        part(
          toolName: 'Read',
          args: {'file_path': 'lib/history.dart'},
          argsText: 'Reading lib/history.dart L110-189',
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/history.dart');
      expect(target.startLine, 110);
      expect(target.endLine, 189);
    });

    test('Bash → null; missing path → null', () {
      expect(
        resolver.resolve(
          part(toolName: 'Bash', args: {'command': 'ls'}),
        ),
        isNull,
      );
      expect(
        resolver.resolve(
          part(toolName: 'Read', args: {'offset': 1, 'limit': 10}),
        ),
        isNull,
      );
    });

    test('case-insensitive tool names', () {
      final target = resolver.resolve(
        part(
          toolName: 'read_file',
          args: {'file_path': 'a.dart'},
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'a.dart');

      expect(
        resolver.resolve(
          part(toolName: 'WRITE', args: {'path': 'b.dart'}),
        )?.path,
        'b.dart',
      );
      expect(
        resolver.resolve(
          part(toolName: 'strreplace', args: {'path': 'c.dart'}),
        )?.path,
        'c.dart',
      );
    });

    test('file_path before path precedence', () {
      final target = resolver.resolve(
        part(
          toolName: 'Read',
          args: {
            'file_path': 'preferred.dart',
            'path': 'ignored.dart',
          },
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'preferred.dart');
    });
  });

  group('CompositeAiToolFileTargetResolver', () {
    test('returns first non-null resolver result', () {
      const composite = CompositeAiToolFileTargetResolver([
        DefaultAiToolFileTargetResolver(),
      ]);

      final target = composite.resolve(
        part(toolName: 'Read', args: {'file_path': 'x.dart'}),
      );

      expect(target?.path, 'x.dart');
    });
  });
}
