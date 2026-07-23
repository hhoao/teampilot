import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/scenarios/mixed_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/native_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:mock_model_gateway/server.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/session_chat_continue_seat.dart';
import 'package:teampilot/pages/chat/session_history_review_submit.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team_bus/mcp/bus_bridge_locator.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';
import 'package:teampilot/services/terminal/terminal_export.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

import '../../support/post_frame_test_harness.dart';
import 'bus_mail_assertions.dart';
import 'bus_roster_assertions.dart';
import 'chat_thread_assertions.dart';
import 'cli_test_profile.dart';
import 'integration_prerequisites.dart';

const kMatrixLeaderProviderId = 'mock-leader';
const kMatrixWorkerProviderId = 'mock-worker';
const kMatrixSimpleProviderId = 'mock-simple';

/// Model id written into mock provider catalogs / session launch argv.
///
/// Prefer [matrixMockModelIdFor] when multiple flashskyai providers share one
/// `llm_config.json` — duplicate keys overwrite and flashskyai rejects
/// `--provider A --model` owned by B.
const kMatrixMockModelId = 'mock-model';

String matrixMockModelIdFor(String providerId) => '$providerId-model';

const kMatrixLeadMemberId = 'team-lead';
const kMatrixWorkerMemberId = 'worker-1';

/// Default last-N lines kept from PTY dumps in [diagnosticsBundle].
const kMatrixPtyDumpMaxLines = 40;

/// Matrix cell mode (simple / native team / mixed TeamBus).
enum CliMatrixMode { simple, native, mixed }

/// Shared gateway recipe for a matrix cell.
enum CliMatrixRecipe { simple3Turn, nativeCollab3Plus, mixedCollab3Plus }

/// Redacts common secret shapes from failure dumps (sk-* / Bearer tokens).
String redactMatrixSecrets(String text) {
  var out = text.replaceAllMapped(
    RegExp(r'sk-[A-Za-z0-9_-]{8,}'),
    (_) => 'sk-[REDACTED]',
  );
  out = out.replaceAllMapped(
    RegExp(
      r'(Bearer\s+)[A-Za-z0-9._\-+=/]{8,}',
      caseSensitive: false,
    ),
    (m) => '${m[1]}[REDACTED]',
  );
  return out;
}

/// Keeps the last [maxLines] lines (prefix notes how many were dropped).
String truncateMatrixDumpLastLines(
  String text, {
  int maxLines = kMatrixPtyDumpMaxLines,
}) {
  final lines = const LineSplitter().convert(text);
  if (lines.length <= maxLines) return text;
  final skipped = lines.length - maxLines;
  return '… ($skipped lines truncated)\n'
      '${lines.sublist(skipped).join('\n')}';
}

/// Truncate + redact for PTY / diagnostics dumps.
String sanitizeMatrixPtyDump(
  String text, {
  int maxLines = kMatrixPtyDumpMaxLines,
}) =>
    truncateMatrixDumpLastLines(redactMatrixSecrets(text), maxLines: maxLines);

/// Homogeneous CLI × mode harness for L2 matrix cells (Task 8+).
///
/// Drives History compose via [submitSessionHistoryReviewMessage] (same as
/// production) — never [ChatCubit] stdin shortcuts as the operator send.
///
/// Does **not** fully green an L2 cell by itself (boot gates / live refresh
/// timing land in Task 9); it must compile and be callable from those cells.
final class CliMessageMatrixHarness {
  CliMessageMatrixHarness({
    required this.profile,
    required this.mode,
    CliMatrixRecipe? recipe,
    String? cliPath,
  }) : recipe = recipe ?? defaultRecipeFor(mode),
       cliPath = cliPath ?? profile.resolveBinary() ?? profile.binaryName;

  factory CliMessageMatrixHarness.forCli(
    CliTool tool, {
    required CliMatrixMode mode,
    CliMatrixRecipe? recipe,
    String? cliPath,
  }) {
    return CliMessageMatrixHarness(
      profile: CliTestProfiles.forTool(tool),
      mode: mode,
      recipe: recipe,
      cliPath: cliPath,
    );
  }

  static CliMatrixRecipe defaultRecipeFor(CliMatrixMode mode) => switch (mode) {
    CliMatrixMode.simple => CliMatrixRecipe.simple3Turn,
    CliMatrixMode.native => CliMatrixRecipe.nativeCollab3Plus,
    CliMatrixMode.mixed => CliMatrixRecipe.mixedCollab3Plus,
  };

  final CliTestProfile profile;
  final CliMatrixMode mode;
  final CliMatrixRecipe recipe;
  final String cliPath;

  MockModelGatewayServer? gateway;
  ChatCubit? cubit;
  AiHistoryCubit? history;
  SessionLifecycleService? lifecycle;
  AppSession? session;
  TeamProfile? team;
  Workspace? workspace;
  PostFrameTestHarness? postFrame;

