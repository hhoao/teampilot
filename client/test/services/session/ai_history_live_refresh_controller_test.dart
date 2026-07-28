import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_live_refresh_controller.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/history_seat_key.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/fake_ai_history_registry.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  late _ScriptedLocator locator;
  late Map<String, List<AiMessage>> messagesBySession;
  late AiHistoryLoader loader;
  late AiHistoryCubit cubit;
  late InMemoryFilesystem fs;
  late _FakeSignal? lastSignal;
  late List<Duration> pollIntervals;

  AppSession simpleSession({String id = 'sess-a'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
    updatedAt: 1,
  );

  WorkspaceLaunchContext launchCtx(AppSession s) => WorkspaceLaunchContext(
    session: s,
    workspace: Workspace(
      workspaceId: s.workspaceId,
      folders: s.folders,
      createdAt: 0,
    ),
  );

  List<AiMessage> messages(int count, {String prefix = 'm'}) => [
    for (var i = 0; i < count; i++)
      AiMessage(
        id: '$prefix-$i',
        role: AiRole.user,
        parts: [AiTextPart(text: 'msg-$prefix-$i')],
      ),
  ];

  AiHistorySeat seatFor(AppSession session) => cubit.ensureSeat(
    sessionId: session.sessionId,
    selectedMemberId: '',
  );

  AiHistoryLiveRefreshController buildController({
    AiHistorySeat? seat,
    Future<AiHistoryWatchMeta?> Function()? resolveWatchMeta,
    Filesystem Function()? fsFn,
    Duration? metaRetryInterval,
  }) {
    final session = simpleSession();
    return AiHistoryLiveRefreshController(
      seat: seat ?? seatFor(session),
      fs: fsFn ?? () => fs,
      resolveWatchMeta:
          resolveWatchMeta ??
          () async => const AiHistoryWatchMeta(
            changeWatchRoot: '/proj',
            cacheTokenPaths: ['/proj/a.jsonl'],
          ),
      metaRetryInterval: metaRetryInterval,
      createSignal:
          ({
            required Filesystem fs,
            required String? Function() watchRoot,
            required List<String> Function() cacheTokenPaths,
            required void Function() onChanged,
            required Duration pollInterval,
          }) {
            pollIntervals.add(pollInterval);
            final signal = _FakeSignal(onChanged: onChanged);
            lastSignal = signal;
            return signal;
          },
    );
  }

  setUp(() {
    setUpTestAppStorage();
    messagesBySession = {};
    locator = _ScriptedLocator();
    fs = InMemoryFilesystem();
    lastSignal = null;
    pollIntervals = [];
    loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: LocalFilesystem(),
        home: '/tmp/ai-history-live-refresh',
        cwd: '/tmp/ai-history-live-refresh',
        appDataRoot: '/tmp/ai-history-live-refresh',
        paths: AppPaths('/tmp/ai-history-live-refresh'),
      ),
      locator: locator,
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: _SessionMapAdapter(() => messagesBySession),
      ),
      resolveCacheToken: (_) async => 'token',
    );
    cubit = AiHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test('refreshNow softReloads bound seat only', () async {
    locator.emitBundle = true;
    final sessionA = simpleSession(id: 'sess-a');
    final sessionB = simpleSession(id: 'sess-b');
    messagesBySession['sess-a'] = messages(2, prefix: 'a');
    messagesBySession['sess-b'] = messages(2, prefix: 'b');

    await cubit.load(
      session: sessionA,
      memberId: '',
      launchContext: launchCtx(sessionA),
    );
    await cubit.load(
      session: sessionB,
      memberId: '',
      launchContext: launchCtx(sessionB),
    );

    final seatA = seatFor(sessionA);
    final seatB = seatFor(sessionB);
    expect(seatA.state.totalMessageCount, 2);
    expect(seatB.state.totalMessageCount, 2);
    final bIdsBefore = seatB.runtime.messages.map((m) => m.id).toList();

    // B is focused (last load). Controller must still softReload only A.
    messagesBySession['sess-a'] = [
      ...messages(2, prefix: 'a'),
      const AiMessage(
        id: 'a-tip',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'extra-a-tip')],
      ),
    ];

    final controller = buildController(seat: seatA);
    await controller.start(skipInitialRefresh: true);
    lastSignal!.fire();
    await pumpEventQueue();

    expect(seatA.state.totalMessageCount, 3);
    expect(
      seatA.runtime.messages.any((m) => m.id == 'a-tip'),
      isTrue,
    );
    expect(seatB.state.totalMessageCount, 2);
    expect(
      seatB.runtime.messages.map((m) => m.id).toList(),
      bIdsBefore,
    );

    await controller.stop();
  });

  test('warm seat policy stops an active live refresh controller', () async {
    final session = simpleSession();
    messagesBySession[session.sessionId] = messages(1);
    locator.emitBundle = true;
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );

    final controller = buildController(seat: seatFor(session));
    await controller.ensureStarted(skipInitialRefresh: true);
    expect(controller.isActive, isTrue);

    // Mirrors SessionChatView warm path: !isHistorySeatHot → stop.
    expect(
      isHistorySeatHot(routeActive: false, isMemberRunning: false),
      isFalse,
    );
    await controller.stop();
    expect(controller.isActive, isFalse);
    expect(lastSignal?.stopped, isTrue);
  });

  test('start attaches signal and softReloads on change', () async {
    final session = simpleSession();
    messagesBySession[session.sessionId] = messages(2);
    locator.emitBundle = true;
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );
    expect(cubit.state.totalMessageCount, 2);

    final controller = buildController(seat: seatFor(session));
    await controller.start();

    expect(lastSignal, isNotNull);
    expect(lastSignal!.started, isTrue);
    expect(pollIntervals, [const Duration(milliseconds: 1200)]);

    messagesBySession[session.sessionId] = messages(3);
    lastSignal!.fire();
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();

    expect(cubit.state.totalMessageCount, 3);

    await controller.stop();
  });

  test(
    'start(skipInitialRefresh: true) attaches signal without softReload',
    () async {
      final session = simpleSession();
      messagesBySession[session.sessionId] = messages(2);
      locator.emitBundle = true;
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      expect(cubit.state.totalMessageCount, 2);

      var softReloadPasses = 0;
      locator.onLocate = () async {
        softReloadPasses++;
        return _dummyBundle(session.sessionId);
      };

      final controller = buildController(seat: seatFor(session));
      await controller.start(skipInitialRefresh: true);

      expect(lastSignal, isNotNull);
      expect(lastSignal!.started, isTrue);
      // Load path already softReloadOrLoad'd — do not stack a second softReload.
      expect(softReloadPasses, 0);
      expect(cubit.state.totalMessageCount, 2);

      messagesBySession[session.sessionId] = messages(3);
      lastSignal!.fire();
      await pumpEventQueue();
      expect(softReloadPasses, 1);
      expect(cubit.state.totalMessageCount, 3);

      await controller.stop();
    },
  );

  test('second change while reload in flight coalesces to one follow-up', () async {
    final session = simpleSession();
    messagesBySession[session.sessionId] = messages(1);
    locator.emitBundle = true;
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );

    final gate = Completer<void>();
    var softReloadPasses = 0;
    locator.onLocate = () async {
      softReloadPasses++;
      // First locate after start's refreshNow is immediate; subsequent
      // softReloads from signal wait on [gate] so we can fire coalesced changes.
      if (softReloadPasses >= 2) {
        await gate.future;
      }
      return _dummyBundle(session.sessionId);
    };

    final controller = buildController(seat: seatFor(session));
    await controller.start();
    // start → refreshNow → softReload (pass 1) + signal attached
    expect(softReloadPasses, 1);
    expect(lastSignal!.started, isTrue);

    messagesBySession[session.sessionId] = messages(2);
    lastSignal!.fire();
    await pumpEventQueue();
    expect(softReloadPasses, 2); // in flight, waiting on gate

    messagesBySession[session.sessionId] = messages(4);
    lastSignal!.fire();
    lastSignal!.fire();
    await pumpEventQueue();
    // Coalesced — still only one in-flight follow-up.
    expect(softReloadPasses, 2);

    gate.complete();
    await pumpEventQueue();
    // One coalesced follow-up after the in-flight reload finishes.
    expect(softReloadPasses, 3);
    expect(cubit.state.totalMessageCount, 4);

    await controller.stop();
  });

  test('stop cancels signal and ignores late callbacks', () async {
    final session = simpleSession();
    messagesBySession[session.sessionId] = messages(2);
    locator.emitBundle = true;
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );

    final controller = buildController(seat: seatFor(session));
    await controller.start();
    final signal = lastSignal!;
    expect(signal.started, isTrue);

    await controller.stop();
    expect(signal.stopped, isTrue);

    messagesBySession[session.sessionId] = messages(9);
    signal.fire();
    await pumpEventQueue();

    expect(cubit.state.totalMessageCount, 2);
  });

  test('FsWatcher poll interval is 750ms', () async {
    final session = simpleSession();
    messagesBySession[session.sessionId] = messages(1);
    locator.emitBundle = true;
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );

    final watchable = _WatchableFs();
    final controller = buildController(
      seat: seatFor(session),
      fsFn: () => watchable,
    );
    await controller.start();

    expect(pollIntervals, [const Duration(milliseconds: 750)]);
    await controller.stop();
  });

  test('null watch meta keeps signal; later meta softReloads and rearms', () async {
    final session = simpleSession();
    messagesBySession[session.sessionId] = messages(1);
    locator.emitBundle = true;
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );
    expect(cubit.state.totalMessageCount, 1);

    AiHistoryWatchMeta? meta;
    var resolveCount = 0;
    final controller = buildController(
      seat: seatFor(session),
      metaRetryInterval: const Duration(milliseconds: 20),
      resolveWatchMeta: () async {
        resolveCount++;
        return meta;
      },
    );
    await controller.start();

    expect(lastSignal, isNotNull);
    expect(lastSignal!.started, isTrue);
    final firstSignal = lastSignal!;
    expect(resolveCount, greaterThanOrEqualTo(1));
    expect(cubit.state.totalMessageCount, 1);

    meta = const AiHistoryWatchMeta(
      changeWatchRoot: '/proj',
      cacheTokenPaths: ['/proj/a.jsonl'],
    );
    messagesBySession[session.sessionId] = messages(3);

    // Interval re-resolve (pre-locate) must find meta without a prior onChanged.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pumpEventQueue();

    expect(resolveCount, greaterThan(1));
    expect(cubit.state.totalMessageCount, 3);
    expect(lastSignal, isNot(same(firstSignal)));
    expect(lastSignal!.started, isTrue);
    expect(firstSignal.stopped, isTrue);

    await controller.stop();
  });

  test('resolveWatchMeta throw keeps last meta and drains coalesced queue', () async {
    final session = simpleSession();
    messagesBySession[session.sessionId] = messages(1);
    locator.emitBundle = true;
    await cubit.load(
      session: session,
      memberId: '',
      launchContext: launchCtx(session),
    );

    const stableMeta = AiHistoryWatchMeta(
      changeWatchRoot: '/proj',
      cacheTokenPaths: ['/proj/a.jsonl'],
    );
    final resolveBlock = Completer<void>();
    var resolveCount = 0;

    final controller = buildController(
      seat: seatFor(session),
      resolveWatchMeta: () async {
        resolveCount++;
        if (resolveCount == 2) {
          await resolveBlock.future;
          throw StateError('resolve failed');
        }
        return stableMeta;
      },
    );
    await controller.start();
    expect(resolveCount, 1);
    expect(cubit.state.totalMessageCount, 1);

    lastSignal!.fire();
    await pumpEventQueue();
    expect(resolveCount, 2); // blocked before throw

    messagesBySession[session.sessionId] = messages(4);
    lastSignal!.fire(); // coalesce while resolve #2 is in flight
    await pumpEventQueue();
    expect(resolveCount, 2);

    resolveBlock.complete();
    await pumpEventQueue();
    // finally must reschedule queued work; last good meta kept for closures.
    expect(resolveCount, greaterThanOrEqualTo(3));
    expect(cubit.state.totalMessageCount, 4);

    await controller.stop();
  });
}

