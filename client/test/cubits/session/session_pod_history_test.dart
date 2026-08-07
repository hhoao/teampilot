import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/history_store.dart';
import 'package:teampilot/cubits/session/session_pod.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/fake_ai_history_registry.dart';
import '../../support/post_frame_test_harness.dart';

class _FakeAdapter implements AiTranscriptAdapter {
  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}

AiHistoryLoader _stubLoader() => AiHistoryLoader(
  contextBuilder: const SessionHistoryContextBuilder(),
  resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
    target: RuntimeTarget.local(),
    filesystem: LocalFilesystem(),
    home: '/tmp/session-pod-history',
    cwd: '/tmp/session-pod-history',
    appDataRoot: '/tmp/session-pod-history',
    paths: AppPaths('/tmp/session-pod-history'),
  ),
  registry: fakeAiHistoryRegistry(
    cli: CliTool.claude,
    adapter: _FakeAdapter(),
  ),
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('SessionPod owns a HistoryStore and exposes member seats', () {
    final pod = SessionPod(
      sessionId: 's1',
      workspaceId: 'w1',
      history: HistoryStore(loader: _stubLoader()),
    );
    final seatA = pod.history!.memberSeat(sessionId: 's1', memberId: '');
    final seatB = pod.history!.memberSeat(sessionId: 's1', memberId: 'm');
    expect(
      identical(seatA, pod.history!.memberSeat(sessionId: 's1', memberId: '')),
      isTrue,
    );
    expect(identical(seatA, seatB), isFalse);
  });
}