  /// Mirrors [SessionChatView] mailbox Queued rows for assertions without a
  /// pumped widget tree (removed on [promoteMailboxConsumed]).
  final List<PendingUserMessage> mailboxQueued = [];

  /// Append-only Queued submissions — survives promote so
  /// [expectMailboxQueuedThenSticky] can prove Queued → sticky.
  final List<PendingUserMessage> mailboxQueuedSubmitted = [];

  HistoryContinueSubmitResult? lastSubmitResult;

  /// Compose-seat assistant markers for [mode]: simple → MARK_A*;
  /// native/mixed → [CliTestProfile.collabLeadMarkers].
  List<String> get composeSeatAssistantMarkers => switch (mode) {
    CliMatrixMode.simple => profile.assistantVisibleMarkers,
    CliMatrixMode.native || CliMatrixMode.mixed => profile.collabLeadMarkers,
  };

  String? _savedBusBridgeEnv;
  bool _envOverrideApplied = false;
  String? _savedBusBridgeDebugOverride;
  bool _busBridgeDebugOverrideApplied = false;

  String get mockBaseUrl => gateway!.baseUri.toString();

  int get mockPort => gateway!.port;

  /// Simple seat uses session id; team modes compose on the lead.
  String get composeMemberId {
    final s = session;
    if (s == null) {
      throw StateError('openSession before composeMemberId');
    }
    if (mode == CliMatrixMode.simple) return s.sessionId;
    return kMatrixLeadMemberId;
  }

  static bool get nativePtyAvailable =>
      IntegrationPrerequisites.nativePtyAvailable;

  /// Starts the mock gateway with [recipe] scenarios (or an explicit map).
  Future<void> startGateway({
    Map<String, MockScenario>? scenarios,
    bool exposeToDocker = false,
  }) async {
    _configureBusBridge();
    final server = MockModelGatewayServer.scenarios(
      scenarios ?? scenariosForRecipe(recipe),
      toolNames: profile.toolName,
    );
    gateway = server;
    await server.start(
      address: exposeToDocker ? InternetAddress.anyIPv4 : null,
    );
  }

  /// Writes actor-keyed providers for [profile.tool] (homogeneous team / simple).
  Future<void> writeMockProviders({String? workerBaseUrl}) async {
    final server = gateway;
    if (server == null) {
      throw StateError('startGateway before writeMockProviders');
    }
    final port = server.port;
    final localUrl = mockBaseUrl;
    final leaderUrl =
        workerBaseUrl != null ? 'http://127.0.0.1:$port' : localUrl;
    final remoteWorkerUrl = workerBaseUrl ?? leaderUrl;
    final hints = profile.gatewayCredentialHints(leaderUrl);
    final workerHints = profile.gatewayCredentialHints(remoteWorkerUrl);

    Map<String, Object?> providerConfig(String providerId) {
      final modelId = matrixMockModelIdFor(providerId);
      return {
        if (profile.providerType != null) 'provider_type': profile.providerType,
        // Custom opencode ids are not in the built-in catalog — npm tells
        // OpenCode which SDK to use (same as OpenAI Compatible preset).
        if (profile.tool == CliTool.opencode)
          'npm': '@ai-sdk/openai-compatible',
        // flashskyai --provider requires --model; key must exist in llm_config
        // and must be unique across providers (merge overwrites same keys).
        'models': {
          modelId: {
            'name': modelId,
            'provider': providerId,
            'model': modelId,
            'enabled': true,
          },
        },
      };
    }

    final providers = <AppProviderConfig>[];
    if (mode == CliMatrixMode.simple) {
      providers.add(
        AppProviderConfig(
          id: kMatrixSimpleProviderId,
          cli: profile.tool,
          name: 'Mock Simple (${profile.tool.value})',
          baseUrl: hints['baseUrl'] ?? leaderUrl,
          apiKey: simpleScriptApiKey,
          defaultModel: matrixMockModelIdFor(kMatrixSimpleProviderId),
          config: providerConfig(kMatrixSimpleProviderId),
        ),
      );
    } else {
      providers.addAll([
        AppProviderConfig(
          id: kMatrixLeaderProviderId,
          cli: profile.tool,
          name: 'Mock Leader (${profile.tool.value})',
          baseUrl: hints['baseUrl'] ?? leaderUrl,
          apiKey: leadScriptApiKey,
          defaultModel: matrixMockModelIdFor(kMatrixLeaderProviderId),
          config: providerConfig(kMatrixLeaderProviderId),
        ),
        AppProviderConfig(
          id: kMatrixWorkerProviderId,
          cli: profile.tool,
          name: 'Mock Worker (${profile.tool.value})',
          // Wire-aware base (openai needs …/v1) — do not use raw remoteWorkerUrl.
          baseUrl: workerHints['baseUrl'] ?? remoteWorkerUrl,
          apiKey: workerScriptApiKey,
          defaultModel: matrixMockModelIdFor(kMatrixWorkerProviderId),
          config: providerConfig(kMatrixWorkerProviderId),
        ),
      ]);
    }

    await AppProviderRepository(
      basePath: AppStorage.paths.basePath,
    ).saveProviders(profile.tool, providers);
  }

