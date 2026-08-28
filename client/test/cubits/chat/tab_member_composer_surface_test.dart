import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/member_connector.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_member_coordination_factory.dart';
import 'package:teampilot/cubits/chat/member_input_ready_wait.dart';
import 'package:teampilot/cubits/chat/tab_member_materializer.dart';
import 'package:teampilot/cubits/chat/tab_member_pty_delivery.dart';
import 'package:teampilot/cubits/chat/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../integration/support/connected_recording_shell.dart';
import '../../support/post_frame_test_harness.dart';
import '../../support/rust_lib_test_init.dart';

class _NoopConnector implements MemberConnector {
  @override
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab,
  ) {}
}

const _sessionId = 'sess-codex';
const _memberId = 'sess-codex';

Future<String> _waitForWindow(
  TerminalSession session,
  bool Function(String window) match, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  var last = '';
  while (DateTime.now().isBefore(deadline)) {
    await session.probe.syncDisplayGrid();
    last = session.probe.describeProbeWindow(scanRows: 52);
    if (match(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return last;
}

void main() {
  setUpAll(initRustLibForTests);
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('Codex splash is not a composer surface after boot frame', () async {
    final harness = await _ComposerHarness.connect(cli: CliTool.codex);
    addTearDown(harness.dispose);

    await harness.paintTrustScreen();
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isFalse,
    );
  });

  test('Codex composer chrome is not ready until dwell elapses', () async {
    final harness = await _ComposerHarness.connect(cli: CliTool.codex);
    addTearDown(harness.dispose);

    await harness.paintComposer();
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isFalse,
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isTrue,
    );
  });

  test('Codex resume history streaming keeps composer unready', () async {
    final harness = await _ComposerHarness.connect(cli: CliTool.codex);
    addTearDown(harness.dispose);

    await harness.paintComposer();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await harness.paintHistory('user: 提交吧');
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isFalse,
      reason: 'streaming resume history must restart composer dwell',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isTrue,
    );
  });

  test('Cursor composer chrome is not ready until dwell elapses', () async {
    final harness = await _ComposerHarness.connect(cli: CliTool.cursor);
    addTearDown(harness.dispose);

    await harness.paintCursorComposer();
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isFalse,
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isTrue,
    );
  });

  test('Cursor full-screen flicker keeps composer unready', () async {
    final harness = await _ComposerHarness.connect(cli: CliTool.cursor);
    addTearDown(harness.dispose);

    await harness.paintCursorComposer();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await harness.paintFlickerFrame('thinking');
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isFalse,
      reason: 'startup redraws must restart Cursor composer dwell',
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isTrue,
    );
  });

  test('Claude boot frame is enough without composer chrome', () async {
    final harness = await _ComposerHarness.connect(cli: CliTool.claude);
    addTearDown(harness.dispose);

    await harness.paintTrustScreen();
    expect(
      harness.delivery.isMemberComposerSurfaceReady(_sessionId, _memberId),
      isTrue,
    );
  });

  test('Codex doorbell defers on splash even after boot frame', () async {
    final harness = await _ComposerHarness.connect(cli: CliTool.codex);
    addTearDown(harness.dispose);

    await harness.paintTrustScreen();
    await harness.delivery
        .deliverMemberStdin(
          _sessionId,
          _memberId,
          TeamBus.doorbellNotice,
          automation: true,
          latchUserTurn: false,
        )
        .timeout(const Duration(seconds: 2));

    expect(
      harness.shell.ptyInputJoined.contains(TeamBus.doorbellNotice),
      isFalse,
    );
    expect(harness.shell.ptyInputJoined.contains('\r'), isTrue);
  });

  test(
    'ensureMemberInputReady waits for Codex composer then proceeds',
    () async {
      final harness = await _ComposerHarness.connect(cli: CliTool.codex);
      addTearDown(harness.dispose);
      await harness.paintTrustScreen();

      var completed = false;
      final pending = harness.materializer
          .ensureMemberInputReady(_sessionId, _memberId, directToPty: true)
          .then((_) => completed = true);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(completed, isFalse);
      expect(harness.shell.ptyInputJoined.contains('\r'), isTrue);

      await harness.paintComposer();
      await pending.timeout(const Duration(seconds: 2));
      expect(completed, isTrue);
    },
  );

  test(
    'ensureMemberInputReady times out on short cap without composer',
    () async {
      final harness = await _ComposerHarness.connect(cli: CliTool.codex);
      addTearDown(harness.dispose);

      final started = DateTime.now();
      await expectLater(
        harness.materializer.ensureMemberInputReady(
          _sessionId,
          _memberId,
          directToPty: true,
          waitCap: const Duration(milliseconds: 250),
        ),
        throwsA(
          isA<MemberInputReadyException>().having(
            (e) => e.failure,
            'failure',
            MemberInputReadyFailure.timedOut,
          ),
        ),
      );
      expect(
        DateTime.now().difference(started) < const Duration(seconds: 5),
        isTrue,
        reason: 'cap must not fall back to a 120s wall clock',
      );
    },
  );

  test('ensureMemberInputReady aborts when the shell dies', () async {
    final harness = await _ComposerHarness.connect(cli: CliTool.codex);
    addTearDown(harness.dispose);

    final pending = harness.materializer.ensureMemberInputReady(
      _sessionId,
      _memberId,
      directToPty: true,
      waitCap: const Duration(seconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    harness.shell.session.failLaunch('test kill');

    await expectLater(
      pending,
      throwsA(
        isA<MemberInputReadyException>().having(
          (e) => e.failure,
          'failure',
          MemberInputReadyFailure.dead,
        ),
      ),
    );
  });
}

final class _ComposerHarness {
  _ComposerHarness({
    required this.store,
    required this.shell,
    required this.delivery,
    required this.ptyInject,
    required this.materializer,
  });

  final ChatTabStore store;
  final ConnectedRecordingShell shell;
  final TabMemberPtyDelivery delivery;
  final MemberPtyInjectService ptyInject;
  final TabMemberMaterializer materializer;

  static Future<_ComposerHarness> connect({required CliTool cli}) async {
    final store = ChatTabStore();
    store.setActiveWorkspaceId('ws-1');
    final tab =
        ChatTab(
            info: const ChatTabInfo(id: _sessionId, title: 't', subtitle: ''),
            workspaceId: 'ws-1',
            cliTeamName: '',
          )
          ..persistedSession = AppSession(
            sessionId: _sessionId,
            workspaceId: 'ws-1',
            sessionTeam: '',
            cli: cli,
            createdAt: 0,
          );
    store.registerSession(tab);

    final shell = await ConnectedRecordingShell.connect();
    tab.memberShells[_memberId] = shell.session;
    shell.session.activityTracker.latchBootFrameReadyForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );

    final ptyInject = MemberPtyInjectService();
    final delivery = TabMemberPtyDelivery(
      tabStore: store,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: TabMemberCoordinationFactory(
        tabStore: store,
        globalPresets: () => const [],
        activeTeam: () => null,
      ),
      ptyInject: ptyInject,
    );
    final runtime = TabSessionRuntimeCoordinator(
      tabStore: store,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      delivery: delivery,
    );
    final materializer = TabMemberMaterializer(
      runtime: runtime,
      tabStore: store,
      connector: _NoopConnector(),
      activeTeam: () => null,
      isClosed: () => false,
      isMixedBusRegistered: (_) => false,
      isMemberConnectOwnedElsewhere: (_, _) => false,
    );
    return _ComposerHarness(
      store: store,
      shell: shell,
      delivery: delivery,
      ptyInject: ptyInject,
      materializer: materializer,
    );
  }

  Future<void> paintTrustScreen() async {
    await shell.emitPtyOutput(
      'Do you trust this directory?\r\nPress enter\r\n',
    );
    final window = await _waitForWindow(
      shell.session,
      (text) => text.contains('trust') || text.contains('Press enter'),
    );
    expect(
      window.contains('trust') || window.contains('Press enter'),
      isTrue,
      reason: 'trust screen should land on the probe grid\n$window',
    );
  }

  Future<void> paintCursorComposer() async {
    await shell.emitPtyOutput('→ Plan, search\r\n');
    final window = await _waitForWindow(
      shell.session,
      (text) => text.contains('→'),
    );
    expect(
      window.contains('→'),
      isTrue,
      reason: 'Cursor composer chrome should land on the probe grid\n$window',
    );
  }

  Future<void> paintFlickerFrame(String line) async {
    await shell.emitPtyOutput('$line\r\n');
    final window = await _waitForWindow(
      shell.session,
      (text) => text.contains(line),
    );
    expect(
      window.contains(line),
      isTrue,
      reason: 'flicker frame should land on the probe grid\n$window',
    );
  }

  Future<void> paintComposer() async {
    await shell.emitPtyOutput('gpt-5.6-luna default · /tmp\r\n› \r\n');
    final window = await _waitForWindow(
      shell.session,
      (text) => text.contains('default ·') || text.contains('›'),
    );
    expect(
      window.contains('default ·') || window.contains('›'),
      isTrue,
      reason: 'composer chrome should land on the probe grid\n$window',
    );
  }

  Future<void> paintHistory(String line) async {
    await shell.emitPtyOutput('$line\r\n');
    final window = await _waitForWindow(
      shell.session,
      (text) => text.contains(line),
    );
    expect(
      window.contains(line),
      isTrue,
      reason: 'history line should land on the probe grid\n$window',
    );
  }

  Future<void> dispose() => shell.dispose();
}
