import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../cubits/ai_history_cubit.dart';
import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/config_bundle.dart';
import '../../models/failed_message_record.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/cli/registry/capabilities/ai_history_capability.dart';
import '../../services/cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/cli/tasks/cli_task_board_controller.dart';
import '../../services/compose/compose_clip.dart';
import '../../services/compose/compose_draft_cache.dart';
import '../../services/compose/compose_file_attach.dart';
import 'session_chat_voice_controller.dart';
import '../../services/follow_up/follow_up_queue.dart';
import '../../services/session/ai_history_live_refresh_controller.dart';
import '../../services/session/failed_message_store.dart';
import '../../services/session/chat_transcript_find_controller.dart';
import '../../services/session/history_seat_key.dart';
import 'ai_message_strings_from_l10n.dart';
import '../../services/session/history_hydration_scope.dart';
import '../../services/session/history_awaiting_working_sync.dart';
import '../../services/session/session_history_pagination.dart';
import '../../services/storage/app_storage.dart';
import '../../services/terminal/pending_user_message.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../utils/debug/debug_bloc_rebuild.dart';
import '../../utils/logging/logger.dart';
import '../../utils/session/session_chat_identity.dart';
import '../../utils/team/team_member_naming.dart';
import 'session_chat_compose_section.dart';
import 'session_seat_working.dart';
import 'session_chat_message_area.dart';
import 'agent_permission_attention_banner.dart';
import 'chat_find_bar.dart';
import 'chat_message_locator.dart';
import 'chat_reveal_controller.dart';
import 'session_follow_up_compose_submit.dart';
import 'history_continue_delivery.dart';
import 'session_history_review_submit.dart';
import 'subagent_preview_controller.dart';

/// Fired by Mod+F (Ctrl+F / Cmd+F) in [SessionChatView] to toggle the find
/// bar. Escape is handled inside [ChatFindBar], which is only mounted while
/// find is visible.
class _ChatFindToggleIntent extends Intent {
  const _ChatFindToggleIntent();
}

/// Bound Chat view: history thread + slim compose for a session body.
class SessionChatView extends StatefulWidget {
  const SessionChatView({
    required this.session,
    required this.workspace,
    required this.selectedMemberId,
    required this.onSubmit,
    this.team,
    this.launchError,
    this.onRemapDeadTarget,
    this.onRetry,
    this.sessionConnectInProgress = false,
    this.isSubmitting = false,
    this.isMailboxUnread,
    this.peekContinueChannel,
    this.routeActive = true,
    this.projectConfigRepository,
    this.failedMessageStore,
    this.viewToggle,
    super.key,
  });

  final AppSession session;
  final Workspace workspace;
  final String selectedMemberId;
  final TeamProfile? team;

  /// Connect+deliver outcome so compose can clear and latch mailbox Queued rows.
  final Future<HistoryContinueSubmitResult> Function(String message) onSubmit;
  final String? launchError;
  final VoidCallback? onRemapDeadTarget;
  final VoidCallback? onRetry;
  final bool sessionConnectInProgress;
  final bool isSubmitting;

  /// When non-null, mailbox Queued rows poll this until the member consumes mail.
  final bool Function(String mailId)? isMailboxUnread;

  /// Optional pre-submit channel peek so mailbox continues skip optimistic
  /// thread pending (confirmed again after connect inside [onSubmit]).
  final HistoryContinueChannel Function()? peekContinueChannel;

  /// When false and the seat member is not running, live transcript refresh stops
  /// (warm keep-alive). Task 7 plumbs this from the workspace route scope.
  final bool routeActive;

  /// Injectable for tests; defaults to the app storage-backed repository.
  final WorkspaceProjectConfigRepository? projectConfigRepository;

  /// Injectable persisted delivery state for restart-safe optimistic bubbles.
  final FailedMessageStore? failedMessageStore;

  /// Icon-only Chat/Terminal control docked into the top-right task-board
  /// capsule. The host passes the bare [SessionWorkbenchViewIcons]; standalone
  /// chrome lives in [SessionWorkbenchViewToggle] for non-chat surfaces.
  final Widget? viewToggle;

  @override
  State<SessionChatView> createState() => _SessionChatViewState();
}

class _SessionChatViewState extends State<SessionChatView> {
  final _controller = TextEditingController();
  final _clip = ComposeClip();
  late final FocusNode _focusNode;
  late final SessionVoiceController _voice;
  final _subagentPreview = SubagentPreviewController();
  AiHistoryLiveRefreshController? _liveRefresh;

  /// 创建 [_liveRefresh] 时的 seat 作用域标识;作用域未变时复用 controller,
  /// 避免 working 状态翻转 / load 完成回调反复"停旧建新"。
  String? _liveRefreshScope;

  /// [_startLiveRefresh] 的在途启动链:并发调用合并为一条,见 [_startLiveRefresh]。
  Future<void>? _liveRefreshStartInFlight;
  AiHistorySeat? _seat;
  CliTaskBoardController? _taskBoardController;

  final _submitLock = HistoryContinueSubmitLock();
  final _mailboxQueued = StreamController<PendingUserMessage>.broadcast();

  /// True from optimistic enqueue through connect/boot/inject settle so idle
  /// grace cannot blank tip chrome while History continue is still in flight.
  var _historyContinueInFlight = false;
  /// Bumped whenever submit discards the compose draft so a late
  /// [_hydrateComposeDraft] cannot seed text the user already sent.
  var _composeDraftSeedGeneration = 0;
  var _suppressComposeDraftPersistence = false;

  /// mailId → seat key at queue time (guards wrong-seat timeline refresh).
  final Map<String, String> _mailboxQueuedSeats = {};
  var _mailboxQueuedClearToken = 0;
  final _submitBusy = ValueNotifier(false);

  /// Hides compose Stop immediately; PTY idleAfter can stay "working" after Ctrl+C.
  final _userStoppedTurn = ValueNotifier(false);

  /// Workspace-layer bundle (project-config.json) so the review compose slash
  /// menu shows the same skills/plugins/MCP as the landing compose.
  ConfigBundle _workspaceBundle = const ConfigBundle();
  int _workspaceBundleGeneration = 0;
  late final WorkspaceProjectConfigRepository _projectConfigRepository;
  late final FailedMessageStore _failedMessageStore;
  FailedMessageRecord? _editingFailedMessage;
  final Set<String> _retryingFailedMessageIds = <String>{};