  /// Builds ChatCubit (+ optional production-shaped AiHistoryCubit).
  ChatCubit createCubit({
    required PostFrameTestHarness postFrame,
    bool createHistory = true,
  }) {
    this.postFrame = postFrame;
    final life = SessionLifecycleService(
      appDataBasePath: AppStorage.paths.basePath,
    );
    lifecycle = life;
    final created = ChatCubit(
      executableResolver: () => cliPath,
      automationRepository: testAutomationRepository(),
      cliExecutableResolver: (_) => cliPath,
      postFrameScheduler: postFrame.scheduler,
      autoLaunchAllMembersOnConnect: () => true,
      sessionRepository: SessionRepository(),
      lifecycleService: life,
    );
    cubit = created;
    if (createHistory) {
      final hist = AiHistoryCubit(
        loader: AiHistoryLoader(
          contextBuilder: const SessionHistoryContextBuilder(),
          resolveWorkContext: (launchCtx, {String? memberId}) =>
              life.launchWorkContext(launchCtx, memberId: memberId),
        ),
      );
      history = hist;
      created.onSessionHistoryStale = (sessionId) {
        // ignore: discarded_futures
        hist.softReloadIfSession(sessionId);
      };
    }
    return created;
  }

  /// Homogeneous team profile for [mode] (cli == [profile.tool] for every seat).
  TeamProfile buildHomogeneousTeam() {
    if (mode == CliMatrixMode.simple) {
      throw StateError('simple mode has no TeamProfile');
    }
    if (mode == CliMatrixMode.native && !profile.supportsNativeTeam) {
      throw StateError(
        '${profile.tool.value} does not support native team '
        '(CliTestProfile.supportsNativeTeam == false)',
      );
    }
    final teamMode =
        mode == CliMatrixMode.native ? TeamMode.native : TeamMode.mixed;
    return TeamProfile(
      id: 'it-matrix-${profile.tool.value}-${mode.name}',
      name: 'IT Matrix ${profile.tool.value} ${mode.name}',
      cli: profile.tool,
      teamMode: teamMode,
      members: [
        TeamMemberConfig(
          id: kMatrixLeadMemberId,
          name: TeamMemberNaming.teamLeadName,
          provider: kMatrixLeaderProviderId,
          model: matrixMockModelIdFor(kMatrixLeaderProviderId),
          cli: profile.tool,
          // High effort can issue multiple Anthropic calls per user message.
          effort: 'low',
        ),
        TeamMemberConfig(
          id: kMatrixWorkerMemberId,
          name: 'developer',
          provider: kMatrixWorkerProviderId,
          model: matrixMockModelIdFor(kMatrixWorkerProviderId),
          cli: profile.tool,
          effort: 'low',
        ),
      ],
    );
  }

  /// Creates workspace + session and opens via [ChatCubit.requestOpenSession].
  Future<AppSession> openSession({
    bool connectImmediately = true,
    String? workingDirectory,
  }) async {
    final chat = cubit;
    if (chat == null) {
      throw StateError('createCubit before openSession');
    }
    if (mode == CliMatrixMode.native && !profile.supportsNativeTeam) {
      throw StateError(
        '${profile.tool.value} does not support native team '
        '(CliTestProfile.supportsNativeTeam == false)',
      );
    }

    final repo = SessionRepository();
    final ws = await repo.createWorkspace([
      WorkspaceFolder(path: workingDirectory ?? AppStorage.cwd),
    ]);
    workspace = ws;

    late final AppSession created;
    if (mode == CliMatrixMode.simple) {
      team = null;
      created = await repo.createSession(
        ws.workspaceId,
        cli: profile.tool,
        provider: kMatrixSimpleProviderId,
        // flashskyai (and peers) require --model whenever --provider is set.
        model: matrixMockModelIdFor(kMatrixSimpleProviderId),
        // High effort can issue multiple Anthropic calls per user message
        // (adaptive thinking), burning scripted TextTurns.
        effort: 'low',
      );
      session = created;
      final status = await chat.requestOpenSession(
        SessionOpenRequest(
          session: created,
          workspace: ws,
          repo: repo,
          connectImmediately: connectImmediately,
        ),
      );
      if (status != SessionOpenStatus.opened) {
        throw StateError(
          'requestOpenSession failed for simple cell: $status '
          '(workspaceId=${ws.workspaceId})',
        );
      }
    } else {
      final builtTeam = buildHomogeneousTeam();
      // Homogeneous: every member CLI matches the matrix row.
      assert(
        builtTeam.cli == profile.tool &&
            builtTeam.members.every(
              (m) => (m.cli ?? builtTeam.cli) == profile.tool,
            ),
      );
      team = builtTeam;
      created = await repo.createSession(
        ws.workspaceId,
        sessionTeam: builtTeam.id,
        rosterMembers: builtTeam.members,
        memberClis: {
          for (final m in builtTeam.members) m.id: profile.tool,
        },
      );
      session = created;
      await chat.requestOpenSession(
        SessionOpenRequest(
          session: created,
          team: builtTeam,
          member: builtTeam.members.firstWhere(
            (m) => m.id == kMatrixLeadMemberId,
          ),
          repo: repo,
          connectImmediately: connectImmediately,
        ),
      );
    }

    await drainPendingAsyncWork();
    await postFrame?.flush();
    return created;
  }

