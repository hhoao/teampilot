import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_live_refresh_controller.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  late _ScriptedLocator locator;
  late List<AiMessage> holderMessages;
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

  List<AiMessage> messages(int count) => [
    for (var i = 0; i < count; i++)
      AiMessage(
        id: 'm-$i',
        role: AiRole.user,
        parts: [AiTextPart(text: 'msg-$i')],
      ),
  ];

  AiHistoryLiveRefreshController buildController({
    Future<AiHistoryWatchMeta?> Function()? resolveWatchMeta,
    Filesystem Function()? fsFn,
    Duration? metaRetryInterval,
  }) {
    return AiHistoryLiveRefreshController(
      cubit: cubit,
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
    holderMessages = const [];
    locator = _ScriptedLocator();
    fs = InMemoryFilesystem();
    lastSignal = null;
    pollIntervals = [];
    final layout = RuntimeLayout(
      teampilotRoot: '/tmp/ai-history-live-refresh',
      fs: LocalFilesystem(),
    );
    loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      fs: () => LocalFilesystem(),
      layout: () => layout,
      appDataRoot: () => '/tmp/ai-history-live-refresh',
      locator: locator,
      adapters: {
        CliTool.claude: _HolderAdapter(() => holderMessages),
      },
      resolveCacheToken: (_) async => 'token',
    );
    cubit = AiHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test('start attaches signal and softReloads on change', () async {
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.state.totalMessageCount, 2);

    final controller = buildController();
    await controller.start();

    expect(lastSignal, isNotNull);
    expect(lastSignal!.started, isTrue);
    expect(pollIntervals, [const Duration(milliseconds: 1200)]);

    holderMessages = messages(3);
    lastSignal!.fire();
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();

    expect(cubit.state.totalMessageCount, 3);

    await controller.stop();
  });

  test(
    'start(skipInitialRefresh: true) attaches signal without softReload',
    () async {
      holderMessages = messages(2);
      locator.emitBundle = true;
      await cubit.load(session: simpleSession(), memberId: '');
      expect(cubit.state.totalMessageCount, 2);

      var softReloadPasses = 0;
      locator.onLocate = () async {
        softReloadPasses++;
        return _dummyBundle();
      };

      final controller = buildController();
      await controller.start(skipInitialRefresh: true);

      expect(lastSignal, isNotNull);
      expect(lastSignal!.started, isTrue);
      // Load path already softReloadOrLoad'd — do not stack a second softReload.
      expect(softReloadPasses, 0);
      expect(cubit.state.totalMessageCount, 2);

      holderMessages = messages(3);
      lastSignal!.fire();
      await pumpEventQueue();
      expect(softReloadPasses, 1);
      expect(cubit.state.totalMessageCount, 3);

      await controller.stop();
    },
  );

  test('second change while reload in flight coalesces to one follow-up', () async {
    holderMessages = messages(1);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');

    final gate = Completer<void>();
    var softReloadPasses = 0;
    locator.onLocate = () async {
      softReloadPasses++;
      // First locate after start's refreshNow is immediate; subsequent
      // softReloads from signal wait on [gate] so we can fire coalesced changes.
      if (softReloadPasses >= 2) {
        await gate.future;
      }
      return _dummyBundle();
    };

    final controller = buildController();
    await controller.start();
    // start → refreshNow → softReload (pass 1) + signal attached
    expect(softReloadPasses, 1);
    expect(lastSignal!.started, isTrue);

    holderMessages = messages(2);
    lastSignal!.fire();
    await pumpEventQueue();
    expect(softReloadPasses, 2); // in flight, waiting on gate

    holderMessages = messages(4);
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
    holderMessages = messages(2);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');

    final controller = buildController();
    await controller.start();
    final signal = lastSignal!;
    expect(signal.started, isTrue);

    await controller.stop();
    expect(signal.stopped, isTrue);

    holderMessages = messages(9);
    signal.fire();
    await pumpEventQueue();

    expect(cubit.state.totalMessageCount, 2);
  });

  test('FsWatcher poll interval is 750ms', () async {
    holderMessages = messages(1);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');

    final watchable = _WatchableFs();
    final controller = buildController(fsFn: () => watchable);
    await controller.start();

    expect(pollIntervals, [const Duration(milliseconds: 750)]);
    await controller.stop();
  });

  test('null watch meta keeps signal; later meta softReloads and rearms', () async {
    holderMessages = messages(1);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');
    expect(cubit.state.totalMessageCount, 1);

    AiHistoryWatchMeta? meta;
    var resolveCount = 0;
    final controller = buildController(
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
    holderMessages = messages(3);

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
    holderMessages = messages(1);
    locator.emitBundle = true;
    await cubit.load(session: simpleSession(), memberId: '');

    const stableMeta = AiHistoryWatchMeta(
      changeWatchRoot: '/proj',
      cacheTokenPaths: ['/proj/a.jsonl'],
    );
    final resolveBlock = Completer<void>();
    var resolveCount = 0;

    final controller = buildController(
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

    holderMessages = messages(4);
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

AiTranscriptBundle _dummyBundle() => const AiTranscriptBundle(
  adapterId: 'claude',
  fragments: [
    AiTranscriptFragment(name: 'canned.jsonl', bytes: []),
  ],
);

class _HolderAdapter implements AiTranscriptAdapter {
  _HolderAdapter(this._messages);

  final List<AiMessage> Function() _messages;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async =>
      List.of(_messages());
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
    return _dummyBundle();
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
