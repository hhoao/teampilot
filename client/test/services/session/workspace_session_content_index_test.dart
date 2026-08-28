import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/session/workspace_session_content_index.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/fake_ai_history_registry.dart';
import '../../support/in_memory_filesystem.dart';

/// Bucket derived by [RuntimeLayout.workspaceBucketForPrimaryPath] for the
/// fixture primary path `/ws/project`.
const bucket = '-ws-project';

void main() {
  group('buildTranscriptDoc', () {
    test(
      'projects roles, text, reasoning and tool calls into searchable text',
      () {
        final messages = [
          AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'Fix the widget color to red')],
          ),
          AiMessage(
            id: 'a1',
            role: AiRole.assistant,
            parts: [
              AiTextPart(text: 'I will update settings_page.dart'),
              AiToolCallPart(
                toolCallId: 't1',
                toolName: 'Edit',
                argsText: '{"file":"settings_page.dart"}',
              ),
            ],
          ),
        ];

        final doc = buildTranscriptDoc(messages);
        final lower = doc.text.toLowerCase();
        expect(lower, contains('red'));
        expect(lower, contains('settings_page.dart'));
        expect(lower, contains('[tool] edit'));
        expect(lower, contains('user:'));
        expect(lower, contains('assistant:'));
        expect(doc.messageStarts, hasLength(2));
      },
    );
  });

  group('caseInsensitiveIndexOf', () {
    test('matches case-insensitively on the original string', () {
      expect(
        WorkspaceSessionContentIndex.caseInsensitiveIndexOf(
          'Hello WORLD',
          'world',
        ),
        6,
      );
      expect(
        WorkspaceSessionContentIndex.caseInsensitiveIndexOf(
          'Hello WORLD',
          '  world ',
        ),
        6,
      );
    });

    test('is length-safe for Unicode lowercase expansions', () {
      // 'ß' lowercases to 'ss' (length change), so an index computed on a
      // lowercased copy would misalign against the original text.
      const text = 'Größe fix the color';
      final idx = WorkspaceSessionContentIndex.caseInsensitiveIndexOf(
        text,
        'fix',
      );
      expect(idx, isNotNull);
      expect(text.substring(idx!), startsWith('fix'));
      expect(idx! + 'fix'.length, lessThanOrEqualTo(text.length));
    });

    test('returns null for blanks and non-matches', () {
      expect(
        WorkspaceSessionContentIndex.caseInsensitiveIndexOf('abc', '   '),
        isNull,
      );
      expect(
        WorkspaceSessionContentIndex.caseInsensitiveIndexOf('abc', 'z'),
        isNull,
      );
    });
  });

  group('WorkspaceSessionContentIndex', () {
    late InMemoryFilesystem fs;
    const root = '/tp-root';
    const wsRoot = '/ws/project';

    setUp(() {
      fs = InMemoryFilesystem();
    });

    WorkspaceSessionContentIndex buildIndex() => WorkspaceSessionContentIndex(
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: root, fs: fs),
      appDataRoot: root,
    );

    AppSession simpleSession({String sessionId = 'sess-1'}) => AppSession(
      sessionId: sessionId,
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: wsRoot)],
      cli: CliTool.claude,
      createdAt: 0,
    );

    Future<void> writeSimpleTranscript(String sessionId) async {
      await fs.writeString(
        '$root/cli-defaults/claude/projects/$bucket/$sessionId.jsonl',
        transcriptJsonl,
      );
    }

    test('warms a simple seat and finds content by query', () async {
      await writeSimpleTranscript('sess-1');
      final index = buildIndex();
      final sessions = [simpleSession()];

      await index.warm(sessions: sessions);

      final matches = index.search('red', sessions: sessions);
      expect(matches, hasLength(1));
      expect(matches.single.session.sessionId, 'sess-1');
      expect(matches.single.memberId, isEmpty);
      expect(matches.single.snippet.toLowerCase(), contains('red'));
      expect(matches.single.messageIndex, 0);
    });

    test('matches tool calls inside a transcript', () async {
      await writeSimpleTranscript('sess-1');
      final index = buildIndex();
      final sessions = [simpleSession()];

      await index.warm(sessions: sessions);

      final matches = index.search('Edit', sessions: sessions);
      expect(matches, hasLength(1));
      expect(matches.single.snippet.toLowerCase(), contains('edit'));
    });

    test(
      'returns no matches for a session with no locatable transcript',
      () async {
        final index = buildIndex();
        final sessions = [simpleSession()];

        await index.warm(sessions: sessions);
        expect(index.search('anything', sessions: sessions), isEmpty);
      },
    );

    test('empty query yields no content matches', () async {
      await writeSimpleTranscript('sess-1');
      final index = buildIndex();
      final sessions = [simpleSession()];

      await index.warm(sessions: sessions);
      expect(index.search('   ', sessions: sessions), isEmpty);
    });

    test('unwarmed seats contribute nothing', () async {
      await writeSimpleTranscript('sess-1');
      final index = buildIndex();
      final sessions = [simpleSession()];

      // search() before warm: nothing indexed yet.
      expect(index.search('red', sessions: sessions), isEmpty);
    });

    test('warm is idempotent across repeated calls', () async {
      await writeSimpleTranscript('sess-1');
      final index = buildIndex();
      final sessions = [simpleSession()];

      await index.warm(sessions: sessions);
      await index.warm(sessions: sessions);

      expect(index.search('settings_page', sessions: sessions), hasLength(1));
    });

    test('searches the member seat of a team session', () async {
      final teamSession = AppSession(
        sessionId: 'team-1',
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: wsRoot)],
        sessionTeam: 'my-team',
        cli: CliTool.claude,
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'dev-0',
            taskId: 'task-0',
            typeId: 'dev',
            cli: CliTool.claude,
          ),
        ],
        createdAt: 0,
      );
      await fs.writeString(
        '$root/identities-runtime/my-team/claude/projects/$bucket/task-0.jsonl',
        transcriptJsonl,
      );
      final index = buildIndex();
      final sessions = [teamSession];

      await index.warm(sessions: sessions);

      final matches = index.search('red', sessions: sessions);
      expect(matches, hasLength(1));
      expect(matches.single.session.sessionId, 'team-1');
      expect(matches.single.memberId, 'dev-0');
      expect(matches.single.memberLabel, 'dev');
    });

    test('warm reuses chat history messages when the source token matches',
        () async {
      var parseCalls = 0;
      final cached = [
        AiMessage(
          id: 'cached',
          role: AiRole.user,
          parts: [AiTextPart(text: 'cached red widget')],
        ),
      ];
      final registry = fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: _CountingParseAdapter(() => parseCalls++),
        locate: (_) async => const AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(name: 's.jsonl', bytes: [0x7B, 0x7D]),
          ],
          hints: {'cacheToken': 'tok-1'},
        ),
      );
      final index = WorkspaceSessionContentIndex(
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: root, fs: fs),
        appDataRoot: root,
        registry: registry,
        cachedHistoryMessages: ({
          required sessionId,
          required memberId,
          required token,
        }) {
          if (token == 'tok-1') return cached;
          return null;
        },
      );
      final sessions = [simpleSession()];

      await index.warm(sessions: sessions);

      expect(parseCalls, 0);
      final matches = index.search('red', sessions: sessions);
      expect(matches, hasLength(1));
      expect(matches.single.snippet.toLowerCase(), contains('red'));
    });

    test('invalidateSession drops a session so it no longer matches', () async {
      await writeSimpleTranscript('sess-1');
      final index = buildIndex();
      final sessions = [simpleSession()];
      await index.warm(sessions: sessions);
      expect(index.search('red', sessions: sessions), isNotEmpty);

      index.invalidateSession('sess-1');
      // After invalidation the seat is unwarmed until the next warm.
      expect(index.search('red', sessions: sessions), isEmpty);
    });
  });
}

const transcriptJsonl =
    ''
    '{"type":"user","message":{"id":"u1","content":"Fix the widget color to red"}}\n'
    '{"type":"assistant","message":{"id":"a1","content":[{"type":"text",'
    '"text":"I will update settings_page.dart to use the brand color."},'
    '{"type":"tool_use","id":"t1","name":"Edit",'
    '"input":{"file":"settings_page.dart"}}]}}\n';

class _CountingParseAdapter implements AiTranscriptAdapter {
  _CountingParseAdapter(this._onParse);

  final void Function() _onParse;

  @override
  String get id => 'counting';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    _onParse();
    return const [];
  }
}