  /// Dismisses boot gates then waits until [CliTestProfile.bootToPrompt].
  Future<void> bootComposeSeatToPrompt({
    Duration timeout = const Duration(seconds: 90),
  }) =>
      bootMemberToPrompt(composeMemberId, timeout: timeout);

  /// Boots a specific roster / simple seat to the composer prompt.
  Future<void> bootMemberToPrompt(
    String memberId, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    TerminalSession? shell;
    while (DateTime.now().isBefore(deadline)) {
      await postFrame?.flush();
      await drainPendingAsyncWork();
      shell = memberShell(memberId);
      if (shell != null && (shell.isRunning || shell.isConnecting)) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (shell == null || (!shell.isRunning && !shell.isConnecting)) {
      final chat = cubit;
      final tab = chat?.activeTab;
      throw StateError(
        'No TerminalSession for member=$memberId '
        'activeSession=${chat?.state.activeSessionId} '
        'selected=${chat?.state.selectedMemberId} '
        'launchError=${chat?.state.sessionLaunchError} '
        'tabLaunchError=${tab?.info.launchError} '
        'shellKeys=${tab?.memberShells.keys.toList()} '
        'isRunning=${chat == null || chat.state.activeSessionId == null ? null : chat.isMemberRunning(sessionId: chat.state.activeSessionId!, memberId: memberId)}\n'
        '${diagnosticsBundle(memberId: memberId)}',
      );
    }
    await profile.dismissBootGates(shell);
    final ok = await profile.bootToPrompt(shell);
    if (!ok) {
      throw StateError(
        'bootToPrompt failed for ${profile.tool.value} member=$memberId\n'
        '${diagnosticsBundle(memberId: memberId)}',
      );
    }
  }

  /// Boots every roster seat (lead + workers) for mixed/native cells.
  Future<void> bootAllMembersToPrompt({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final built = team;
    if (built == null) {
      await bootComposeSeatToPrompt(timeout: timeout);
      return;
    }
    for (final m in built.members) {
      await bootMemberToPrompt(m.id, timeout: timeout);
    }
  }

  /// Parks the worker, then [submitCompose] on the lead (recipe order).
  ///
  /// Relies on virgin-lead mail suppression: worker idle-announce queues mail
  /// without PTY-doorbelling a lead that has never started a turn, so History
  /// compose remains the first lead user message.
  Future<HistoryContinueSubmitResult> parkWorkerAndComposeOnLead(
    String prompt, {
    String workerKickoff = 'Start idle loop.',
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final server = gateway;
    if (server == null) {
      throw StateError('startGateway before parkWorkerAndComposeOnLead');
    }
    if (mode == CliMatrixMode.simple) {
      throw StateError('parkWorkerAndComposeOnLead is for mixed/native cells');
    }

    await _submitWorkerKickoffAndAwaitPark(
      kickoff: workerKickoff,
      timeout: timeout,
      workerBaseline: server.requestCountFor(workerScriptApiKey),
    );
    await bootComposeSeatToPrompt(timeout: timeout);
    return submitCompose(prompt);
  }

  /// History-compose on the lead, then park the worker on `wait_for_message`.
  ///
  /// Alternate ordering when compose must precede park; prefer
  /// [parkWorkerAndComposeOnLead] for [mixed_collab_3plus].
  Future<HistoryContinueSubmitResult> composeOnLeadThenParkWorker(
    String prompt, {
    String workerKickoff = 'Start idle loop.',
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final server = gateway;
    if (server == null) {
      throw StateError('startGateway before composeOnLeadThenParkWorker');
    }
    if (mode == CliMatrixMode.simple) {
      throw StateError('composeOnLeadThenParkWorker is for mixed/native cells');
    }

    final leadBefore = server.requestCountFor(leadScriptApiKey);
    final result = await submitCompose(prompt);
    if (!result.ok) return result;

    await waitForGatewayTurns(
      apiKey: leadScriptApiKey,
      minTurns: leadBefore + 1,
      timeout: timeout,
    );

    await _submitWorkerKickoffAndAwaitPark(
      kickoff: workerKickoff,
      timeout: timeout,
      workerBaseline: server.requestCountFor(workerScriptApiKey),
    );
    return result;
  }

  /// PTY kickoff for the worker so it parks on `wait_for_message`.
  Future<void> kickoffWorkerParkAndWait({
    String kickoff = 'Start idle loop.',
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final chat = cubit;
    final s = session;
    final server = gateway;
    if (chat == null || s == null || server == null) {
      throw StateError('openSession+startGateway before kickoffWorkerParkAndWait');
    }
    if (mode == CliMatrixMode.simple) {
      throw StateError('kickoffWorkerParkAndWait is for mixed/native cells');
    }
    await _submitWorkerKickoffAndAwaitPark(
      kickoff: kickoff,
      timeout: timeout,
      workerBaseline: server.requestCountFor(workerScriptApiKey),
    );
  }

  Future<void> _submitWorkerKickoffAndAwaitPark({
    required String kickoff,
    required Duration timeout,
    required int workerBaseline,
  }) async {
    final chat = cubit;
    final s = session;
    final server = gateway;
    if (chat == null || s == null || server == null) {
      throw StateError('openSession+startGateway before worker park kickoff');
    }

    final bus = chat.sessionRuntime.busForSession(s.sessionId);
    final mcpGateway = chat.teammateBusMcpGateway;
    final parked = waitUntilWorkerParked(
      bus: bus,
      gateway: mcpGateway,
      sessionId: s.sessionId,
      memberId: kMatrixWorkerMemberId,
      timeout: timeout,
    );

    chat.selectMember(kMatrixWorkerMemberId);
    // Prefer the automation grid-ACK path (same as History compose delivery).
    // Raw submitFullScreenInput can miss Enter on flashskyai's Ink composer.
    await chat.sessionRuntime.deliverMemberStdin(
      s.sessionId,
      kMatrixWorkerMemberId,
      kickoff,
      automation: true,
    );
    await drainPendingAsyncWork(rounds: 10);
    await postFrame?.flush();

    final deadline = DateTime.now().add(timeout);
    var workerHit = false;
    while (DateTime.now().isBefore(deadline)) {
      if (server.requestCountFor(workerScriptApiKey) > workerBaseline) {
        workerHit = true;
        break;
      }
      await drainPendingAsyncWork();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!workerHit) {
      throw StateError(
        'Worker never hit mock API after kickoff '
        '(expected $workerScriptApiKey request)\n'
        '${diagnosticsBundle(memberId: kMatrixWorkerMemberId)}',
      );
    }
    await parked;
    await drainPendingAsyncWork(rounds: 5);
    await postFrame?.flush();
  }

  /// Asserts TeamBus ping (lead→worker) then pong (worker→lead).
  Future<void> waitForBusPingPong({
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final s = session;
    if (s == null) {
      throw StateError('openSession before waitForBusPingPong');
    }
    final root = AppStorage.paths.basePath;
    final workerPing = await waitForBusMail(
      teampilotRoot: root,
      workspaceId: s.workspaceId,
      sessionId: s.sessionId,
      memberId: kMatrixWorkerMemberId,
      timeout: timeout,
      where: (row) =>
          row['from'] == kMatrixLeadMemberId && row['content'] == 'ping',
    );
    if (!workerPing) {
      await dumpBusMailDiagnostics(
        teampilotRoot: root,
        workspaceId: s.workspaceId,
        sessionId: s.sessionId,
        memberIds: const [kMatrixLeadMemberId, kMatrixWorkerMemberId],
      );
      throw StateError(
        'Timed out waiting for worker mail: ping from $kMatrixLeadMemberId\n'
        '${diagnosticsBundle()}',
      );
    }

    final leaderPong = await waitForBusMail(
      teampilotRoot: root,
      workspaceId: s.workspaceId,
      sessionId: s.sessionId,
      memberId: kMatrixLeadMemberId,
      timeout: timeout,
      where: (row) =>
          row['from'] == kMatrixWorkerMemberId && row['content'] == 'pong',
    );
    if (!leaderPong) {
      await dumpBusMailDiagnostics(
        teampilotRoot: root,
        workspaceId: s.workspaceId,
        sessionId: s.sessionId,
        memberIds: const [kMatrixLeadMemberId, kMatrixWorkerMemberId],
      );
      throw StateError(
        'Timed out waiting for lead mail: pong from $kMatrixWorkerMemberId\n'
        '${diagnosticsBundle()}',
      );
    }
  }

  /// Loads History for the compose seat (production [AiHistoryCubit.load]).
  Future<void> loadHistory({String? memberId}) async {
    final hist = history;
    final s = session;
    final ws = workspace;
    if (hist == null || s == null || ws == null) {
      throw StateError('createCubit+openSession before loadHistory');
    }
    final mid = memberId ?? composeMemberId;
    await hist.load(
      session: s,
      memberId: mode == CliMatrixMode.simple ? '' : mid,
      launchContext: WorkspaceLaunchContext(session: s, workspace: ws),
      team: team,
    );
  }

  /// Soft-reloads History and flushes a held assistant tip for bubble asserts.
  Future<void> refreshHistoryForAsserts() async {
    final hist = history;
    if (hist == null) return;
    await hist.softReload();
    if (hist.hasHeldAssistantTip) {
      hist.flushHeldTip(endAwaiting: true);
    }
  }

  /// Resolves the continue channel the same way production Chat does.
  HistoryContinueChannel peekContinueChannel({String? memberId}) {
    final chat = cubit;
    final s = session;
    if (chat == null || s == null) {
      return HistoryContinueChannel.pty;
    }
    final mid = memberId ?? composeMemberId;
    final bus = chat.sessionRuntime.busForSession(s.sessionId);
    return resolveHistoryContinueChannel(
      teamBusInstalled: bus != null,
      memberWaitingForMessage: bus?.isWaitingForMessage(mid) ?? false,
      memberInTurn: bus?.isMemberInTurn(mid) ?? false,
    );
  }

  /// History compose submit — mirrors [SessionChatView] pending / Queued side
  /// effects, then calls [submitSessionHistoryReviewMessage].
  Future<HistoryContinueSubmitResult> submitCompose(
    String text, {
    String? memberId,
  }) async {
    final chat = cubit;
    final s = session;
    if (chat == null || s == null) {
      throw StateError('openSession before submitCompose');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const HistoryContinueSubmitResult.failed();
    }

    final mid = memberId ?? composeMemberId;
    HistoryContinueChannel resolveChannel() =>
        peekContinueChannel(memberId: mid);

    final peek = resolveChannel();
    final optimisticPty = peek == HistoryContinueChannel.pty;
    final hist = history;
    if (optimisticPty && hist != null) {
      hist.enqueuePendingUser(trimmed);
    }

    final activeTeam = team;
    final connectMember = activeTeam == null
        ? null
        : resolveSessionChatContinueMember(
            session: s,
            team: activeTeam,
            selectedMemberId: mid,
          );

    final result = await submitSessionHistoryReviewMessage(
      sessionId: s.sessionId,
      memberId: mid,
      message: trimmed,
      connectRequest: ExistingSessionConnect(
        session: s,
        team: activeTeam,
        member: connectMember,
        preserveWorkbenchView: true,
      ),
      resolveChannel: resolveChannel,
      connectWorkspaceSession: chat.connectWorkspaceSession,
      ensureMemberInputReady: (sessionId, member, {bool directToPty = false}) =>
          chat.memberMaterializer.ensureMemberInputReady(
            sessionId,
            member,
            directToPty: directToPty,
          ),
      deliverUserCommandToMember:
          (sessionId, member, body, {bool directToPty = false}) =>
              chat.sessionRuntime.deliverUserCommandToMember(
                sessionId,
                member,
                body,
                directToPty: directToPty,
              ),
      applyFirstPromptTitle: chat.applyFirstPromptTitle,
    );
    lastSubmitResult = result;

    if (!result.ok) {
      if (optimisticPty && hist != null) {
        hist.removePendingMatching(trimmed);
      }
      return result;
    }

    if (result.isMailbox) {
      if (optimisticPty && hist != null) {
        hist.removePendingMatching(trimmed);
      }
      final queued = PendingUserMessage(
        id: result.mailId!,
        content: trimmed,
      );
      mailboxQueued.add(queued);
      mailboxQueuedSubmitted.add(queued);
      return result;
    }

    if (!optimisticPty && hist != null) {
      hist.enqueuePendingUser(trimmed);
    }
    return result;
  }

  /// Promote a Queued mailbox row to sticky (SessionChatView onConsumed).
  void promoteMailboxConsumed(String mailId) {
    final idx = mailboxQueued.indexWhere((m) => m.id == mailId);
    if (idx < 0) return;
    final msg = mailboxQueued.removeAt(idx);
    history?.appendStickyLocalUser(
      id: 'mailbox:${msg.id}',
      text: msg.content,
    );
  }

  Future<void> waitForGatewayTurns({
    required String apiKey,
    required int minTurns,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final server = gateway;
    if (server == null) {
      throw StateError('startGateway before waitForGatewayTurns');
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (server.requestCountFor(apiKey) >= minTurns) return;
      await drainPendingAsyncWork();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'Timed out waiting for ≥$minTurns gateway turns for apiKey=$apiKey '
      '(have ${server.requestCountFor(apiKey)})\n'
      '${diagnosticsBundle()}',
    );
  }

  Future<void> waitForPtyMarkers(
    List<String> markers, {
    String? memberId,
    Duration timeout = const Duration(seconds: 120),
    int scanRows = 52,
  }) async {
    final shell = memberShell(memberId ?? composeMemberId);
    if (shell == null) {
      throw StateError(
        'No TerminalSession for member=${memberId ?? composeMemberId}\n'
        '${diagnosticsBundle()}',
      );
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await shell.probe.syncDisplayGrid();
      final frame = [
        shell.probe.describeProbeWindow(scanRows: scanRows),
        exportTerminalScrollback(shell.engine),
      ].join('\n');
      if (markers.every(frame.contains)) return;
      await drainPendingAsyncWork();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await shell.probe.syncDisplayGrid();
    throw StateError(
      'Timed out waiting for PTY markers $markers\n'
      'frame:\n${sanitizeMatrixPtyDump(shell.probe.describeProbeWindow(scanRows: scanRows))}\n'
      '${diagnosticsBundle()}',
    );
  }

  /// Waits for user + ≥3 assistant bubbles on [history] (channel-aware).
  ///
  /// Default markers: [composeSeatAssistantMarkers] (simple → MARK_A*,
  /// native/mixed → collab lead markers). Mailbox channel waits for Queued →
  /// sticky via [promoteMailboxConsumed] — does not require a user bubble on
  /// the cubit while mail is only Queued.
  Future<void> waitForBubbles({
    required String userText,
    List<String>? assistantMarkers,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final hist = history;
    if (hist == null) {
      throw StateError('createCubit(createHistory: true) before waitForBubbles');
    }
    final markers = assistantMarkers ?? composeSeatAssistantMarkers;
    final channel = lastSubmitResult?.channel ?? peekContinueChannel();
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      await refreshHistoryForAsserts();
      try {
        if (channel == HistoryContinueChannel.mailbox) {
          final mailId = lastSubmitResult?.mailId;
          if (mailId == null || mailId.isEmpty) {
            throw StateError(
              'mailbox submit missing mailId\n${diagnosticsBundle()}',
            );
          }
          final stickyId = 'mailbox:$mailId';
          final stickySeat = hist.seatOf(
            sessionId: hist.state.sessionId ?? '',
            selectedMemberId: hist.state.memberId ?? '',
          );
          final stickyReady =
              stickySeat?.runtime.messages.any(
                (m) => m.role == AiRole.user && m.id == stickyId,
              ) ??
              false;
          if (!stickyReady) {
            // Still Queued (or not yet promoted) — do not expectUserBubble.
            if (!mailboxQueuedSubmitted.any((m) => m.id == mailId)) {
              throw TestFailure(
                'mailbox Queued snapshot missing mailId=$mailId\n'
                '${diagnosticsBundle()}',
              );
            }
            // Mirror SessionChatView strip: promote when bus marks mail read.
            final chat = cubit;
            final s = session;
            final bus = (chat != null && s != null)
                ? chat.sessionRuntime.busForSession(s.sessionId)
                : null;
            final stillUnread =
                bus?.isUnread(composeMemberId, mailId) ?? true;
            if (!stillUnread && mailboxQueued.any((m) => m.id == mailId)) {
              promoteMailboxConsumed(mailId);
              continue;
            }
            throw TestFailure(
              'mailbox sticky not ready yet (mail still Queued or unconsumed)',
            );
          }
          expectMailboxQueuedThenSticky(
            queuedSnapshot: mailboxQueuedSubmitted,
            history: hist,
            text: userText,
            mailId: mailId,
          );
        } else {
          expectUserBubble(
            hist,
            userText,
            matches: profile.matchesUserBubble,
          );
        }
        expectAssistantMarkers(
          hist,
          markers,
          matches: profile.matchesAssistantMarker,
        );
        return;
      } on TestFailure {
        // Keep polling until timeout.
      }
      await drainPendingAsyncWork();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    await refreshHistoryForAsserts();
    throw StateError(
      'Timed out waiting for chat bubbles\n'
      'channel=$channel userText=$userText markers=$markers\n'
      '${diagnosticsBundle()}',
    );
  }

  TerminalSession? memberShell(String memberId) {
    final chat = cubit;
    if (chat == null) return null;
    chat.selectMember(memberId);
    return chat.currentSession;
  }

  /// Gateway + thread (+ optional PTY frame) for attribution on red cells.
  String diagnosticsBundle({String? memberId}) {
    final buf = StringBuffer('CliMessageMatrixHarness diagnostics\n');
    buf.writeln(
      'cli=${profile.tool.value} mode=${mode.name} recipe=${recipe.name}',
    );
    buf.writeln('cliPath=$cliPath');
    buf.writeln(
      redactMatrixSecrets(
        gateway?.dumpDiagnostics() ?? 'gateway: not started',
      ),
    );
    final hist = history;
    if (hist != null) {
      buf.writeln(redactMatrixSecrets(dumpThread(hist)));
    } else {
      buf.writeln('history: not created');
    }
    buf.writeln(
      'mailboxQueued=${mailboxQueued.map((m) => '${m.id}:${m.content}').toList()}',
    );
    buf.writeln(
      'mailboxQueuedSubmitted='
      '${mailboxQueuedSubmitted.map((m) => '${m.id}:${m.content}').toList()}',
    );
    buf.writeln('lastSubmit=$lastSubmitResult');
    final mid = memberId ?? (session == null ? '' : composeMemberId);
    final shell = mid.isEmpty ? null : memberShell(mid);
    if (shell != null) {
      try {
        buf.writeln(
          'ptyFrame:\n${sanitizeMatrixPtyDump(shell.probe.describeProbeWindow(scanRows: 52))}',
        );
      } on Object catch (e) {
        buf.writeln('ptyFrame: error $e');
      }
    }
    return buf.toString();
  }

  Future<void> dispose() async {
    final hist = history;
    history = null;
    if (hist != null) {
      await hist.close();
    }
    final active = cubit;
    cubit = null;
    if (active != null) {
      await active.close();
    }
    await gateway?.stop();
    gateway = null;
    _restoreBusBridgeEnv();
  }

  /// OpenCode remote HTTP MCP does not complete long-blocking
  /// `wait_for_message` SSE; product launch prefers stdio via
  /// [BusBridgeLocator]. Other CLIs force HTTP so matrix cells do not depend
  /// on a runnable bridge binary in the test runner.
  void _configureBusBridge() {
    if (profile.tool == CliTool.opencode) {
      _forceStdioBusBridge();
    } else {
      _forceHttpMcp();
    }
  }

  void _forceStdioBusBridge() {
    final bridge = _resolveMatrixBusBridge();
    if (bridge == null) {
      throw StateError(
        'OpenCode mixed matrix requires teammate_bus_bridge on disk '
        '(build linux bundle or set ${BusBridgeLocator.envOverride})',
      );
    }
    // flutter test cannot mutate Platform.environment — pin via locator.
    _savedBusBridgeDebugOverride = BusBridgeLocator.debugResolveOverride;
    BusBridgeLocator.debugResolveOverride = bridge;
    _busBridgeDebugOverrideApplied = true;
    try {
      _savedBusBridgeEnv = Platform.environment[BusBridgeLocator.envOverride];
      Platform.environment[BusBridgeLocator.envOverride] = bridge;
      _envOverrideApplied = true;
    } on UnsupportedError {
      // Env pin optional when debugResolveOverride is set.
      _envOverrideApplied = false;
    }
  }

  /// Bundle / CWD candidates for the stdio bus bridge used by OpenCode cells.
  static String? _resolveMatrixBusBridge() {
    final fromEnv = Platform.environment[BusBridgeLocator.envOverride]?.trim();
    if (fromEnv != null &&
        fromEnv.isNotEmpty &&
        fromEnv != '/dev/null/teampilot-it-no-bridge' &&
        BusBridgeLocator.isRunnableExecutable(fromEnv)) {
      return fromEnv;
    }
    const candidates = [
      'build/linux/x64/debug/bundle/teammate_bus_bridge',
      'build/linux/x64/debug/teammate_bus_bridge',
      '../build/linux/x64/debug/bundle/teammate_bus_bridge',
    ];
    for (final path in candidates) {
      if (BusBridgeLocator.isRunnableExecutable(path)) {
        return File(path).absolute.path;
      }
    }
    return BusBridgeLocator.resolve();
  }

  void _forceHttpMcp() {
    // Clear any OpenCode stdio pin from a prior cell in the same isolate.
    if (_busBridgeDebugOverrideApplied) {
      BusBridgeLocator.debugResolveOverride = _savedBusBridgeDebugOverride;
      _busBridgeDebugOverrideApplied = false;
      _savedBusBridgeDebugOverride = null;
    }
    // Pin an unusable bridge so resolve() returns null → HTTP MCP fallback.
    _savedBusBridgeDebugOverride = BusBridgeLocator.debugResolveOverride;
    BusBridgeLocator.debugResolveOverride =
        '/dev/null/teampilot-it-no-bridge';
    _busBridgeDebugOverrideApplied = true;
    try {
      _savedBusBridgeEnv = Platform.environment[BusBridgeLocator.envOverride];
      Platform.environment[BusBridgeLocator.envOverride] =
          '/dev/null/teampilot-it-no-bridge';
      _envOverrideApplied = true;
    } on UnsupportedError {
      _envOverrideApplied = false;
    }
  }

  void _restoreBusBridgeEnv() {
    if (_busBridgeDebugOverrideApplied) {
      BusBridgeLocator.debugResolveOverride = _savedBusBridgeDebugOverride;
      _busBridgeDebugOverrideApplied = false;
      _savedBusBridgeDebugOverride = null;
    }
    if (!_envOverrideApplied) return;
    final saved = _savedBusBridgeEnv;
    _savedBusBridgeEnv = null;
    _envOverrideApplied = false;
    try {
      if (saved == null) {
        Platform.environment.remove(BusBridgeLocator.envOverride);
      } else {
        Platform.environment[BusBridgeLocator.envOverride] = saved;
      }
    } on UnsupportedError {
      // Best-effort restore only.
    }
  }
}

Map<String, MockScenario> scenariosForRecipe(CliMatrixRecipe recipe) =>
    switch (recipe) {
      CliMatrixRecipe.simple3Turn => simple3TurnScenarios(),
      CliMatrixRecipe.nativeCollab3Plus => nativeCollab3PlusScenarios(),
      CliMatrixRecipe.mixedCollab3Plus => mixedCollab3PlusScenarios(),
    };