AiTranscriptBundle _dummyBundle([String sessionId = 'sess-a']) =>
    AiTranscriptBundle(
      adapterId: 'claude',
      fragments: const [
        AiTranscriptFragment(name: 'canned.jsonl', bytes: []),
      ],
      hints: {'sessionId': sessionId},
    );

class _SessionMapAdapter implements AiTranscriptAdapter {
  _SessionMapAdapter(this._messagesBySession);

  final Map<String, List<AiMessage>> Function() _messagesBySession;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    final sessionId = bundle.hints['sessionId'] ?? '';
    return List.of(_messagesBySession()[sessionId] ?? const []);
  }
}

class _ScriptedLocator extends AiHistoryLocator {
  bool emitBundle = false;
  Object? error;
  final queue = <Future<AiTranscriptBundle?>>[];
  Future<AiTranscriptBundle?> Function()? onLocate;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    if (error != null) throw error!;
    if (onLocate != null) return onLocate!();
    if (queue.isNotEmpty) return queue.removeAt(0);
    if (!emitBundle) return null;
    final sessionId = ctx.sessionId?.trim() ?? '';
    return _dummyBundle(sessionId);
  }
}

class _FakeSignal implements TranscriptChangeSignalHandle {
  _FakeSignal({required this.onChanged});

  final void Function() onChanged;
  var started = false;
  var stopped = false;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void fire() => onChanged();
}

class _WatchableFs extends InMemoryFilesystem implements FsWatcher {
  @override
  FsTreeWatch watchTree(String path) {
    return FsTreeWatch(
      events: const Stream.empty(),
      close: () async {},
    );
  }
}
