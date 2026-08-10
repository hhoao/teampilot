import 'dart:async';

import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../cubits/ai_history_cubit.dart';
import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/landing_launch_context.dart';
import '../../models/member_presence.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../services/ai/headless_ai_service.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/cli/registry/capabilities/ai_history_capability.dart';
import '../../services/cli/registry/capabilities/turn_interrupt_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/cli/tasks/cli_task_board_controller.dart';
import '../../services/compose/compose_draft_cache.dart';
import '../../services/compose/compose_file_attach.dart';
import '../../services/compose/compose_prompt_enhance.dart';
import 'session_chat_voice_controller.dart';
import '../../services/follow_up/follow_up_queue.dart';
import '../../services/session/ai_history_live_refresh_controller.dart';
import '../../services/session/chat_transcript_find_controller.dart';
import '../../services/session/history_seat_key.dart';
import '../../services/session/history_awaiting_working_sync.dart';
import '../../services/session/session_history_pagination.dart';
import '../../services/storage/app_storage.dart';
import '../../services/terminal/pending_user_message.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';
import 'session_chat_compose_section.dart';
import 'session_chat_message_area.dart';
import 'agent_permission_attention_banner.dart';
import 'chat_find_bar.dart';
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

  @override
  State<SessionChatView> createState() => _SessionChatViewState();
}

