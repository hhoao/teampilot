import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/antigravity/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';

AiToolCallPart part(String name, {Map<String, Object?>? args}) =>
    AiToolCallPart(toolCallId: 'call_1', toolName: name, args: args);

void main() {
  const cap = AntigravityAiHistoryCapability();
  const resolvers = AntigravityToolCallResolvers.instance;

  test('history is ACP-owned and exposes resolvers', () {
    expect(cap.adapter.id, 'antigravity');
    expect(cap.tailFallbackPrefix, 'antigravity');
    expect(cap.editResolver, isNotNull);
    expect(cap.fileResolver, isNotNull);
    expect(cap.shellResolver, isNotNull);
    expect(cap.categoryResolver, isNotNull);
  });

  test('ACP-owned history parses nothing and resumes post-captured', () async {
    expect(
      await cap.adapter.parse(
        const AiTranscriptBundle(adapterId: 'antigravity', fragments: []),
      ),
      isEmpty,
    );
    expect(cap.binding, ResumeBinding.postCaptured);
    expect(cap.subagentToolNames, {'invoke_subagent'});
  });

  test('sessionEnv derives the isolated home from the config dir', () {
    final home = p.join('runtime', 'tool', 'home');
    final configDir = p.join(home, '.gemini', 'config');
    expect(cap.sessionEnv(toolRoot: configDir), {
      'HOME': home,
      'USERPROFILE': home,
      'GEMINI_HOME': p.join(home, '.gemini'),
    });
    expect(cap.sessionEnv(), isEmpty);
  });

  group('tool-call resolvers', () {
    test(
      'replace_file_content maps TargetFile/TargetContent to an edit hunk',
      () {
        final target = resolvers.editResolver.resolve(
          part(
            'replace_file_content',
            args: {
              'TargetFile': '/src/main.dart',
              'TargetContent': 'hello',
              'ReplacementContent': 'goodbye',
            },
          ),
        );
        expect(target, isNotNull);
        expect(target!.hunk.path, '/src/main.dart');
        expect(target.hunk.removedCount, 1);
        expect(target.hunk.addedCount, 1);
        expect(
          target.hunk.lines
              .firstWhere((line) => line.kind == AiEditLineKind.remove)
              .text,
          'hello',
        );
        expect(
          target.hunk.lines
              .firstWhere((line) => line.kind == AiEditLineKind.add)
              .text,
          'goodbye',
        );
      },
    );

    test('write_to_file maps TargetFile/CodeContent to a write hunk', () {
      final target = resolvers.editResolver.resolve(
        part(
          'write_to_file',
          args: {'TargetFile': '/src/new.dart', 'CodeContent': 'a\nb'},
        ),
      );
      expect(target, isNotNull);
      expect(target!.hunk.path, '/src/new.dart');
      expect(target.hunk.addedCount, 2);
      expect(target.hunk.removedCount, 0);
    });

    test('view_file maps AbsolutePath to a file target', () {
      final target = resolvers.fileResolver.resolve(
        part('view_file', args: {'AbsolutePath': '/src/main.dart'}),
      );
      expect(target, isNotNull);
      expect(target!.path, '/src/main.dart');
    });

    test('view_file maps StartLine/EndLine to a line range', () {
      final target = resolvers.fileResolver.resolve(
        part(
          'view_file',
          args: {
            'AbsolutePath': '/src/main.dart',
            'StartLine': 10,
            'EndLine': 20,
          },
        ),
      );
      expect(target, isNotNull);
      expect(target!.path, '/src/main.dart');
      expect(target.startLine, 10);
      expect(target.endLine, 20);
    });

    test('multi_replace_file_content does not claim edit hunk support', () {
      final args = <String, Object?>{
        'TargetFile': '/src/main.dart',
        'ReplacementChunks': [
          {'TargetContent': 'a', 'ReplacementContent': 'b'},
        ],
      };
      expect(
        resolvers.editResolver.resolve(
          part('multi_replace_file_content', args: args),
        ),
        isNull,
      );
      expect(
        resolvers.fileResolver
            .resolve(part('multi_replace_file_content', args: args))
            ?.path,
        '/src/main.dart',
      );
      expect(
        resolvers.categoryResolver.resolve(
          part('multi_replace_file_content', args: args),
        ),
        AiToolCallCategory.edit,
      );
    });

    test('run_command maps CommandLine to a shell target', () {
      final target = resolvers.shellResolver.resolve(
        part('run_command', args: {'CommandLine': 'flutter analyze'}),
      );
      expect(target, isNotNull);
      expect(target!.command, 'flutter analyze');
    });

    test('shared resolver behavior is retained', () {
      expect(
        resolvers.shellResolver
            .resolve(part('bash', args: {'command': 'pwd'}))
            ?.command,
        'pwd',
      );
      expect(
        resolvers.fileResolver
            .resolve(part('read', args: {'file_path': '/a.dart'}))
            ?.path,
        '/a.dart',
      );
    });

    test('category mapping covers representative Antigravity tools', () {
      const expected = <String, AiToolCallCategory>{
        'run_command': AiToolCallCategory.command,
        'view_file': AiToolCallCategory.read,
        'write_to_file': AiToolCallCategory.write,
        'replace_file_content': AiToolCallCategory.edit,
        'multi_replace_file_content': AiToolCallCategory.edit,
        'list_dir': AiToolCallCategory.read,
        'find_by_name': AiToolCallCategory.read,
        'grep_search': AiToolCallCategory.read,
        'search_web': AiToolCallCategory.search,
        'read_url_content': AiToolCallCategory.search,
        'invoke_subagent': AiToolCallCategory.subagent,
        'send_message': AiToolCallCategory.subagent,
        'manage_task': AiToolCallCategory.task,
        'schedule': AiToolCallCategory.task,
        'ask_question': AiToolCallCategory.askUser,
        'generate_image': AiToolCallCategory.other,
      };
      expected.forEach((name, category) {
        expect(
          resolvers.categoryResolver.resolve(part(name)),
          category,
          reason: name,
        );
      });
    });
  });
}
