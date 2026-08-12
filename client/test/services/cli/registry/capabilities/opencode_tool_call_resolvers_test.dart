import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/opencode/capabilities/tool_call_resolvers.dart';

void main() {
  const resolvers = OpencodeToolCallResolvers();

  AiToolCallPart toolCall(String name, Map<String, Object?> args) {
    return AiToolCallPart(
      toolCallId: 'call-1',
      toolName: name,
      args: args,
    );
  }

  group('editResolver', () {
    test('edit with camelCase filePath/oldString/newString resolves to hunk',
        () {
      final target = resolvers.editResolver.resolve(toolCall('edit', {
        'filePath': '/src/main.dart',
        'oldString': 'hello',
        'newString': 'goodbye',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/src/main.dart');
      expect(target.hunk.removedCount, 1);
      expect(target.hunk.addedCount, 1);
      expect(target.hunk.lines[0].kind, AiEditLineKind.remove);
      expect(target.hunk.lines[1].kind, AiEditLineKind.add);
    });

    test('write with camelCase filePath/content resolves to hunk', () {
      final target = resolvers.editResolver.resolve(toolCall('write', {
        'filePath': '/lib/app.dart',
        'content': 'line1\nline2',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/lib/app.dart');
      expect(target.hunk.addedCount, 2);
      expect(target.hunk.removedCount, 0);
    });

    test('legacy snake_case file_path still resolves', () {
      final target = resolvers.editResolver.resolve(toolCall('edit', {
        'file_path': '/old.dart',
        'old_string': 'a',
        'new_string': 'b',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/old.dart');
    });

    test('bash tool does not resolve as edit', () {
      final target =
          resolvers.editResolver.resolve(toolCall('bash', {'command': 'ls'}));
      expect(target, isNull);
    });
  });

  group('fileResolver', () {
    test('read with filePath + offset/limit resolves with line range', () {
      final target = resolvers.fileResolver.resolve(toolCall('read', {
        'filePath': '/a.dart',
        'offset': 10,
        'limit': 5,
      }));
      expect(target, isNotNull);
      expect(target!.path, '/a.dart');
      expect(target.startLine, 10);
      expect(target.endLine, 14);
    });

    test('edit with filePath resolves to file target', () {
      final target = resolvers.fileResolver.resolve(toolCall('edit', {
        'filePath': '/a.dart',
        'oldString': 'x',
        'newString': 'y',
      }));
      expect(target, isNotNull);
      expect(target!.path, '/a.dart');
    });

    test('write with filePath resolves to file target', () {
      final target = resolvers.fileResolver.resolve(toolCall('write', {
        'filePath': '/b.dart',
        'content': 'c',
      }));
      expect(target, isNotNull);
      expect(target!.path, '/b.dart');
    });
  });

  group('shellResolver', () {
    test('bash with command resolves', () {
      final target =
          resolvers.shellResolver.resolve(toolCall('bash', {'command': 'ls -la'}));
      expect(target, isNotNull);
      expect(target!.command, 'ls -la');
    });
  });
}