  /// Host-owned Timer for [historyAwaitingIdleGrace]; latch lives on the seat.
  Timer? _awaitingIdleGraceTimer;

  /// Chat find bar (Mod+F): full-transcript search + n/N navigation, revealed
  /// via [AiHistorySeat.revealMessage] + [ChatRevealController].
  final _findQueryController = TextEditingController();
  final _findFocusNode = FocusNode(debugLabel: 'session_chat_find');
  // late: the provider closure reads `_seat`, which is bound after construction.
  late final _findController = ChatTranscriptFindController(
    messagesProvider: () => _seat?.loadedMessages ?? const [],
  );
  final _revealController = ChatRevealController();
  final _visibleOwnerId = ValueNotifier<String?>(null);
  final _emptyRuntime = ExternalStoreAiThreadRuntime();
  late final ChatMessageLocator _locator;
  bool _findVisible = false;
  String? _locateHighlightId;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'session_history_review_compose');
    _voice = SessionVoiceController(composeController: _controller);
    // Restore the cached session draft before attaching the change listener so
    // the restore does not notify _onComposeChanged (no setState during mount).
    final draft = composeDraftCache.sessionDraft(widget.session.sessionId);
    if (draft != null && draft.isNotEmpty) {
      _controller.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    _controller.addListener(_onComposeChanged);
    unawaited(_hydrateComposeDraft());
    _projectConfigRepository =
        widget.projectConfigRepository ?? WorkspaceProjectConfigRepository();
    _failedMessageStore =
        widget.failedMessageStore ??
        FailedMessageStore(fs: AppStorage.fs, rootPath: AppStorage.appDataRoot);
    _locator = ChatMessageLocator(
      loadedMessages: () => _seat?.loadedMessages ?? const [],
      runtime: () => _seat?.runtime ?? _emptyRuntime,
      revealInWindow: (index) {
        _seat?.revealMessage(index);
      },
      revealController: _revealController,
      onHighlight: (id) {
        if (mounted) setState(() => _locateHighlightId = id);
      },
      waitFrame: () {
        final done = Completer<void>();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!done.isCompleted) done.complete();
        });
        return done.future;
      },
    );
    _bindSeat();
    unawaited(_loadHistoryThenHydratePersistedPendingUsers());
    unawaited(_loadWorkspaceProjectBundle());
  }

  Future<void> _loadWorkspaceProjectBundle() async {
    final generation = ++_workspaceBundleGeneration;
    try {
      final config = await _projectConfigRepository.load(
        widget.session.workspaceId,
      );
      if (!mounted || generation != _workspaceBundleGeneration) return;
      setState(() => _workspaceBundle = config.bundle);
    } on Object {
      if (!mounted || generation != _workspaceBundleGeneration) return;
      setState(() => _workspaceBundle = const ConfigBundle());
    }
  }

  void _bindSeat() {
    final chat = context.read<ChatCubit>();
    final store = chat.podRuntime(widget.session.sessionId)?.history;
    _seat = store != null
        ? store.memberSeat(
            sessionId: widget.session.sessionId,
            memberId: widget.selectedMemberId,
          )
        // Fallback until pods own a HistoryStore (bootstrap wiring).
        : context.read<AiHistoryCubit>().ensureSeat(
            sessionId: widget.session.sessionId,
            selectedMemberId: widget.selectedMemberId,
          );
    final seat = _seat;
    _taskBoardController?.dispose();
    _taskBoardController = seat == null
        ? null
        : CliTaskBoardController(
            runtime: seat.runtime,
            loadedMessages: () => seat.loadedMessages,
          );
  }

  @override
  void didUpdateWidget(covariant SessionChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.workspaceId != widget.session.workspaceId) {
      unawaited(_loadWorkspaceProjectBundle());
    }
    final seatChanged =
        oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.selectedMemberId != widget.selectedMemberId ||
        oldWidget.team?.id != widget.team?.id;
    if (seatChanged) {
      _userStoppedTurn.value = false;
      _locator.cancel();
      _visibleOwnerId.value = null;
      _locateHighlightId = null;
      unawaited(_stopLiveRefreshForSeatChange());
      _clearMailboxQueuedUi();
      _editingFailedMessage = null;
      _subagentPreview.clear();
      _bindSeat();
      // Defer: load → runtime.setLoading sync-notifies seat listeners
      // while ancestors (e.g. TpDeferredForegroundMount) are still building.
      // Do not clearPendings here: re-entering a seat (tab switch, team prop
      // resolve flicker) before the CLI transcript is locatable would wipe the
      // optimistic first bubble and show sessionHistoryEmpty. Seat.load()
      // already clears pendings when sessionId/memberId actually change.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_loadHistoryThenHydratePersistedPendingUsers());
      });
    } else if (oldWidget.routeActive != widget.routeActive) {
      _maybeStartLiveRefreshForRunningPty();
    }
  }

  Future<void> _hydratePersistedPendingUsers() async {
    final seat = _seat;
    if (seat == null) return;
    await seat.hydratePendingUsers(
      store: _failedMessageStore,
      workspaceId: widget.session.workspaceId,
      sessionId: widget.session.sessionId,
    );
  }

  /// The CLI snapshot establishes the user-turn baseline used by FIFO
  /// confirmation. Hydrating before it completes lets existing transcript
  /// turns consume restored records as though they were freshly sent.
  Future<void> _loadHistoryThenHydratePersistedPendingUsers() async {
    final seat = _seat;
    if (seat == null) return;
    final scope = HistoryHydrationScope(
      seat: seat,
      sessionId: widget.session.sessionId,
      memberId: widget.selectedMemberId,
    );
    await _loadHistory();
    if (!mounted ||
        !scope.isCurrent(
          seat: _seat,
          sessionId: widget.session.sessionId,
          memberId: widget.selectedMemberId,
        )) {
      return;
    }
    await _hydratePersistedPendingUsers();
  }

  String _mailboxSeatKey() => historySeatKey(
    sessionId: widget.session.sessionId,
    selectedMemberId: widget.selectedMemberId,
  );

  /// Drop Queued rows on seat change without promoting them as consumed.
  void _clearMailboxQueuedUi() {
    _mailboxQueuedSeats.clear();
    _mailboxQueuedClearToken++;
    if (mounted) setState(() {});
  }

  void _toggleFind() {
    setState(() => _findVisible = !_findVisible);
    if (_findVisible) {
      _findFocusNode.requestFocus();
    } else {
      _closeFind();
    }
  }

  void _closeFind() {
    _findController.clear();
    _findQueryController.clear();
    setState(() {
      _findVisible = false;
      _locateHighlightId = null;
    });
    _revealController.clear();
  }

  void _navigateFindTo(TranscriptHit hit) {
    unawaited(_locator.locate(id: hit.messageId, index: hit.messageIndex));
  }

  @override
  void dispose() {
    _awaitingIdleGraceTimer?.cancel();
    _awaitingIdleGraceTimer = null;
    _controller.removeListener(_onComposeChanged);
    _voice.dispose();
    final live = _liveRefresh;
    _liveRefresh = null;
    _liveRefreshScope = null;
    unawaited(live?.stop() ?? Future<void>.value());
    _taskBoardController?.dispose();
    _taskBoardController = null;
    unawaited(_mailboxQueued.close());
    _subagentPreview.dispose();
    _clip.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _findQueryController.dispose();
    _findFocusNode.dispose();
    _findController.dispose();
    _revealController.dispose();
    _visibleOwnerId.dispose();
    _locator.cancel();
    _emptyRuntime.close();
    _submitBusy.dispose();
    _userStoppedTurn.dispose();
    super.dispose();
  }

  void _onComposeChanged() {
    if (_suppressComposeDraftPersistence) return;
    unawaited(
      composeDraftCache.saveSession(
        widget.session.workspaceId,
        widget.session.sessionId,
        _controller.text,
      ),
    );
  }

  Future<void> _hydrateComposeDraft() async {
    final generation = _composeDraftSeedGeneration;
    final draft = await composeDraftCache.hydrateSession(
      widget.session.workspaceId,
      widget.session.sessionId,
      shouldSeed: () =>
          mounted &&
          generation == _composeDraftSeedGeneration &&
          _controller.text.isEmpty,
    );
    if (!mounted ||
        generation != _composeDraftSeedGeneration ||
        _controller.text.isNotEmpty ||
        draft == null ||
        draft.isEmpty) {
      return;
    }
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  /// Submission owns recovery via the optimistic / failed history bubble —
  /// clear compose drafts as soon as send starts so remount/hydrate cannot
  /// put the same text back into the field.
  ///
  /// When [holdListenerSuppress] is true (PTY deliver in flight), the compose
  /// change listener stays muted until the caller clears
  /// [_suppressComposeDraftPersistence]. Follow-up enqueue passes false so the
  /// field is immediately editable again.
  Future<void> _discardComposeDraftForSubmit({
    bool holdListenerSuppress = true,
  }) async {
    _composeDraftSeedGeneration++;
    _suppressComposeDraftPersistence = true;
    composeDraftCache.clearSessionDraft(widget.session.sessionId);
    await composeDraftCache.clearSessionPersistent(
      widget.session.workspaceId,
      widget.session.sessionId,
    );
    if (!mounted) return;
    _controller.clear();
    _clip.clear();
    if (!holdListenerSuppress) {
      _suppressComposeDraftPersistence = false;
    }
  }

  bool get _isSubmitting =>
      _submitBusy.value || _submitLock.isBusy || widget.isSubmitting;

  String get _workspaceRoot {
    final work = widget.session.workDirsForMember(
      widget.selectedMemberId,
      folders: _launchContext.folderCatalog,
    );
    if (work.workingDirectory.isNotEmpty) return work.workingDirectory;
    return widget.session.firstFolderPath;
  }

  WorkspaceLaunchContext get _launchContext => WorkspaceLaunchContext(
    session: widget.session,
    workspace: widget.workspace,
  );

  Future<void> _loadHistory({bool force = false}) async {
    final seat = _seat;
    if (seat == null) return;
    if (force) {
      await seat.load(
        session: widget.session,
        memberId: widget.selectedMemberId,
        launchContext: _launchContext,
        team: widget.team,
        workingDirectory: _workspaceRoot,
        force: true,
      );
      if (!mounted) return;
      _maybeStartLiveRefreshForRunningPty();
      // Seat owns the working latch across remount — sync (do not force-clear)
      // so landing Starting survives long connects.
      _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
      if (seat.state.awaitingAssistant) {
        unawaited(_startLiveRefresh(skipInitialRefresh: true));
      }
      return;
    }
    // Soft when already ready for this seat — no loading flash / hard reload.
    await seat.softReloadOrLoad(
      session: widget.session,
      memberId: widget.selectedMemberId,
      launchContext: _launchContext,
      team: widget.team,
      workingDirectory: _workspaceRoot,
    );
    if (!mounted) return;
    _maybeStartLiveRefreshForRunningPty();
    // Landing seed / continue awaiting: refresh while PTY runs offstage.
    _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
    if (seat.state.awaitingAssistant) {
      unawaited(_startLiveRefresh(skipInitialRefresh: true));
    }
  }

  /// PTY shells for Simple seats are keyed by [AppSession.sessionId].
  String get _shellMemberId => shellMemberIdForHistory(
    sessionId: widget.session.sessionId,
    selectedMemberId: widget.selectedMemberId,
  );

  String get _followUpSeatKey =>
      followUpSeatKey(widget.session.sessionId, _shellMemberId);

  void _notifyFollowUpMemberWorking(ChatCubit chat) {
    chat.notifyFollowUpMemberWorking(
      widget.session.sessionId,
      _shellMemberId,
      working: chat.isMemberWorking(widget.session.sessionId, _shellMemberId),
    );
  }

  void _onUserStoppedTurn() {
    if (_userStoppedTurn.value) return;
    _userStoppedTurn.value = true;
    _seat?.flushHeldTip(endAwaiting: true);
    context.read<ChatCubit>().endOperatorDeliveryInFlight(
      widget.session.sessionId,
    );
  }

  /// Starting tip without PTY working yet — still offer Stop to cancel wait.
  bool _composeTurnStarting(ChatCubit chat) {
    if (_userStoppedTurn.value) return false;
    final rawWorking = chat.isMemberWorking(
      widget.session.sessionId,
      _shellMemberId,
    );
    if (rawWorking) return false;
    return _isSubmitting ||
        _historyContinueInFlight ||
        (_seat?.state.awaitingAssistant ?? false);
  }

  void _clearStoppedTurnIfSeatIdle(ChatCubit chat) {
    if (!_userStoppedTurn.value) return;
    if (chat.isMemberWorking(widget.session.sessionId, _shellMemberId)) {
      return;
    }
    _userStoppedTurn.value = false;
  }

  void _maybeStartLiveRefreshForRunningPty() {
    if (!mounted) return;
    final running = context.read<ChatCubit>().isMemberRunning(
      sessionId: widget.session.sessionId,
      memberId: _shellMemberId,
    );
    final hot = isHistorySeatHot(
      routeActive: widget.routeActive,
      isMemberRunning: running,
    );
    if (!hot) {
      unawaited(_liveRefresh?.stop() ?? Future<void>.value());
      return;
    }
    final seat = _seat;
    final skip = shouldSkipLiveRefreshInitialSoftReload(
      hasOptimisticPending: seat?.hasOptimisticPending ?? false,
      awaitingAssistant: seat?.state.awaitingAssistant ?? false,
    );
    unawaited(_startLiveRefresh(skipInitialRefresh: skip));
  }

  Future<void> _startLiveRefresh({bool skipInitialRefresh = false}) {
    // 单飞:并发调用(_loadHistory 完成回调、BlocListener working 翻转、
    // didUpdateWidget 在同一异步窗口内触发)共享一条启动链。否则多个调用
    // 都在 resolveSeatRuntime 的 await 前看到 _liveRefresh == null,
    // 各自通过复用检查后各建一个 controller。
    final inFlight = _liveRefreshStartInFlight;
    if (inFlight != null) return inFlight;
    final future = _startLiveRefreshImpl(
      skipInitialRefresh: skipInitialRefresh,
    );
    _liveRefreshStartInFlight = future;
    future.whenComplete(() {
      if (identical(_liveRefreshStartInFlight, future)) {
        _liveRefreshStartInFlight = null;
      }
    }).ignore();
    return future;
  }

  Future<void> _startLiveRefreshImpl({bool skipInitialRefresh = false}) async {
    final seat = _seat;
    if (seat == null) return;
    final chat = context.read<ChatCubit>();
    final running = chat.isMemberRunning(
      sessionId: widget.session.sessionId,
      memberId: _shellMemberId,
    );
    final hot = isHistorySeatHot(
      routeActive: widget.routeActive,
      isMemberRunning: running,
    );
    if (!hot) {
      await _liveRefresh?.stop();
      return;
    }
    // 复用:seat 作用域未变时直接 ensureStarted(幂等),不再重建 controller。
    // 旧实现每次调用都"停旧建新",agent 活跃期 working 状态翻转频繁,
    // 同一时刻会并存多个 controller,且被停实例的在途查询仍会跑完。
    final scope =
        '${widget.session.sessionId}|${widget.selectedMemberId}'
        '|${widget.team?.id ?? ''}|${widget.workspace.workspaceId}';
    if (_liveRefresh != null && _liveRefreshScope == scope) {
      await _liveRefresh!.ensureStarted(skipInitialRefresh: skipInitialRefresh);
      return;
    }
    try {
      final historyCubit = context.read<AiHistoryCubit>();
      final loader =
          context
              .read<ChatCubit>()
              .podRuntime(widget.session.sessionId)
              ?.history
              ?.loader ??
          historyCubit.loader;
      final roots = await loader.resolveSeatRuntime(
        launchContext: _launchContext,
        memberId: widget.selectedMemberId,
      );
      if (!mounted || !identical(_seat, seat)) return;
      final stillRunning = chat.isMemberRunning(
        sessionId: widget.session.sessionId,
        memberId: _shellMemberId,
      );
      if (!isHistorySeatHot(
        routeActive: widget.routeActive,
        isMemberRunning: stillRunning,
      )) {
        await _liveRefresh?.stop();
        return;
      }
      await _liveRefresh?.stop();
      _liveRefreshScope = scope;
      _liveRefresh = AiHistoryLiveRefreshController(
        seat: seat,
        fs: () => roots.filesystem,
        resolveWatchMeta: () => loader.resolveWatchMeta(
          launchContext: _launchContext,
          memberId: widget.selectedMemberId,
          team: widget.team,
          workingDirectory: _workspaceRoot,
        ),
      );
      await _liveRefresh!.ensureStarted(skipInitialRefresh: skipInitialRefresh);
    } on Object catch (e, st) {
      // Live refresh is best-effort; seat load already surfaces History errors.
      // Avoid PlatformDispatcher noise when work-context resolve fails (e.g.
      // stale loader after hot reload across AiHistoryLoader API changes).
      appLogger.w(
        '[session-chat] live refresh failed session=${widget.session.sessionId} '
        'member=${widget.selectedMemberId}: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _stopLiveRefreshForSeatChange() async {
    final previous = _liveRefresh;
    _liveRefresh = null;
    _liveRefreshScope = null;
    await previous?.stop();
  }

  AppSession? _sessionFromCubit(ChatCubit cubit) {
    final id = widget.session.sessionId;
    for (final session in cubit.state.sessions) {
      if (session.sessionId == id) return session;
    }
    return null;
  }

  /// Reactive snapshot for [build] only (`context.select`).
  AppSession? _watchCubitSession(BuildContext context) {
    final identity = seatSelect<ChatCubit, SessionChatIdentity?>(
      context,
      (c) => SessionChatIdentity.tryFromChatState(
        c.state,
        widget.session.sessionId,
      ),
    );
    if (identity == null) return _sessionFromCubit(context.read<ChatCubit>());
    return identity.applyTo(widget.session);
  }

  /// One-shot lookup for event handlers (`context.read`).
  AppSession? _readCubitSession(BuildContext context) =>
      _sessionFromCubit(context.read<ChatCubit>());

  /// Build-only display session (`context.select`). Do not call from handlers.
  AppSession _watchDisplaySession(BuildContext context) =>
      _watchCubitSession(context) ?? widget.session;

  /// Event-handler display session (`context.read`).
  AppSession _readDisplaySession(BuildContext context) =>
      _readCubitSession(context) ?? widget.session;

  TeamProfile? _liveTeamFor(AppSession session, LaunchProfileCubit cubit) {
    if (session.isSimple) return null;
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) return null;
    final profile = cubit.byId(teamId);
    if (profile is TeamProfile) return profile;
    return widget.team;
  }

  /// Build-only live team (`context.watch`). Do not call from handlers.
  /// Build-only live team — uses [context.select] scoped to the session's team
  /// profile so other profile changes do not rebuild this widget. Do not call
  /// from handlers.
  TeamProfile? _watchLiveTeam(BuildContext context) {
    final session = _watchDisplaySession(context);
    if (session.isSimple) return null;
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) return null;
    return seatSelect<LaunchProfileCubit, TeamProfile?>(context, (c) {
      final profile = c.byId(teamId);
      return profile is TeamProfile ? profile : widget.team;
    });
  }

  /// Event-handler live team (`context.read`).
  TeamProfile? _readLiveTeam(BuildContext context) => _liveTeamFor(
    _readDisplaySession(context),
    context.read<LaunchProfileCubit>(),
  );

  String _effectiveMemberId(TeamProfile? team) {
    if (widget.session.isSimple || team == null) return '';
    final mid = widget.selectedMemberId.trim();
    if (mid.isNotEmpty) return mid;
    return team.members.where(TeamMemberNaming.isTeamLead).firstOrNull?.id ??
        team.members.firstOrNull?.id ??
        '';
  }

  TeamMemberConfig? _selectedMember(TeamProfile? team) {
    if (team == null) return null;
    final mid = _effectiveMemberId(team);
    if (mid.isEmpty) return null;
    return team.members.where((m) => m.id == mid).firstOrNull;
  }

  CliTool _lockedCli({
    required AppSession session,
    required TeamProfile? team,
    required List<CliPreset> presets,
  }) {
    if (session.isSimple) return session.cli ?? CliTool.claude;
    if (team == null) return CliTool.claude;
    final memberId = _effectiveMemberId(team);
    final member = _selectedMember(team);
    return SessionMemberCliResolver.resolve(
      persistedSession: session,
      team: team,
      memberId: memberId.isNotEmpty ? memberId : (member?.id ?? ''),
      globalPresets: presets,
      cliForMember: (t, id, {List<CliPreset> globalPresets = const []}) {
        final m = (member != null && member.id == id)
            ? member
            : () {
                for (final x in t.members) {
                  if (x.id == id) return x;
                }
                return null;
              }();
        if (m != null) {
          return memberLaunchCli(
            team: t,
            member: m,
            globalPresets: globalPresets,
          );
        }
        return t.cli;
      },
    );
  }

  Future<void> _attachFiles() async {
    if (_isSubmitting) return;
    await pickAndInsertComposeFileReferences(
      controller: _controller,
      workspaceRoot: _workspaceRoot,
      filesystem: AppStorage.fs,
    );
    if (!mounted) return;
    _focusNode.requestFocus();
  }

  Future<bool> _pasteComposeImage() async {
    if (_isSubmitting) return false;
    final pasted = await pasteComposeImageAttachment(
      controller: _controller,
      workspaceRoot: _workspaceRoot,
    );
    return pasted;
  }

  Future<HistoryContinueSubmitResult> _handleComposeSubmit(String text) async {
    if (_isSubmitting) return const HistoryContinueSubmitResult.failed();
    final trimmed = text.trim();
    final selectedMemberId = widget.selectedMemberId;
    final chat = context.read<ChatCubit>();
    final permissionWaiting =
        AgentPermissionAttentionBanner.isSelectedSeatWaiting(
          attention: context.read<AgentAttentionCubit>(),
          session: widget.session,
          selectedMemberId: selectedMemberId,
        );
    final memberWorking =
        chat.isMemberWorking(
          widget.session.sessionId,
          _shellMemberId,
        ) &&
        !_userStoppedTurn.value;
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    final lockedCli = _lockedCli(
      session: _readDisplaySession(context),
      team: _readLiveTeam(context),
      presets: context.read<CliPresetsCubit>().state.presets,
    );
    final supportsTurnInterrupt =
        registry
            .capability<TerminalBehaviorCapability>(lockedCli)
            ?.supportsTurnInterrupt ??
        false;
    final action = resolveHistoryComposeSubmitAction(
      permissionWaiting: permissionWaiting,
      memberWorking: memberWorking,
      trimmedText: trimmed,
      supportsTurnInterrupt: supportsTurnInterrupt,
    );

    var delivered = false;
    dispatchHistoryComposeSubmit(
      action: action,
      text: trimmed,
      onEnqueue: (queued) {
        chat.followUpQueue.enqueue(_followUpSeatKey, queued);
        unawaited(
          _discardComposeDraftForSubmit(holdListenerSuppress: false),
        );
        _notifyFollowUpMemberWorking(chat);
      },
      onDeliver: (_) {
        delivered = true;
        _userStoppedTurn.value = false;
      },
    );
    if (!delivered) return const HistoryContinueSubmitResult.failed();

    return await _deliverComposeMessage(
      trimmed,
      retryRecord: _editingFailedMessage,
    );
  }

  Future<HistoryContinueSubmitResult> _deliverComposeMessage(
    String text, {
    FailedMessageRecord? retryRecord,
    bool clearCompose = true,
  }) async {
    if (text.isEmpty) return const HistoryContinueSubmitResult.failed();
    final selectedMemberId = widget.selectedMemberId;
    if (AgentPermissionAttentionBanner.isSelectedSeatWaiting(
      attention: context.read<AgentAttentionCubit>(),
      session: widget.session,
      selectedMemberId: selectedMemberId,
    )) {
      return const HistoryContinueSubmitResult.failed();
    }

    final seat = _seat;
    if (seat == null) return const HistoryContinueSubmitResult.failed();
    // Peek before connect so mailbox continues skip optimistic thread pending.
    // onSubmit re-resolves after connect; rollback if peek was wrong.
    final peek =
        widget.peekContinueChannel?.call() ?? HistoryContinueChannel.pty;
    final optimisticPty = peek == HistoryContinueChannel.pty;
    final retryingRecord = retryRecord?.copyWith(text: text);
    final pendingRecord = retryingRecord != null
        ? await seat.retryPendingUser(
            store: _failedMessageStore,
            workspaceId: widget.session.workspaceId,
            sessionId: widget.session.sessionId,
            record: retryingRecord,
          )
        : optimisticPty
        ? await seat.persistPendingUser(
            store: _failedMessageStore,
            workspaceId: widget.session.workspaceId,
            sessionId: widget.session.sessionId,
            text: text,
          )
        : null;
    if (!mounted) return const HistoryContinueSubmitResult.failed();
    _historyContinueInFlight = true;
    _submitBusy.value = true;
    try {
      if (optimisticPty) {
        _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
      }
      // Clear drafts as soon as send starts. Recovery for failed delivery is
      // the optimistic / failed history bubble — not the compose field.
      if (clearCompose) {
        await _discardComposeDraftForSubmit();
      }

      final result = await _submitLock.run(() => widget.onSubmit(text));
      if (!mounted) return const HistoryContinueSubmitResult.failed();
      if (!result.ok) {
        _suppressComposeDraftPersistence = false;
        _cancelAwaitingIdleGrace();
        if (pendingRecord != null) {
          await seat.markPendingFailed(
            store: _failedMessageStore,
            workspaceId: widget.session.workspaceId,
            sessionId: widget.session.sessionId,
            record: pendingRecord,
          );
        }
        if (retryingRecord != null) {
          _editingFailedMessage = retryingRecord.copyWith(
            status: FailedMessageStatus.failed,
          );
        }
        setState(() {});
        return result;
      }

      if (retryingRecord != null) _editingFailedMessage = null;
      if (!mounted) return result;

      if (result.isMailbox) {
        _cancelAwaitingIdleGrace();
        if (optimisticPty) seat.removePendingMatching(text);
        if (pendingRecord != null) {
          await _failedMessageStore.remove(
            widget.session.workspaceId,
            widget.session.sessionId,
            pendingRecord.id,
          );
        }
        final mailId = result.mailId!;
        _mailboxQueuedSeats[mailId] = _mailboxSeatKey();
        _mailboxQueued.add(PendingUserMessage(id: mailId, content: text));
        setState(() {});
        // Mailbox text is not in the CLI transcript — skip live refresh churn.
        return result;
      }

      if (!optimisticPty && pendingRecord == null) {
        // Peek said mailbox but post-connect path was PTY — show the bubble now.
        seat.enqueuePendingUser(text);
        _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
      }
      // Keep the optimistic bubble until the CLI transcript gains a user turn
      // (_reconcilePendings). Removing here left History blank while the CLI
      // was still processing.
      unawaited(_startLiveRefresh());
      return result;
    } finally {
      _historyContinueInFlight = false;
      if (mounted) {
        _submitBusy.value = false;
        _suppressComposeDraftPersistence = false;
        // Stop during Starting may race deliver settle — keep tip cleared.
        if (_userStoppedTurn.value) {
          _seat?.flushHeldTip(endAwaiting: true);
        }
      }
    }
  }

  Future<FailedMessageRecord?> _loadFailedMessage(String messageId) async {
    final seat = _seat;
    if (seat == null) return null;
    final scope = HistoryHydrationScope(
      seat: seat,
      sessionId: widget.session.sessionId,
      memberId: widget.selectedMemberId,
    );
    final records = await _failedMessageStore.load(
      widget.session.workspaceId,
      widget.session.sessionId,
    );
    if (!mounted ||
        !scope.isCurrent(
          seat: _seat,
          sessionId: widget.session.sessionId,
          memberId: widget.selectedMemberId,
        )) {
      return null;
    }
    for (final record in records) {
      if (record.id == messageId &&
          record.status == FailedMessageStatus.failed) {
        return record;
      }
    }
    return null;
  }

  Future<void> _retryFailedMessage(String messageId) async {
    if (_isSubmitting || !_retryingFailedMessageIds.add(messageId)) return;
    try {
      final record = await _loadFailedMessage(messageId);
      if (record == null || !mounted) return;
      await _deliverComposeMessage(
        record.text,
        retryRecord: record,
        clearCompose: false,
      );
    } finally {
      _retryingFailedMessageIds.remove(messageId);
    }
  }

  void _cancelAwaitingIdleGrace() {
    _awaitingIdleGraceTimer?.cancel();
    _awaitingIdleGraceTimer = null;
  }

  void _scheduleAwaitingIdleGrace() {
    if (_awaitingIdleGraceTimer != null) return;
    _awaitingIdleGraceTimer = Timer(historyAwaitingIdleGrace, () {
      _awaitingIdleGraceTimer = null;
      if (!mounted) return;
      final seat = _seat;
      if (seat == null || !seat.state.awaitingAssistant) return;
      final cubit = context.read<ChatCubit>();
      final chat = cubit.state;
      final sid = widget.session.sessionId;
      final working = chat.isSessionBusy(sid);
      if (working) {
        // Working rose during grace — latch via normal sync.
        seat.applyWorkingSessionSync(
          sessionWorking: true,
          sessionConnecting: _podConnecting(cubit, sid),
          memberRunning: cubit.isMemberRunning(
            sessionId: sid,
            memberId: _shellMemberId,
          ),
          historyContinueInFlight: _historyContinueInFlight,
        );
        return;
      }
      // Still idle after grace — settle Starting/Running.
      seat.flushHeldTip(endAwaiting: true);
    });
  }

  void _syncAwaitingFromWorkingSessions(ChatState chat, {ChatCubit? cubit}) {
    final seat = _seat;
    if (seat == null) return;
    final sid = widget.session.sessionId;
    final chatCubit = cubit ?? context.read<ChatCubit>();
    final action = seat.applyWorkingSessionSync(
      sessionWorking: chat.isSessionBusy(sid),
      sessionConnecting: _podConnecting(chatCubit, sid),
      memberRunning: context.read<ChatCubit>().isMemberRunning(
        sessionId: sid,
        memberId: _shellMemberId,
      ),
      historyContinueInFlight: _historyContinueInFlight,
    );
    switch (action) {
      case HistoryAwaitingWorkingAction.none:
      case HistoryAwaitingWorkingAction.resetLatch:
      case HistoryAwaitingWorkingAction.latchWorking:
      case HistoryAwaitingWorkingAction.clearAwaiting:
        _cancelAwaitingIdleGrace();
        return;
      case HistoryAwaitingWorkingAction.deferWhileStarting:
        // Keep Starting; cancel any grace started before connect began.
        _cancelAwaitingIdleGrace();
        return;
      case HistoryAwaitingWorkingAction.scheduleGraceClear:
        _scheduleAwaitingIdleGrace();
        return;
    }
  }

  /// Whether this session is currently connecting, derived from its own pod
  /// phase.
  static bool _podConnecting(ChatCubit cubit, String sessionId) =>
      cubit.podFor(sessionId)?.phase.isLaunching ?? false;

  @override
  Widget build(BuildContext context) {
    final viewToggle = widget.viewToggle;
    if (viewToggle == null) return _buildContent(context);
    final spacing = context.tpSpacing;
    final controller = _taskBoardController;
    Widget capsule() => AiMessageStringsScope(
      strings: aiMessageStringsFromL10n(context.l10n),
      child: controller == null
          ? AiTaskBoardPanel(items: const [], collapsedLeading: viewToggle)
          : ListenableBuilder(
              listenable: controller,
              builder: (context, _) => AiTaskBoardPanel(
                items: controller.board.aiItems,
                collapsedLeading: viewToggle,
              ),
            ),
    );
    return Stack(
      children: [
        Positioned.fill(child: _buildContent(context)),
        Positioned(top: spacing.sm, right: spacing.sm, child: capsule()),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final cs = Theme.of(context).colorScheme;
    final session = _watchDisplaySession(context);
    final team = _watchLiveTeam(context);
    final selectedMemberId = widget.selectedMemberId;

    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();

    // lockedCli is still needed by the parent for historyCap (subagent tools).
    final presets = seatSelect<CliPresetsCubit, List<CliPreset>>(
      context,
      (c) => c.state.presets,
    );
    final lockedCli = _lockedCli(
      session: session,
      team: team,
      presets: presets,
    );
    final historyCap = registry.capability<AiHistoryCapability>(lockedCli);
    watchSessionSeatWorking(
      context,
      workspaceId: widget.session.workspaceId,
      sessionId: widget.session.sessionId,
      memberId: _shellMemberId,
    );
    return ShortcutFocus(
      // The chat page owns Mod+F (find bar). Claimed so the global workspace
      // search / other Mod+F global commands stay suppressed here.
      claims: {
        KeyChord(key: 'f', mods: [KeyChordMod.mod]),
      },
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          // Ctrl+F (Linux/Windows) and Cmd+F (macOS) both toggle the find bar;
          // only the platform-matching activator fires for a given key press.
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              const _ChatFindToggleIntent(),
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              const _ChatFindToggleIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _ChatFindToggleIntent: CallbackAction<_ChatFindToggleIntent>(
              onInvoke: (_) {
                _toggleFind();
                return null;
              },
            ),
          },
          child: MultiBlocListener(
            listeners: [
              BlocListener<ChatCubit, ChatState>(
                listenWhen: (previous, current) =>
                    previous.isSessionBusy(widget.session.sessionId) !=
                    current.isSessionBusy(widget.session.sessionId),
                listener: (context, state) {
                  _syncAwaitingFromWorkingSessions(state);
                  _maybeStartLiveRefreshForRunningPty();
                  final chat = context.read<ChatCubit>();
                  _notifyFollowUpMemberWorking(chat);
                  _clearStoppedTurnIfSeatIdle(chat);
                },
              ),
              BlocListener<MemberPresenceCubit, MemberPresenceState>(
                listenWhen: (previous, current) {
                  const offline = MemberPresence.offline();
                  return (previous.presence[_shellMemberId] ?? offline) !=
                      (current.presence[_shellMemberId] ?? offline);
                },
                listener: (context, _) {
                  _notifyFollowUpMemberWorking(context.read<ChatCubit>());
                },
              ),
            ],
            child: ColoredBox(
              color: cs.surface,
              child:
                  BlocSelector<
                    LayoutCubit,
                    LayoutState,
                    ({
                      bool expandReasoning,
                      bool expandTools,
                      bool autoOpenSubagentPreview,
                      ContentDisplayMode userMessageMode,
                      ContentDisplayMode chatCodeBlockMode,
                    })
                  >(
                    selector: (s) => (
                      expandReasoning: s.preferences.cotExpandReasoningOnOpen,
                      expandTools: s.preferences.cotExpandToolsOnOpen,
                      autoOpenSubagentPreview:
                          s.preferences.autoOpenSubagentPreview,
                      userMessageMode: s.preferences.chatUserMessageMode,
                      chatCodeBlockMode: s.preferences.chatCodeBlockMode,
                    ),
                    builder: (context, prefs) {
                      final expandReasoning = prefs.expandReasoning;
                      final expandTools = prefs.expandTools;
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final columnWidth = resolveSessionHistoryColumnWidth(
                            constraints.maxWidth,
                          );
                          return Theme(
                            data: Theme.of(context).copyWith(
                              extensions: [
                                for (final ext in Theme.of(
                                  context,
                                ).extensions.values)
                                  if (ext is! AiMessageTheme) ext,
                                AiMessageTheme.of(context).copyWith(
                                  markdown: buildAppMarkdownTokens(
                                    Theme.of(context),
                                    MarkdownProfile.compact,
                                    width: columnWidth,
                                    mutedSurface: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.55),
                                  ),
                                  userBubbleColor: cs.surfaceContainerHighest,
                                  userBubbleForeground: cs.onSurface,
                                  mutedSurface: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.55),
                                  toolTriggerColor: cs.onSurfaceVariant,
                                  messageSpacing: 24,
                                  threadMaxWidth: columnWidth,
                                  threadHorizontalPadding: spacing.md,
                                  cotExpandReasoningOnOpen: expandReasoning,
                                  cotExpandToolsOnOpen: expandTools,
                                ),
                              ],
                            ),
                            child: BlocBuilder<AiHistorySeat, AiHistoryState>(
                              bloc: _seat,
                              // Skip totalMessageCount-only tip growth — thread listens to
                              // runtime. Rebuild for chrome / overlay / awaiting flips.
                              buildWhen: (p, c) => debugBuildWhen(
                                p,
                                c,
                                tag: 'session_chat_view',
                                changed: {
                                  'status': p.status != c.status,
                                  'hasOlder': p.hasOlder != c.hasOlder,
                                  'awaitingAssistant':
                                      p.awaitingAssistant !=
                                      c.awaitingAssistant,
                                  'isLoadingOlder':
                                      p.isLoadingOlder != c.isLoadingOlder,
                                  'softReloadError':
                                      p.softReloadError != c.softReloadError,
                                  'sessionId': p.sessionId != c.sessionId,
                                  'memberId': p.memberId != c.memberId,
                                  'subagentAttachmentEpoch':
                                      p.subagentAttachmentEpoch !=
                                      c.subagentAttachmentEpoch,
                                  'errorMessage':
                                      p.errorMessage != c.errorMessage,
                                },
                                enable: false,
                              ),
                              builder: (context, state) {
                                final historySeat = _seat;
                                if (historySeat == null) {
                                  return const SizedBox.shrink();
                                }
                                return ListenableBuilder(
                                  listenable: Listenable.merge([
                                    _subagentPreview,
                                    _userStoppedTurn,
                                  ]),
                                  builder: (context, _) {
                                    _subagentPreview.pruneToAvailable(
                                      historySeat.subagentAttachments.keys
                                          .toSet(),
                                    );
                                    final runningSubagentIds =
                                        prefs.autoOpenSubagentPreview
                                        ? _runningSubagentIds(
                                            historySeat,
                                            historyCap,
                                          )
                                        : const <String>[];
                                    final pendingAuto = _subagentPreview
                                        .computeAutoFollow(
                                          prefEnabled:
                                              prefs.autoOpenSubagentPreview,
                                          runningIds: runningSubagentIds,
                                          availableIds: runningSubagentIds
                                              .toSet(),
                                        );
                                    if (pendingAuto != null) {
                                      final id = pendingAuto;
                                      // Deferred: never notify inside build.
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) async {
                                            if (!mounted) return;
                                            final attachment = await historySeat
                                                .loadSubagentAttachment(id);
                                            if (!mounted) return;
                                            if (attachment == null) return;
                                            _subagentPreview.autoOpen(id);
                                          });
                                    }
                                    final stack = _subagentPreview.stack;
                                    final top = stack.isEmpty
                                        ? null
                                        : historySeat.subagentAttachments[stack
                                              .last];
                                    final topTitle = top?.title?.trim();
                                    final previewTitle = l10n
                                        .subagentPreviewTitleAgent(
                                          (topTitle != null &&
                                                  topTitle.isNotEmpty)
                                              ? topTitle
                                              : 'Agent',
                                        );

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        SessionChatMessageArea(
                                          session: widget.session,
                                          workspace: widget.workspace,
                                          selectedMemberId: selectedMemberId,
                                          shellMemberId: _shellMemberId,
                                          isSubmitting: _isSubmitting,
                                          userStoppedTurn:
                                              _userStoppedTurn.value,
                                          state: state,
                                          historySeat: historySeat,
                                          top: top,
                                          previewTitle: previewTitle,
                                          subagentPreview: _subagentPreview,
                                          taskBoardController:
                                              _taskBoardController,
                                          findVisible: _findVisible,
                                          highlightMessageId:
                                              _locateHighlightId,
                                          visibleOwnerId: _visibleOwnerId,
                                          onLocateOutline: (e) => unawaited(
                                            _locator.locate(
                                              id: e.id,
                                              index: e.messageIndex,
                                              highlight: false,
                                              animate: true,
                                            ),
                                          ),
                                          findController: _findController,
                                          findQueryController:
                                              _findQueryController,
                                          findFocusNode: _findFocusNode,
                                          revealController: _revealController,
                                          historyCap: historyCap,
                                          onRetry: () =>
                                              _loadHistory(force: true),
                                          onRetryFailedMessage: (id) =>
                                              unawaited(
                                                _retryFailedMessage(id),
                                              ),
                                          onCloseFind: _closeFind,
                                          onNavigateFind: _navigateFindTo,
                                        ),
                                        if (top == null)
                                          ListenableBuilder(
                                            listenable: Listenable.merge([
                                              _submitBusy,
                                              _userStoppedTurn,
                                            ]),
                                            builder: (context, _) {
                                              return SessionChatComposeSection(
                                                session: session,
                                                workspace: widget.workspace,
                                                selectedMemberId:
                                                    selectedMemberId,
                                                shellMemberId: _shellMemberId,
                                                composeController: _controller,
                                                composeClip: _clip,
                                                composeFocusNode: _focusNode,
                                                voiceController: _voice,
                                                isSubmitting: _isSubmitting,
                                                workspaceRoot: _workspaceRoot,
                                                workspaceBundle:
                                                    _workspaceBundle,
                                                launchError: widget.launchError,
                                                onRemapDeadTarget:
                                                    widget.onRemapDeadTarget,
                                                onRetry: widget.onRetry,
                                                sessionConnectInProgress: widget
                                                    .sessionConnectInProgress,
                                                isMailboxUnread:
                                                    widget.isMailboxUnread,
                                                mailboxQueued: _mailboxQueued,
                                                mailboxQueuedSeats:
                                                    _mailboxQueuedSeats,
                                                mailboxQueuedClearToken:
                                                    _mailboxQueuedClearToken,
                                                onMailboxConsumed: (mailId) {
                                                  if (!mounted) return;
                                                  unawaited(
                                                    _seat
                                                        ?.refreshMailboxTimeline(),
                                                  );
                                                },
                                                onAttach: () =>
                                                    unawaited(_attachFiles()),
                                                onPasteImage:
                                                    _pasteComposeImage,
                                                routeActive: widget.routeActive,
                                                onSubmit: _handleComposeSubmit,
                                                userStoppedTurn:
                                                    _userStoppedTurn.value,
                                                onUserStoppedTurn:
                                                    _onUserStoppedTurn,
                                                turnStarting: _composeTurnStarting(
                                                  context.read<ChatCubit>(),
                                                ),
                                              );
                                            },
                                          ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subagent tool calls still in flight (newest-first), for auto-follow.
/// [computeAutoFollow] lazy-loads the selected id via [AiHistorySeat.loadSubagentAttachment].
List<String> _runningSubagentIds(AiHistorySeat seat, AiHistoryCapability? cap) {
  if (cap == null) return const [];
  final names = cap.subagentToolNames;
  final out = <String>[];
  final messages = seat.loadedMessages;
  for (var i = messages.length - 1; i >= 0; i--) {
    for (final part in messages[i].parts) {
      if (part is! AiToolCallPart) continue;
      if (part.status != AiToolCallStatus.incomplete) continue;
      if (!names.contains(part.toolName.trim().toLowerCase())) continue;
      final id = part.toolCallId.trim();
      if (id.isNotEmpty) out.add(id);
    }
  }
  return out;
}