class _SessionChatViewState extends State<SessionChatView> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  late final SessionVoiceController _voice;
  final _headlessAi = HeadlessAiService();
  final _subagentPreview = SubagentPreviewController();
  AiHistoryLiveRefreshController? _liveRefresh;
  AiHistorySeat? _seat;
  CliTaskBoardController? _taskBoardController;

  final _submitLock = HistoryContinueSubmitLock();
  final _mailboxQueued = StreamController<PendingUserMessage>.broadcast();

  /// mailId → seat key at queue time (guards wrong-seat timeline refresh).
  final Map<String, String> _mailboxQueuedSeats = {};
  var _mailboxQueuedClearToken = 0;
  var _enhancing = false;

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
  bool _findVisible = false;
  String? _findHighlightId;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'session_history_review_compose');
    _voice = SessionVoiceController(composeController: _controller);
    _voice.onNeedsHostRebuild = () {
      if (mounted) setState(() {});
    };
    _voice.initialize();
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
    _bindSeat();
    _loadHistory();
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
    final seatChanged =
        oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.selectedMemberId != widget.selectedMemberId ||
        oldWidget.team?.id != widget.team?.id;
    if (seatChanged) {
      unawaited(_stopLiveRefreshForSeatChange());
      _clearMailboxQueuedUi();
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
        _loadHistory();
      });
    } else if (oldWidget.routeActive != widget.routeActive) {
      _maybeStartLiveRefreshForRunningPty();
    }
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
      _findHighlightId = null;
    });
    _revealController.clear();
  }

  void _navigateFindTo(TranscriptHit hit) {
    final seat = _seat;
    if (seat != null) {
      seat.revealMessage(hit.messageIndex);
    }
    setState(() => _findHighlightId = hit.messageId);
    // Reveal after the frame so the seat's window update has reached the thread
    // and the target message is in `displayMessages` when the offset is computed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealController.reveal(hit.messageId);
    });
  }

  @override
  void dispose() {
    _awaitingIdleGraceTimer?.cancel();
    _awaitingIdleGraceTimer = null;
    _controller.removeListener(_onComposeChanged);
    _voice.dispose();
    final live = _liveRefresh;
    _liveRefresh = null;
    unawaited(live?.stop() ?? Future<void>.value());
    _taskBoardController?.dispose();
    _taskBoardController = null;
    unawaited(_mailboxQueued.close());
    _subagentPreview.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _findQueryController.dispose();
    _findFocusNode.dispose();
    _findController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  void _onComposeChanged() {
    composeDraftCache.setSessionDraft(
      widget.session.sessionId,
      _controller.text,
    );
    if (mounted) setState(() {});
  }

  bool get _isSubmitting => _submitLock.isBusy || widget.isSubmitting;

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

  void _loadHistory({bool force = false}) {
    final seat = _seat;
    if (seat == null) return;
    if (force) {
      unawaited(
        seat
            .load(
              session: widget.session,
              memberId: widget.selectedMemberId,
              launchContext: _launchContext,
              team: widget.team,
              workingDirectory: _workspaceRoot,
              force: true,
            )
            .then((_) {
              if (!mounted) return;
              _maybeStartLiveRefreshForRunningPty();
              // Seat owns the working latch across remount — sync (do not
              // force-clear) so landing Starting survives long connects.
              _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
              if (seat.state.awaitingAssistant) {
                unawaited(_startLiveRefresh(skipInitialRefresh: true));
              }
            }),
      );
      return;
    }
    // Soft when already ready for this seat — no loading flash / hard reload.
    unawaited(
      seat
          .softReloadOrLoad(
            session: widget.session,
            memberId: widget.selectedMemberId,
            launchContext: _launchContext,
            team: widget.team,
            workingDirectory: _workspaceRoot,
          )
          .then((_) {
            if (!mounted) return;
            _maybeStartLiveRefreshForRunningPty();
            // Landing seed / continue awaiting: refresh while PTY runs offstage.
            _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
            if (seat.state.awaitingAssistant) {
              unawaited(_startLiveRefresh(skipInitialRefresh: true));
            }
          }),
    );
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
    // softReloadOrLoad already refreshed once on this load path — attach the
    // change signal without stacking ensureStarted → refreshNow softReload.
    unawaited(_startLiveRefresh(skipInitialRefresh: true));
  }

  Future<void> _startLiveRefresh({bool skipInitialRefresh = false}) async {
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
      if (mounted) setState(() {});
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
    await previous?.stop();
    if (mounted) setState(() {});
  }

  LandingLaunchContext _enhanceDraft([AppSession? live]) {
    final session = live ?? widget.session;
    final isPersonal = session.sessionTeam.trim().isEmpty;
    return LandingLaunchContext(
      isPersonal: isPersonal,
      presetId: isPersonal
          ? (session.presetId.trim().isEmpty ? null : session.presetId)
          : null,
      teamId: isPersonal ? null : session.sessionTeam,
      expertKey: session.expertKey.trim().isEmpty
          ? null
          : session.expertKey,
      workingDirectoryPath: _workspaceRoot,
      cli: isPersonal ? session.cli : null,
      provider: isPersonal ? session.provider : null,
      model: isPersonal ? session.model : null,
      effort: isPersonal ? session.effort : null,
    );
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
    return context.select<ChatCubit, AppSession?>(_sessionFromCubit);
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
    return context.select<LaunchProfileCubit, TeamProfile?>((c) {
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
    if (_isSubmitting || _enhancing) return;
    await pickAndInsertComposeFileReferences(
      controller: _controller,
      workspaceRoot: _workspaceRoot,
      filesystem: AppStorage.fs,
    );
    if (!mounted) return;
    setState(() {});
    _focusNode.requestFocus();
  }

  Future<bool> _pasteComposeImage() async {
    if (_isSubmitting || _enhancing) return false;
    final pasted = await pasteComposeImageAttachment(
      controller: _controller,
      workspaceRoot: _workspaceRoot,
    );
    if (pasted && mounted) setState(() {});
    return pasted;
  }

  Future<void> _enhancePrompt() async {
    final draft = _controller.text.trim();
    if (draft.isEmpty || _isSubmitting || _enhancing) return;

    final live = _readCubitSession(context) ?? widget.session;
    final setting = resolveLandingEnhanceSetting(
      draft: _enhanceDraft(live),
      presets: context.read<CliPresetsCubit>().state.presets,
      teams: context.read<LaunchProfileCubit>().state.teams,
      appProviders: context.read<AppProviderCubit>().state,
      registry: CliToolRegistryScope.of(context),
    );
    if (setting == null) {
      AppToast.show(
        context,
        message: context.l10n.workspaceChatLandingEnhanceNotConfigured,
        variant: TpToastVariant.warning,
      );
      return;
    }

    setState(() => _enhancing = true);
    try {
      final result = await _headlessAi.run(
        setting: setting,
        prompt: buildComposeEnhancePrompt(draft),
        workingDirectory: _workspaceRoot.isEmpty ? null : _workspaceRoot,
      );
      if (!mounted) return;
      final enhanced = cleanComposeEnhanceOutput(result.text);
      if (enhanced.isEmpty) {
        AppToast.show(
          context,
          message: context.l10n.workspaceChatLandingEnhanceFailed,
          variant: TpToastVariant.warning,
        );
        return;
      }
      _controller.text = enhanced;
      _controller.selection = TextSelection.collapsed(offset: enhanced.length);
      setState(() {});
      _focusNode.requestFocus();
    } on HeadlessAiException catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: e.message,
        variant: TpToastVariant.warning,
      );
    } on Object {
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.workspaceChatLandingEnhanceFailed,
        variant: TpToastVariant.warning,
      );
    } finally {
      if (mounted) setState(() => _enhancing = false);
    }
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
    final memberWorking = chat.isMemberWorking(
      widget.session.sessionId,
      _shellMemberId,
    );
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    final lockedCli = _lockedCli(
      session: _readDisplaySession(context),
      team: _readLiveTeam(context),
      presets: context.read<CliPresetsCubit>().state.presets,
    );
    final supportsTurnInterrupt =
        registry
            .capability<TurnInterruptCapability>(lockedCli)
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
        _controller.clear();
        _notifyFollowUpMemberWorking(chat);
        if (mounted) setState(() {});
      },
      onDeliver: (_) => delivered = true,
    );
    if (!delivered) return const HistoryContinueSubmitResult.failed();

    return await _deliverComposeMessage(trimmed);
  }

  Future<HistoryContinueSubmitResult> _deliverComposeMessage(String text) async {
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
    if (optimisticPty) {
      seat.enqueuePendingUser(text);
      _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
    }
    _controller.clear();
    if (mounted) setState(() {});

    final result = await _submitLock.run(() async {
      if (mounted) setState(() {});
      return widget.onSubmit(text);
    });
    if (!mounted) return const HistoryContinueSubmitResult.failed();
    setState(() {});
    if (!result.ok) {
      _cancelAwaitingIdleGrace();
      if (optimisticPty) seat.removePendingMatching(text);
      _controller
        ..text = text
        ..selection = TextSelection.collapsed(offset: text.length);
      setState(() {});
      return result;
    }

    if (result.isMailbox) {
      _cancelAwaitingIdleGrace();
      if (optimisticPty) seat.removePendingMatching(text);
      final mailId = result.mailId!;
      _mailboxQueuedSeats[mailId] = _mailboxSeatKey();
      _mailboxQueued.add(PendingUserMessage(id: mailId, content: text));
      setState(() {});
      // Mailbox text is not in the CLI transcript — skip live refresh churn.
      return result;
    }

    if (!optimisticPty) {
      // Peek said mailbox but post-connect path was PTY — show the bubble now.
      seat.enqueuePendingUser(text);
      _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
    }
    unawaited(_startLiveRefresh());
    return result;
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
      final working = chat.workingSessionIds.contains(sid);
      if (working) {
        // Working rose during grace — latch via normal sync.
        seat.applyWorkingSessionSync(
          sessionWorking: true,
          sessionConnecting: _podConnecting(cubit, sid),
          memberRunning: cubit.isMemberRunning(
            sessionId: sid,
            memberId: _shellMemberId,
          ),
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
      sessionWorking: chat.workingSessionIds.contains(sid),
      sessionConnecting: _podConnecting(chatCubit, sid),
      memberRunning: context.read<ChatCubit>().isMemberRunning(
        sessionId: sid,
        memberId: _shellMemberId,
      ),
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
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final cs = Theme.of(context).colorScheme;
    final session = _watchDisplaySession(context);
    final team = _watchLiveTeam(context);
    final selectedMemberId = widget.selectedMemberId;

    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();

    // Rebuild when session working or bus presence changes (seat-level stop).
    context.select<ChatCubit, (String?, Set<String>)>(
      (c) => (c.state.activeSessionId, c.state.workingSessionIds),
    );
    context.select<MemberPresenceCubit, Map<String, MemberPresence>>(
      (c) => c.state.presence,
    );

    // lockedCli is still needed by the parent for historyCap (subagent tools).
    final presets = context.select<CliPresetsCubit, List<CliPreset>>(
      (c) => c.state.presets,
    );
    final lockedCli = _lockedCli(
      session: session,
      team: team,
      presets: presets,
    );
    final historyCap = registry.capability<AiHistoryCapability>(lockedCli);
    final askCardVisible = context.select<AgentAttentionCubit, bool>(
      (c) => AgentPermissionAttentionBanner.isSelectedSeatAskCard(
        attention: c,
        session: session,
        selectedMemberId: selectedMemberId,
        seatCli: lockedCli,
        registry: registry,
      ),
    );

    return ShortcutFocus(
      // The chat page owns Mod+F (find bar). Claimed so the global workspace
      // search / other Mod+F global commands stay suppressed here.
      claims: {KeyChord(key: 'f', mods: [KeyChordMod.mod])},
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
              previous.workingSessionIds != current.workingSessionIds ||
              previous.stateVersion != current.stateVersion,
          listener: (context, state) {
            _syncAwaitingFromWorkingSessions(state);
            _maybeStartLiveRefreshForRunningPty();
            _notifyFollowUpMemberWorking(context.read<ChatCubit>());
          },
        ),
        BlocListener<MemberPresenceCubit, MemberPresenceState>(
          listenWhen: (previous, current) =>
              previous.presence != current.presence,
          listener: (context, _) {
            _notifyFollowUpMemberWorking(context.read<ChatCubit>());
          },
        ),
      ],
      child: ColoredBox(
        color: cs.surface,
        child: BlocSelector<
          LayoutCubit,
          LayoutState,
          ({
            bool expandReasoning,
            bool expandTools,
            ContentDisplayMode userMessageMode,
            ContentDisplayMode chatCodeBlockMode,
          })
        >(
          selector: (s) => (
            expandReasoning: s.preferences.cotExpandReasoningOnOpen,
            expandTools: s.preferences.cotExpandToolsOnOpen,
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
                      for (final ext in Theme.of(context).extensions.values)
                        if (ext is! AiMessageTheme) ext,
                      AiMessageTheme.of(context).copyWith(
                        markdown: buildAppMarkdownTokens(
                          Theme.of(context),
                          MarkdownProfile.compact,
                          // v1: window width, not chat column width.
                          width: MediaQuery.sizeOf(context).width,
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
                buildWhen: (previous, current) =>
                    previous.status != current.status ||
                    previous.hasOlder != current.hasOlder ||
                    previous.isLoadingOlder != current.isLoadingOlder ||
                    previous.softReloadError != current.softReloadError ||
                    previous.awaitingAssistant != current.awaitingAssistant ||
                    previous.sessionId != current.sessionId ||
                    previous.memberId != current.memberId ||
                    previous.subagentAttachmentEpoch !=
                        current.subagentAttachmentEpoch ||
                    previous.errorMessage != current.errorMessage,
                builder: (context, state) {
                  final historySeat = _seat;
                  if (historySeat == null) {
                    return const SizedBox.shrink();
                  }
                  return ListenableBuilder(
                    listenable: _subagentPreview,
                    builder: (context, _) {
                      _subagentPreview.pruneToAvailable(
                        historySeat.subagentAttachments.keys.toSet(),
                      );
                      final stack = _subagentPreview.stack;
                      final top = stack.isEmpty
                          ? null
                          : historySeat.subagentAttachments[stack.last];
                      final topTitle = top?.title?.trim();
                      final previewTitle = l10n.subagentPreviewTitleAgent(
                        (topTitle != null && topTitle.isNotEmpty)
                            ? topTitle
                            : 'Agent',
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SessionChatMessageArea(
                            session: widget.session,
                            workspace: widget.workspace,
                            selectedMemberId: selectedMemberId,
                            shellMemberId: _shellMemberId,
                            isSubmitting: _isSubmitting,
                            state: state,
                            historySeat: historySeat,
                            top: top,
                            previewTitle: previewTitle,
                            subagentPreview: _subagentPreview,
                            taskBoardController: _taskBoardController,
                            findVisible: _findVisible,
                            findHighlightId: _findHighlightId,
                            findController: _findController,
                            findQueryController: _findQueryController,
                            findFocusNode: _findFocusNode,
                            revealController: _revealController,
                            historyCap: historyCap,
                            onRetry: () => _loadHistory(force: true),
                            onCloseFind: _closeFind,
                            onNavigateFind: _navigateFindTo,
                          ),
                          if (top == null)
                            SessionChatComposeSection(
                              session: session,
                              workspace: widget.workspace,
                              selectedMemberId: selectedMemberId,
                              shellMemberId: _shellMemberId,
                              composeController: _controller,
                              composeFocusNode: _focusNode,
                              voiceController: _voice,
                              isSubmitting: _isSubmitting,
                              isEnhancing: _enhancing,
                              workspaceRoot: _workspaceRoot,
                              askCardVisible: askCardVisible,
                              launchError: widget.launchError,
                              onRemapDeadTarget: widget.onRemapDeadTarget,
                              onRetry: widget.onRetry,
                              sessionConnectInProgress:
                                  widget.sessionConnectInProgress,
                              isMailboxUnread: widget.isMailboxUnread,
                              mailboxQueued: _mailboxQueued,
                              mailboxQueuedSeats: _mailboxQueuedSeats,
                              mailboxQueuedClearToken: _mailboxQueuedClearToken,
                              onMailboxConsumed: (mailId) {
                                if (!mounted) return;
                                unawaited(_seat?.refreshMailboxTimeline());
                              },
                              onAttach: () => unawaited(_attachFiles()),
                              onEnhance: () => unawaited(_enhancePrompt()),
                              onPasteImage: _pasteComposeImage,
                              onComposeChanged: () => setState(() {}),
                              routeActive: widget.routeActive,
                              onSubmit: _handleComposeSubmit,
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
