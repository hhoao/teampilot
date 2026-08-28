import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/cli/opencode/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/cli/registry/capabilities/shared_tool_call_resolvers.dart';

AiToolCallPart part(String name, {String? argsText, Map<String, Object?>? args}) {
  return AiToolCallPart(
    toolCallId: 'call_1',
    toolName: name,
    args: args,
    argsText: argsText,
  );
}

void main() {
  const shared = SharedToolCallResolvers();

  group('共享层治理：key/toolName 集精确固定', () {
    // 治理标准（plan Task 5）：每个名称/键须有 ≥2 个 CLI 的矩阵证据；
    // 单 CLI 特有的下沉到拥有者 CLI 文件；无证据的移除。
    test('edit 各集只含共享项（strreplace/editnotebook 下沉至 cursor，'
        'oldString/newString 下沉至 opencode，file/target_file/start_line 无证据移除）',
        () {
      expect(SharedToolCallResolverKeys.editToolNames, {'edit', 'notebookedit'});
      expect(SharedToolCallResolverKeys.editPathKeys,
          ['file_path', 'notebook_path']);
      expect(SharedToolCallResolverKeys.editOldStringKeys, ['old_string']);
      expect(
        SharedToolCallResolverKeys.editNewStringKeys,
        ['new_string', 'new_source'],
      );
    });

    test('write 各集只含共享项（writefile/write_file/create/create_file/'
        'contents 无证据移除）', () {
      expect(SharedToolCallResolverKeys.writeToolNames, {'write'});
      expect(SharedToolCallResolverKeys.writePathKeys, ['file_path']);
      expect(SharedToolCallResolverKeys.writeContentKeys, ['content']);
    });

    test('diff 集保持共享（codec 能力层：codex + opencode 共用配置族）', () {
      expect(SharedToolCallResolverKeys.diffToolNames,
          {'applypatch', 'apply_patch'});
      expect(SharedToolCallResolverKeys.diffPatchKeys, ['patch', 'diff', 'input']);
    });

    test('file 各集只含共享项（readfile/read_file 无证据移除）', () {
      expect(SharedToolCallResolverKeys.fileReadToolNames, {'read'});
      expect(SharedToolCallResolverKeys.fileWriteToolNames, {'write'});
      expect(SharedToolCallResolverKeys.fileEditToolNames,
          {'edit', 'applypatch', 'notebookedit'});
    });

    test('shell 各集只含共享项（shell/run_shell_command/run_terminal_cmd '
        '由 cursor 专属覆写保留，无 ≥2 CLI 证据）', () {
      expect(
        SharedToolCallResolverKeys.shellToolNames,
        {'bash', 'shell_command', 'exec_command'},
      );
    });
  });

  group('共享层基线族仍可解析（claude/flashskyai 同源面）', () {
    test('editResolver returns the same target instance for the same part', () {
      final call = part(
        'Write',
        args: {
          'file_path': 'a.txt',
          'content': List.generate(80, (i) => 'line $i').join('\n'),
        },
      );
      final first = shared.editResolver.resolve(call);
      final second = shared.editResolver.resolve(call);
      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
    });

    test('Edit{file_path, old_string, new_string} 解析出 hunk', () {
      final target = shared.editResolver.resolve(part(
        'Edit',
        args: {
          'file_path': 'a.txt',
          'old_string': 'foo',
          'new_string': 'bar',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'a.txt');
    });

    test('NotebookEdit{notebook_path, new_source} 解析出 hunk', () {
      final target = shared.editResolver.resolve(part(
        'NotebookEdit',
        args: {'notebook_path': '/tmp/demo.ipynb', 'new_source': 'print(1)'},
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/tmp/demo.ipynb');
      expect(target.hunk.addedCount, 1);
    });

    test('Write{file_path, content} 解析出 hunk', () {
      final target = shared.editResolver.resolve(part(
        'Write',
        args: {'file_path': 'new.txt', 'content': 'line1'},
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'new.txt');
    });

    test('Read{file_path} 解析出文件目标', () {
      final target =
          shared.fileResolver.resolve(part('Read', args: {'file_path': 'a.dart'}));
      expect(target, isNotNull);
      expect(target!.path, 'a.dart');
    });

    test('Bash{command} 解析出命令', () {
      final target =
          shared.shellResolver.resolve(part('Bash', args: {'command': 'ls'}));
      expect(target, isNotNull);
      expect(target!.command, 'ls');
    });

    test('apply_patch FREEFORM（codex）经共享 diff codec 解析出 hunk', () {
      final target = shared.editResolver.resolve(part(
        'apply_patch',
        argsText: '''*** Begin Patch
*** Update File: lib/foo.dart
@@ -1,2 +1,3 @@
-removed
+added
*** End Patch''',
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'lib/foo.dart');
    });
  });

  group('下沉项不在共享层解析（由拥有者 CLI 提供）', () {
    test('strreplace / editnotebook 不在共享 editResolver 解析', () {
      expect(
        shared.editResolver.resolve(part(
          'StrReplace',
          args: {'file_path': 'a.txt', 'old_string': 'x', 'new_string': 'y'},
        )),
        isNull,
      );
      expect(
        shared.editResolver.resolve(part(
          'EditNotebook',
          args: {'notebook_path': '/tmp/a.ipynb', 'new_source': 'x'},
        )),
        isNull,
      );
    });

    test('camelCase oldString/newString（opencode 特有）不在共享 editResolver 解析',
        () {
      expect(
        shared.editResolver.resolve(part(
          'edit',
          args: {'filePath': 'a.txt', 'oldString': 'x', 'newString': 'y'},
        )),
        isNull,
      );
    });

    test('Shell（cursor 特有名）不在共享 shellResolver 解析', () {
      expect(
        shared.shellResolver
            .resolve(part('Shell', args: {'command': 'pwd'})),
        isNull,
      );
    });

    test('无证据别名不在共享层解析（writefile/create_file/readfile/'
        'run_shell_command/run_terminal_cmd）', () {
      expect(
        shared.editResolver
            .resolve(part('writefile', args: {'file_path': 'a', 'content': 'b'})),
        isNull,
      );
      expect(
        shared.editResolver
            .resolve(part('create_file', args: {'file_path': 'a', 'content': 'b'})),
        isNull,
      );
      expect(shared.fileResolver.resolve(part('readfile', args: {'path': 'a'})),
          isNull);
      expect(
        shared.shellResolver
            .resolve(part('run_shell_command', args: {'command': 'pwd'})),
        isNull,
      );
      expect(
        shared.shellResolver
            .resolve(part('run_terminal_cmd', args: {'command': 'pwd'})),
        isNull,
      );
    });

    test('cursor 特有键 path/contents 不在共享层解析（G-4 下沉项）', () {
      expect(
        shared.editResolver.resolve(part(
          'Edit',
          args: {'path': 'a.txt', 'old_string': 'x', 'new_string': 'y'},
        )),
        isNull,
        reason: 'path 为 cursor 特有键，共享 editPathKeys 无',
      );
      expect(
        shared.editResolver.resolve(part(
          'Write',
          args: {'file_path': 'a.txt', 'contents': 'b'},
        )),
        isNull,
        reason: 'contents 为 cursor 特有键，共享 writeContentKeys 无',
      );
    });
  });

  group('下沉项在拥有者 CLI 可解析', () {
    const cursor = CursorToolCallResolvers();
    const opencode = OpencodeToolCallResolvers();

    test('cursor：StrReplace / EditNotebook 解析出 hunk', () {
      final strTarget = cursor.editResolver.resolve(part(
        'StrReplace',
        args: {'file_path': 'a.txt', 'old_string': 'foo', 'new_string': 'bar'},
      ));
      expect(strTarget, isNotNull);
      expect(strTarget!.hunk.path, 'a.txt');

      final notebookTarget = cursor.editResolver.resolve(part(
        'EditNotebook',
        args: {'notebook_path': '/tmp/demo.ipynb', 'new_source': 'print(1)'},
      ));
      expect(notebookTarget, isNotNull);
      expect(notebookTarget!.hunk.path, '/tmp/demo.ipynb');
    });

    test('cursor：Shell 解析出命令', () {
      final target =
          cursor.shellResolver.resolve(part('Shell', args: {'command': 'pwd'}));
      expect(target, isNotNull);
      expect(target!.command, 'pwd');
    });

    test('opencode：edit{filePath, oldString, newString} 解析出 hunk', () {
      final target = opencode.editResolver.resolve(part(
        'edit',
        args: {'filePath': 'a.txt', 'oldString': 'x', 'newString': 'y'},
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'a.txt');
    });
  });
}
