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

    test('end_line without start_line → single line at end', () {
      final target = resolver.resolve(
        part(
          toolName: 'StrReplace',
          args: {
            'file_path': 'lib/edit.dart',
            'end_line': 12,
          },
        ),
      );

      expect(target, isNotNull);
      expect(target!.startLine, 12);
      expect(target.endLine, 12);
    });

    test('L110 single-line from argsText', () {
      final target = resolver.resolve(
        part(
          toolName: 'Read',
          args: {'file_path': 'lib/single.dart'},
          argsText: 'Reading lib/single.dart L110',
        ),
      );

      expect(target, isNotNull);
      expect(target!.startLine, 110);
      expect(target.endLine, 110);
    });

    test('camelCase startLine/endLine args', () {
      final target = resolver.resolve(
        part(
          toolName: 'Edit',
          args: {
            'path': 'lib/camel.dart',
            'startLine': 3,
            'endLine': 7,
          },
        ),
      );

      expect(target, isNotNull);
      expect(target!.path, 'lib/camel.dart');
      expect(target.startLine, 3);
      expect(target.endLine, 7);
    });

    test('file and target_file path keys', () {
      expect(
        resolver.resolve(
          part(toolName: 'Create', args: {'file': 'lib/create.dart'}),
        )?.path,
        'lib/create.dart',
      );
      expect(
        resolver.resolve(
          part(
            toolName: 'ApplyPatch',
            args: {'target_file': 'lib/patch.dart'},
          ),
        )?.path,
        'lib/patch.dart',
      );
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

    test('custom null falls through to default', () {
      const composite = CompositeAiToolFileTargetResolver([
        _NullResolver(),
        DefaultAiToolFileTargetResolver(),
      ]);

      final target = composite.resolve(
        part(toolName: 'Read', args: {'file_path': 'fallback.dart'}),
      );

      expect(target?.path, 'fallback.dart');
    });

    test('custom target preferred over default', () {
      const composite = CompositeAiToolFileTargetResolver([
        _FixedResolver(
          const AiToolFileTarget(path: 'custom.dart', startLine: 1, endLine: 2),
        ),
        DefaultAiToolFileTargetResolver(),
      ]);

      final target = composite.resolve(
        part(toolName: 'Read', args: {'file_path': 'default.dart'}),
      );

      expect(target?.path, 'custom.dart');
      expect(target?.startLine, 1);
      expect(target?.endLine, 2);
    });
  });
}

class _NullResolver implements AiToolFileTargetResolver {
  const _NullResolver();

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) => null;
}

class _FixedResolver implements AiToolFileTargetResolver {
  const _FixedResolver(this.target);

  final AiToolFileTarget target;

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) => target;
}
