import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/claude_ai_transcript.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late Directory base;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  var mtimeToken = 'mtime-1';

  AppSession simpleSession({String id = 'sess-a'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
    updatedAt: 1,
  );

  AiHistoryLoader buildLoader({
    AiHistoryLocator locator = const AiHistoryLocator(),
    Map<CliTool, AiTranscriptAdapter>? adapters,
  }) {
    return AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      fs: () => fs,
      layout: () => layout,
      appDataRoot: () => base.path,
      locator: locator,
      adapters: adapters,
      resolveCacheToken: (_) async => mtimeToken,
    );
  }

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('ai_history_loader_');
    fs = LocalFilesystem(
      pathContext: p.Context(style: p.Style.posix, current: base.path),
    );
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
  });

  tearDown(() {
    if (base.existsSync()) {
      base.deleteSync(recursive: true);
    }
    tearDownTestAppStorage();
  });

  test('missing transcript returns empty list', () async {
    final messages = await buildLoader().load(
      session: simpleSession(),
      memberId: '',
    );
    expect(messages, isEmpty);
  });

  test('parses Claude fixture bytes via locate + adapter', () async {
    final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
    final sessionId = 'sess-a';
    final toolRoot = layout.sessionRuntimeToolDir('ws-1', sessionId, 'claude');
    final projects = p.join(toolRoot, 'projects', bucket);
    await Directory(projects).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/claude/basic.jsonl',
    ).readAsBytes();
    await File(p.join(projects, '$sessionId.jsonl')).writeAsBytes(fixture);

    final messages = await buildLoader().load(
      session: simpleSession(id: sessionId),
      memberId: '',
    );

    expect(messages, isNotEmpty);
    expect(messages.first.id, 'u-1');
    expect(messages.first.role, AiRole.user);
    expect(
      messages.where((m) => m.role == AiRole.assistant),
      isNotEmpty,
    );
  });

  test('throws StateError when adapter missing for launch CLI', () async {
    final loader = buildLoader(adapters: const {});
    await expectLater(
      () => loader.load(session: simpleSession(), memberId: ''),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('AiTranscriptAdapter missing'),
        ),
      ),
    );
  });

  test('mtime unchanged reuses cache on reload', () async {
    var locateCalls = 0;
    final locator = _CountingLocator(() async {
      locateCalls++;
      return null;
    });
    final loader = buildLoader(locator: locator);

    final session = simpleSession();
    expect(await loader.load(session: session, memberId: ''), isEmpty);
    expect(locateCalls, 1);

    expect(await loader.load(session: session, memberId: ''), isEmpty);
    expect(locateCalls, 1);

    mtimeToken = 'mtime-2';
    expect(await loader.load(session: session, memberId: ''), isEmpty);
    expect(locateCalls, 2);
  });

  test('default adapters include Claude', () {
    expect(
      AiHistoryLoader.defaultAdapters[CliTool.claude],
      isA<ClaudeAiTranscriptAdapter>(),
    );
  });
}

class _CountingLocator extends AiHistoryLocator {
  _CountingLocator(this._onLocate);

  final Future<AiTranscriptBundle?> Function() _onLocate;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) =>
      _onLocate();
}
