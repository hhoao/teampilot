import 'dart:async';

import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../cubits/ai_history_cubit.dart';
import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/config_bundle.dart';
import '../../models/member_presence.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/ai/headless_ai_service.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/ai_history_capability.dart';
import '../../services/cli/registry/capabilities/turn_interrupt_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/compose/compose_at_file_refs.dart';
import '../../services/compose/compose_draft_cache.dart';
import '../../services/compose/compose_file_attach.dart';
import '../../services/compose/compose_file_drop_ingestor.dart';
import '../../services/compose/compose_landing_bundle.dart';
import '../../services/compose/compose_prompt_enhance.dart';
import '../../services/compose/compose_text_edit.dart';
import '../../services/compose/compose_voice_input.dart';
import '../../services/expert_hub/expert_member_resolver.dart';
import '../../services/follow_up/follow_up_queue.dart';
import '../../services/session/ai_history_live_refresh_controller.dart';
import '../../services/session/history_seat_key.dart';
import '../../services/session/history_awaiting_working_sync.dart';
import '../../services/session/session_continue_overrides_apply.dart';
import '../../services/session/session_history_pagination.dart';
import '../../services/storage/app_storage.dart';
import '../../services/ai_history/workspace_edit_line_highlighter.dart';
import '../../services/workbench/ai_tool_file_open_coordinator.dart';
import '../../services/workbench/session_member_filesystem.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../services/terminal/pending_user_message.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';
import '../../widgets/compose/compose_chrome.dart';
import '../../widgets/compose/compose_model_preset_chip.dart';
import '../../widgets/compose/simple_custom_launch_dialog.dart';
import '../../widgets/compose/workspace_compose_card.dart';
import '../../widgets/follow_up/follow_up_queue_strip.dart';
import '../home_workspace/workspace/workspace_landing_team_settings_dialog.dart';
import 'agent_permission_attention_banner.dart';
import 'compose_stop_visibility.dart';
import 'session_follow_up_compose_submit.dart';
import 'history_continue_delivery.dart';
import 'history_mailbox_queued_strip.dart';
import 'session_history_live_chrome.dart';
import 'session_history_review_messages.dart';
import 'session_history_review_submit.dart';
import 'subagent_preview_controller.dart';

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
  late final ComposeVoiceInput _voiceInput;
  final _headlessAi = HeadlessAiService();
  final _subagentPreview = SubagentPreviewController();
  AiHistoryLiveRefreshController? _liveRefresh;
  AiHistorySeat? _seat;

  final _submitLock = HistoryContinueSubmitLock();
  final _mailboxQueued = StreamController<PendingUserMessage>.broadcast();

  /// mailId → seat key at queue time (guards wrong-seat timeline refresh).
  final Map<String, String> _mailboxQueuedSeats = {};
  var _mailboxQueuedClearToken = 0;
  var _enhancing = false;
  var _voiceListening = false;
  var _voiceSoundLevel = 0.0;
  var _discardVoiceTranscript = false;
  TextEditingValue? _voiceInsertBaseline;
  Stopwatch? _voiceStopwatch;
  Timer? _voiceTimer;
  var _workspaceProjectBundle = const ConfigBundle();
  var _workspaceBundleGeneration = 0;

  /// Host-owned Timer for [historyAwaitingIdleGrace]; latch lives on the seat.
  Timer? _awaitingIdleGraceTimer;

  /// Compose Stop cleared Running chrome; ignore residual sessionWorking until
  /// the next user turn latches awaiting again.
  var _userStoppedTurn = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'session_history_review_compose');
    _voiceInput = ComposeVoiceInput(
      onFinalTranscript: (text) {
        if (!mounted || _discardVoiceTranscript) return;
        if (_voiceInsertBaseline != null) {
          _controller.value = _voiceInsertBaseline!;
        }
        _controller.value = insertTextAtSelection(
          _controller,
          text,
          separatorBefore: ' ',
          separatorAfter: ' ',
        );
        _voiceInsertBaseline = null;
        setState(() {});
      },
      onListeningChanged: (listening) {
        if (!mounted) return;
        _applyVoiceListening(listening);
      },
      onSoundLevel: (level) {
        if (!mounted) return;
        setState(() => _voiceSoundLevel = level);
      },
      onError: (error) {
        if (!mounted) return;
        final l10n = context.l10n;
        final message = speechRecognitionErrorIsPermissionDenied(error)
            ? l10n.workspaceChatLandingVoicePermissionDenied
            : l10n.workspaceChatLandingVoiceUnavailable;
        AppToast.show(
          context,
          message: message,
          variant: TpToastVariant.warning,
        );
        _applyVoiceListening(false);
      },
    );
    unawaited(_voiceInput.initialize());
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
    unawaited(_loadWorkspaceProjectBundle());
  }

  void _bindSeat() {
    _seat = context.read<AiHistoryCubit>().ensureSeat(
      sessionId: widget.session.sessionId,
      selectedMemberId: widget.selectedMemberId,
    );
  }

  void _applyVoiceListening(bool listening) {
    if (listening) {
      _discardVoiceTranscript = false;
      _voiceInsertBaseline ??= _controller.value;
      final needsRebuild = !_voiceListening || _voiceStopwatch == null;
      _voiceListening = true;
      if (_voiceStopwatch == null) _startVoiceSessionClock();
      if (needsRebuild && mounted) setState(() {});
      return;
    }
    if (!_voiceListening && _voiceStopwatch == null) return;
    if (_discardVoiceTranscript) {
      _voiceInsertBaseline = null;
    }
    _voiceListening = false;
    _stopVoiceSessionClock();
    if (mounted) setState(() {});
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
    if (oldWidget.session.workspaceId != widget.session.workspaceId) {
      unawaited(_loadWorkspaceProjectBundle());
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

  @override
  void dispose() {
    _awaitingIdleGraceTimer?.cancel();
    _awaitingIdleGraceTimer = null;
    _controller.removeListener(_onComposeChanged);
    _stopVoiceSessionClock();
    final live = _liveRefresh;
    _liveRefresh = null;
    unawaited(live?.stop() ?? Future<void>.value());
    unawaited(_mailboxQueued.close());
    _voiceInput.dispose();
    _subagentPreview.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onComposeChanged() {
    composeDraftCache.setSessionDraft(
      widget.session.sessionId,
      _controller.text,
    );
    if (mounted) setState(() {});
  }

  void _startVoiceSessionClock() {
    _voiceStopwatch = Stopwatch()..start();
    _voiceSoundLevel = 0;
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopVoiceSessionClock() {
    _voiceTimer?.cancel();
    _voiceTimer = null;
    _voiceStopwatch?.stop();
    _voiceStopwatch = null;
    _voiceSoundLevel = 0;
  }

  bool get _isSubmitting => _submitLock.isBusy || widget.isSubmitting;

  Duration get _voiceElapsed => _voiceStopwatch?.elapsed ?? Duration.zero;

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
    final cubit = context.read<AiHistoryCubit>();
    try {
      final roots = await cubit.loader.resolveSeatRuntime(
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
        resolveWatchMeta: () => cubit.loader.resolveWatchMeta(
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

  Future<void> _loadWorkspaceProjectBundle() async {
    final generation = ++_workspaceBundleGeneration;
    try {
      final config = await WorkspaceProjectConfigRepository().load(
        widget.session.workspaceId,
      );
      if (!mounted || generation != _workspaceBundleGeneration) return;
      setState(() => _workspaceProjectBundle = config.bundle);
    } on Object {
      if (!mounted || generation != _workspaceBundleGeneration) return;
      setState(() => _workspaceProjectBundle = const ConfigBundle());
    }
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

  ConfigBundle _slashBundle(BuildContext context) {
    final live = _readCubitSession(context) ?? widget.session;
    return slashBundleForLanding(
      draft: _enhanceDraft(live),
      team: widget.team,
      workspace: _workspaceProjectBundle,
      hubState: _expertHubState(context),
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
  TeamProfile? _watchLiveTeam(BuildContext context) => _liveTeamFor(
    _watchDisplaySession(context),
    context.watch<LaunchProfileCubit>(),
  );

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

  bool _effectivePermission({
    required AppSession session,
    required TeamProfile? team,
  }) {
    final overrides = session.continueOverrides;
    if (session.isSimple) {
      return resolveContinueSkipPermissions(
        sessionLevel: overrides.dangerouslySkipPermissions,
        memberLevel: null,
        launchDefault: false,
      );
    }
    final member = _selectedMember(team);
    final memberId = _effectiveMemberId(team);
    final memberOverride = overrides.memberOverrides[memberId];
    return resolveContinueSkipPermissions(
      sessionLevel: overrides.dangerouslySkipPermissions,
      memberLevel: memberOverride?.dangerouslySkipPermissions,
      launchDefault: member?.dangerouslySkipPermissions ?? true,
    );
  }

  String? _selectedPresetId({
    required AppSession session,
    required TeamProfile? team,
  }) {
    if (session.isSimple) {
      final id = session.presetId.trim();
      return id.isEmpty ? null : id;
    }
    final memberId = _effectiveMemberId(team);
    final fromOverride = session
        .continueOverrides
        .memberOverrides[memberId]
        ?.presetId
        ?.trim();
    if (fromOverride != null && fromOverride.isNotEmpty) return fromOverride;
    final member = _selectedMember(team);
    if (member == null) return null;
    if (member.inheritsTeamPreset) {
      final teamPreset = team?.activePresetId?.trim() ?? '';
      return teamPreset.isEmpty ? null : teamPreset;
    }
    if (member.hasExplicitPreset) {
      final id = member.activePresetId?.trim() ?? '';
      return id.isEmpty ? null : id;
    }
    return null;
  }

  String? _identityLabel({
    required AppSession session,
    required TeamProfile? team,
    required ExpertHubState? hubState,
    required String expertFallback,
  }) {
    if (!session.isSimple) {
      final name = team?.name.trim() ?? '';
      return name.isEmpty ? null : name;
    }
    final key = session.expertKey.trim();
    if (key.isEmpty) return null;
    return ExpertMemberResolver.labelForKey(
      key: key,
      fallbackLabel: expertFallback,
      hubState: hubState,
    );
  }

  ExpertHubState? _expertHubState(BuildContext context) {
    try {
      return context.watch<ExpertHubCubit>().state;
    } on ProviderNotFoundException {
      return null;
    }
  }

  Workspace? _workspaceForSettings(BuildContext context) {
    final id = widget.session.workspaceId;
    return context
        .read<ChatCubit>()
        .state
        .workspaces
        .where((w) => w.workspaceId == id)
        .firstOrNull;
  }

  Future<void> _openTeamSettings(TeamProfile team) async {
    final workspace = _workspaceForSettings(context);
    if (workspace == null) return;
    await showLandingTeamSettingsDialog(
      context,
      workspace: workspace,
      team: team,
    );
  }

  void _toastContinueSaveFailed() {
    AppToast.show(
      context,
      message: context.l10n.sessionHistoryContinueSaveFailed,
      variant: TpToastVariant.warning,
    );
  }

  Future<void> _onPermissionSelected({
    required bool value,
    required TeamProfile? team,
  }) async {
    final session = _readCubitSession(context);
    if (session == null) {
      if (mounted) _toastContinueSaveFailed();
      return;
    }
    final memberId = session.isSimple ? null : _effectiveMemberId(team);
    if (!session.isSimple && (memberId == null || memberId.isEmpty)) return;
    try {
      final ok = await context.read<ChatCubit>().setSessionContinuePermission(
        sessionId: session.sessionId,
        dangerouslySkipPermissions: value,
        memberId: memberId,
      );
      if (!ok && mounted) _toastContinueSaveFailed();
    } on Object {
      if (mounted) _toastContinueSaveFailed();
    }
  }

  Future<void> _onPresetSelected({
    required String presetId,
    required TeamProfile? team,
    required List<CliPreset> sameCliPresets,
    required CliTool lockedCli,
  }) async {
    final session = _readCubitSession(context);
    if (session == null) {
      if (mounted) _toastContinueSaveFailed();
      return;
    }
    final preset = sameCliPresets.where((p) => p.id == presetId).firstOrNull;
    if (preset == null) return;
    final memberId = session.isSimple ? null : _effectiveMemberId(team);
    if (!session.isSimple && (memberId == null || memberId.isEmpty)) return;
    try {
      final ok = await context.read<ChatCubit>().setSessionContinuePreset(
        sessionId: session.sessionId,
        preset: preset,
        memberId: memberId,
        lockedCli: lockedCli,
      );
      if (!ok && mounted) _toastContinueSaveFailed();
    } on Object {
      if (mounted) _toastContinueSaveFailed();
    }
  }

  Future<void> _openContinueCustomLaunchDialog({
    required AppSession session,
  }) async {
    final result = await showSimpleCustomLaunchDialog(
      context,
      lockCli: true,
      initialCli: session.cli ?? CliTool.claude,
      initialProvider: session.provider,
      initialModel: session.model,
      initialEffort: session.effort,
    );
    if (!mounted || result == null) return;
    final live = _readCubitSession(context);
    if (live == null) {
      if (mounted) _toastContinueSaveFailed();
      return;
    }
    try {
      final ok = await context.read<ChatCubit>().setSessionContinueCustom(
        sessionId: live.sessionId,
        provider: result.provider,
        model: result.model,
        effort: result.effort,
      );
      if (!ok && mounted) _toastContinueSaveFailed();
    } on Object {
      if (mounted) _toastContinueSaveFailed();
    }
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

  void _insertComposeReferences(List<String> references) {
    insertComposeReferences(_controller, references);
    if (!mounted) return;
    setState(() {});
    _focusNode.requestFocus();
  }

  ComposeFileDropIngestor _composeDropIngestor() => ComposeFileDropIngestor(
    workspaceRoot: _workspaceRoot,
    onInsertReferences: _insertComposeReferences,
  );

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

  Future<void> _toggleVoice() async {
    if (_isSubmitting || _enhancing) return;

    final available = await _voiceInput.initialize();
    if (!mounted) return;
    if (!available) {
      AppToast.show(
        context,
        message: _voiceInput.permissionDenied
            ? context.l10n.workspaceChatLandingVoicePermissionDenied
            : context.l10n.workspaceChatLandingVoiceUnavailable,
        variant: TpToastVariant.warning,
      );
      return;
    }

    final started = await _voiceInput.toggleListening(
      preferredLocale: Localizations.localeOf(context),
    );
    if (!mounted) return;
    if (!started && !_voiceInput.isSessionActive) return;
    if (started || _voiceInput.isSessionActive) {
      _focusNode.requestFocus();
    }
  }

  Future<void> _cancelVoice() async {
    if (!_voiceListening && !_voiceInput.isSessionActive) return;
    _discardVoiceTranscript = true;
    await _voiceInput.endSession(discard: true);
  }

  Future<void> _stopVoice() async {
    if (!_voiceListening && !_voiceInput.isSessionActive) return;
    _discardVoiceTranscript = false;
    await _voiceInput.endSession(discard: false);
  }

  Future<void> _handleComposeStop(ChatCubit chat) async {
    await chat.interruptSelectedMemberTurn(
      sessionId: widget.session.sessionId,
      memberId: _shellMemberId,
    );
    chat.pauseFollowUpQueue(widget.session.sessionId, _shellMemberId);
    // Clear History "运行中…" immediately — do not wait for PTY idleAfter.
    final seat = _seat;
    if (seat != null && seat.state.awaitingAssistant) {
      seat.flushHeldTip(endAwaiting: true);
    }
    _cancelAwaitingIdleGrace();
    _userStoppedTurn = true;
    if (mounted) setState(() {});
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    final text = _controller.text.trim();
    final selectedMemberId = widget.selectedMemberId;
    final chat = context.read<ChatCubit>();
    final permissionWaiting = AgentPermissionAttentionBanner.isSelectedSeatWaiting(
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
      trimmedText: text,
      supportsTurnInterrupt: supportsTurnInterrupt,
    );

    var delivered = false;
    dispatchHistoryComposeSubmit(
      action: action,
      text: text,
      onEnqueue: (queued) {
        chat.followUpQueue.enqueue(_followUpSeatKey, queued);
        _controller.clear();
        _notifyFollowUpMemberWorking(chat);
        if (mounted) setState(() {});
      },
      onDeliver: (_) => delivered = true,
    );
    if (!delivered) return;

    await _deliverComposeMessage(text);
  }

  Future<void> _deliverComposeMessage(String text) async {
    if (text.isEmpty) return;
    final selectedMemberId = widget.selectedMemberId;
    if (AgentPermissionAttentionBanner.isSelectedSeatWaiting(
      attention: context.read<AgentAttentionCubit>(),
      session: widget.session,
      selectedMemberId: selectedMemberId,
    )) {
      return;
    }

    final seat = _seat;
    if (seat == null) return;
    // Peek before connect so mailbox continues skip optimistic thread pending.
    // onSubmit re-resolves after connect; rollback if peek was wrong.
    final peek =
        widget.peekContinueChannel?.call() ?? HistoryContinueChannel.pty;
    final optimisticPty = peek == HistoryContinueChannel.pty;
    if (optimisticPty) {
      seat.enqueuePendingUser(text);
      _userStoppedTurn = false;
      _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
    }
    _controller.clear();
    if (mounted) setState(() {});

    final result = await _submitLock.run(() async {
      if (mounted) setState(() {});
      return widget.onSubmit(text);
    });
    if (!mounted) return;
    setState(() {});
    if (!result.ok) {
      _cancelAwaitingIdleGrace();
      if (optimisticPty) seat.removePendingMatching(text);
      _controller
        ..text = text
        ..selection = TextSelection.collapsed(offset: text.length);
      setState(() {});
      return;
    }

    if (result.isMailbox) {
      _cancelAwaitingIdleGrace();
      if (optimisticPty) seat.removePendingMatching(text);
      final mailId = result.mailId!;
      _mailboxQueuedSeats[mailId] = _mailboxSeatKey();
      _mailboxQueued.add(PendingUserMessage(id: mailId, content: text));
      setState(() {});
      // Mailbox text is not in the CLI transcript — skip live refresh churn.
      return;
    }

    if (!optimisticPty) {
      // Peek said mailbox but post-connect path was PTY — show the bubble now.
      seat.enqueuePendingUser(text);
      _userStoppedTurn = false;
      _syncAwaitingFromWorkingSessions(context.read<ChatCubit>().state);
    }
    unawaited(_startLiveRefresh());
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
  /// phase — never from the global `sessionConnectingId`/'pending' sentinel.
  static bool _podConnecting(ChatCubit cubit, String sessionId) =>
      cubit.podFor(sessionId)?.phase.isLaunching ?? false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final cs = Theme.of(context).colorScheme;
    final skills = context.watch<SkillCubit>().state.installed;
    final plugins = context.watch<PluginCubit>().state.installed;
    final presets = context.watch<CliPresetsCubit>().state.presets;
    final session = _watchDisplaySession(context);
    final team = _watchLiveTeam(context);
    final hubState = _expertHubState(context);
    final selectedMemberId = widget.selectedMemberId;
    final permissionWaiting = context.select<AgentAttentionCubit, bool>(
      (c) => AgentPermissionAttentionBanner.isSelectedSeatWaiting(
        attention: c,
        session: session,
        selectedMemberId: selectedMemberId,
      ),
    );
    if (permissionWaiting && _focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNode.hasFocus) _focusNode.unfocus();
      });
    }
    final canSubmit =
        !permissionWaiting &&
        _controller.text.trim().isNotEmpty &&
        !_isSubmitting;

    final lockedCli = _lockedCli(
      session: session,
      team: team,
      presets: presets,
    );
    final askCardVisible = context.select<AgentAttentionCubit, bool>(
      (c) => AgentPermissionAttentionBanner.isSelectedSeatAskCard(
        attention: c,
        session: session,
        selectedMemberId: selectedMemberId,
        seatCli: lockedCli,
        registry: CliToolRegistryScope.maybeOf(context),
      ),
    );
    final sameCliPresets = presetsForCli(presets, lockedCli);
    final selectedPresetId = _selectedPresetId(session: session, team: team);
    final selectedPreset = selectedPresetId == null
        ? null
        : sameCliPresets.where((p) => p.id == selectedPresetId).firstOrNull;
    final modelLabel = session.isSimple
        ? simpleLaunchChipLabel(
            presetName: selectedPreset?.name,
            cli: lockedCli,
            provider: session.provider,
            model: session.model,
            emptyLabel: l10n.workspaceChatLandingUsePreset,
          )
        : (selectedPreset?.name.trim().isNotEmpty == true
              ? selectedPreset!.name.trim()
              : l10n.workspaceChatLandingUsePreset);
    final identityLabel = _identityLabel(
      session: session,
      team: team,
      hubState: hubState,
      expertFallback: l10n.expertHubNoneSelected,
    );
    final workspace = _workspaceForSettings(context);
    final showTeamSettings = !session.isSimple && team != null;
    final teamSettingsAttention =
        showTeamSettings &&
        workspace != null &&
        landingTeamSettingsNeedsAttention(workspace: workspace, team: team);

    // Rebuild when session working or bus presence changes (seat-level stop).
    context.select<ChatCubit, (String?, Set<String>)>(
      (c) => (c.state.activeSessionId, c.state.workingSessionIds),
    );
    context.select<MemberPresenceCubit, Map<String, MemberPresence>>(
      (c) => c.state.presence,
    );
    final chat = context.read<ChatCubit>();
    final memberWorking = chat.isMemberWorking(
      widget.session.sessionId,
      _shellMemberId,
    );
    final composeTextEmpty = _controller.text.trim().isEmpty;
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    final supportsTurnInterrupt =
        registry
            .capability<TurnInterruptCapability>(lockedCli)
            ?.supportsTurnInterrupt ??
        false;
    final showComposeStop = shouldShowComposeStop(
      memberWorking: memberWorking,
      supportsTurnInterrupt: supportsTurnInterrupt,
      composeTextEmpty: composeTextEmpty,
    );
    final historyCap = registry.capability<AiHistoryCapability>(lockedCli);

    return MultiBlocListener(
      listeners: [
        BlocListener<ChatCubit, ChatState>(
          listenWhen: (previous, current) =>
              previous.workingSessionIds != current.workingSessionIds ||
              previous.sessionConnectingId != current.sessionConnectingId ||
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
        child: BlocSelector<LayoutCubit, LayoutState, (bool, bool)>(
          selector: (s) => (
            s.preferences.cotExpandReasoningOnOpen,
            s.preferences.cotExpandToolsOnOpen,
          ),
          builder: (context, cotExpand) {
            final (expandReasoning, expandTools) = cotExpand;
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
                  final lifecycle = context.read<ChatCubit>().lifecycle;
                  final workspaceFolderPaths = sessionMemberFolderPaths(
                    lifecycle: lifecycle,
                    launchContext: _launchContext,
                    memberId: widget.selectedMemberId,
                  );
                  final sessionWorkingDirectory = _workspaceRoot.isEmpty
                      ? null
                      : _workspaceRoot;
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
                          Expanded(
                            // Full-bleed scroll surface: margins beside the text
                            // column still receive wheel / drag. Message width is
                            // capped inside SessionHistoryThread.
                            child: AiToolFileActionsScope(
                              actions: AiToolFileActions(
                                onOpenFile: (target) async {
                                  final fs =
                                      await resolveSessionMemberFilesystem(
                                        lifecycle: lifecycle,
                                        launchContext: _launchContext,
                                        memberId: widget.selectedMemberId,
                                        toolsScope:
                                            WorkspaceToolsScope.maybeOf(
                                              context,
                                            ),
                                      );
                                  if (!context.mounted) return;
                                  final coordinator =
                                      AiToolFileOpenCoordinator(
                                        opener: context
                                            .read<WorkbenchEditorOpener>(),
                                        editor: context.read<EditorCubit>(),
                                      );
                                  final result = await coordinator.openToolFile(
                                    workspaceId: widget.session.workspaceId,
                                    target: target,
                                    sessionWorkingDirectory:
                                        sessionWorkingDirectory,
                                    workspaceFolderPaths:
                                        workspaceFolderPaths,
                                    fs: fs,
                                  );
                                  if (!context.mounted) return;
                                  if (result.isMissing) {
                                    AppToast.show(
                                      context,
                                      message: l10n.aiToolFileNotFound(
                                        target.path,
                                      ),
                                      variant: TpToastVariant.warning,
                                    );
                                  }
                                },
                                lineHighlighter: WorkspaceAiEditLineHighlighter(
                                  brightness: Theme.of(context).brightness,
                                ),
                              ),
                              child: AiToolSubagentActionsScope(
                                actions: AiToolSubagentActions(
                                  isSubagentTool: historyCap == null
                                      ? null
                                      : (name) => historyCap.subagentToolNames
                                          .contains(name.trim().toLowerCase()),
                                  onOpenSubagent: (id) async {
                                    final attachments =
                                        _seat?.subagentAttachments ?? const {};
                                    if (!attachments.containsKey(id)) {
                                      if (!context.mounted) return;
                                      AppToast.show(
                                        context,
                                        message:
                                            l10n.subagentPreviewUnavailable,
                                        variant: TpToastVariant.warning,
                                      );
                                      return;
                                    }
                                    _subagentPreview.push(id);
                                  },
                                ),
                                child: AiMessageStringsScope(
                                  strings: AiMessageStrings(
                                    usedTool: l10n.aiMessageUsedTool,
                                    cancelledTool: l10n.aiMessageCancelledTool,
                                    formatToolsUsed: l10n.aiMessageToolsUsed,
                                    reasoning: l10n.aiMessageReasoning,
                                    result: l10n.aiMessageToolResult,
                                    copy: l10n.copy,
                                    copied: l10n.aiMessageCopied,
                                    exportMarkdown:
                                        l10n.aiMessageExportMarkdown,
                                    messageIncomplete:
                                        l10n.aiMessageIncomplete,
                                    messageCancelled:
                                        l10n.aiMessageCancelled,
                                    scrollToBottom:
                                        l10n.aiMessageScrollToBottom,
                                    showMore: l10n.aiMessageShowMore,
                                    showLess: l10n.aiMessageShowLess,
                                    thinkingProcess:
                                        l10n.aiMessageThinkingProcess,
                                    formatThinkingProcessSteps: (count) => l10n
                                        .aiMessageThinkingProcessSteps(
                                          count as int,
                                        ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Builder(
                                        builder: (context) {
                                          final seat =
                                              context.select<
                                                ChatCubit,
                                                ({
                                                  bool sessionWorking,
                                                  bool sessionConnecting,
                                                  bool memberRunning,
                                                  int stateVersion,
                                                })
                                              >((c) {
                                                final sid =
                                                    widget.session.sessionId;
                                                return (
                                                  sessionWorking: c
                                                      .state
                                                      .workingSessionIds
                                                      .contains(sid),
                                                  sessionConnecting:
                                                      _podConnecting(c, sid),
                                                  memberRunning: c
                                                      .isMemberRunning(
                                                        sessionId: sid,
                                                        memberId:
                                                            _shellMemberId,
                                                      ),
                                                  // Connect completion bumps
                                                  // this so PTY-up rebuilds.
                                                  stateVersion:
                                                      c.state.stateVersion,
                                                );
                                              });
                                          final liveChrome =
                                              SessionHistoryLiveChromeX.resolve(
                                                turnInFlight:
                                                    historyTurnInFlight(
                                                      isSubmitting:
                                                          _isSubmitting,
                                                      awaitingAssistant:
                                                          state
                                                              .awaitingAssistant,
                                                      sessionWorking:
                                                          seat.sessionWorking,
                                                      userStoppedTurn:
                                                          _userStoppedTurn,
                                                    ),
                                                memberRunning:
                                                    seat.memberRunning,
                                                sessionWorking:
                                                    seat.sessionWorking,
                                                sessionConnecting:
                                                    seat.sessionConnecting,
                                              );
                                          return SessionHistoryReviewMessages(
                                            state: state,
                                            runtime: historySeat.runtime,
                                            onRetry: () =>
                                                _loadHistory(force: true),
                                            onLoadOlder: historySeat.loadOlder,
                                            liveChrome: liveChrome,
                                          );
                                        },
                                      ),
                                      if (top != null)
                                        Positioned.fill(
                                          child: Material(
                                            color: cs.surface,
                                            child: AiHistoryRenderScope(
                                              // History-review budget also
                                              // guards subagent messages: a
                                              // giant subagent turn collapses
                                              // instead of freezing the
                                              // preview open.
                                              child: SubagentPreviewScaffold(
                                                title: previewTitle,
                                                messages: top.messages,
                                                emptyLabel: l10n
                                                    .subagentPreviewEmpty,
                                                backTooltip:
                                                    l10n.subagentPreviewBack,
                                                onBack: _subagentPreview.pop,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (top == null)
                      Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: columnWidth,
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              spacing.md,
                              0,
                              spacing.md,
                              spacing.lg,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AgentPermissionAttentionBanner(
                                  session: widget.session,
                                  selectedMemberId: widget.selectedMemberId,
                                ),
                                StreamBuilder<FollowUpQueue>(
                                  stream: chat.followUpQueue.watch(_followUpSeatKey),
                                  initialData: chat.followUpQueue.queueFor(
                                    _followUpSeatKey,
                                  ),
                                  builder: (context, snapshot) {
                                    final queue =
                                        snapshot.data ?? const FollowUpQueue();
                                    return FollowUpQueueStrip(
                                      queue: queue,
                                      onDelete: (id) => chat.followUpQueue.remove(
                                        _followUpSeatKey,
                                        id,
                                      ),
                                      onEdit: (id, content) =>
                                          chat.followUpQueue.edit(
                                            _followUpSeatKey,
                                            id,
                                            content,
                                          ),
                                      onMoveUp: (id) => chat.followUpQueue.moveUp(
                                        _followUpSeatKey,
                                        id,
                                      ),
                                      onResume: () => unawaited(
                                        chat.resumeFollowUpQueue(
                                          widget.session.sessionId,
                                          _shellMemberId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (widget.isMailboxUnread != null)
                                  HistoryMailboxQueuedStrip(
                                    key: ValueKey(
                                      'mailbox-queued-$_mailboxQueuedClearToken',
                                    ),
                                    submissions: _mailboxQueued.stream,
                                    isUnread: widget.isMailboxUnread!,
                                    clearToken: _mailboxQueuedClearToken,
                                    onConsumed: (msg) {
                                      if (!mounted) return;
                                      final seatKey = _mailboxQueuedSeats
                                          .remove(msg.id);
                                      if (seatKey != _mailboxSeatKey()) {
                                        return;
                                      }
                                      // Mail is read in the bus log now —
                                      // refresh the merged timeline so the
                                      // message appears as real history.
                                      unawaited(
                                        _seat?.refreshMailboxTimeline(),
                                      );
                                    },
                                  ),
                                if (!askCardVisible)
                                WorkspaceComposeCard(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  hint: memberWorking
                                      ? l10n.sessionFollowUpAddPlaceholder
                                      : l10n.sessionHistoryComposeHint,
                                  canSubmit: canSubmit,
                                  isSubmitting: _isSubmitting,
                                  onSubmit: () => unawaited(_handleSubmit()),
                                  onChanged: (_) => setState(() {}),
                                  chrome: BoundComposeChrome(
                                    composeEnabled: !permissionWaiting,
                                    launchError: widget.launchError,
                                    onRemapDeadTarget: widget.onRemapDeadTarget,
                                    onRetry: widget.onRetry,
                                    sessionConnectInProgress:
                                        widget.sessionConnectInProgress,
                                    floating: true,
                                    identityLabel: identityLabel,
                                    identityIcon: session.isSimple
                                        ? Icons.psychology_outlined
                                        : Icons.groups_outlined,
                                    sameCliPresets: sameCliPresets,
                                    selectedPresetId: selectedPresetId,
                                    modelPresetLabel: modelLabel,
                                    emptyPresetHintLabel:
                                        l10n.workspaceCliPresetsEmptyHint,
                                    onPresetSelected: (presetId) => unawaited(
                                      _onPresetSelected(
                                        presetId: presetId,
                                        team: team,
                                        sameCliPresets: sameCliPresets,
                                        lockedCli: lockedCli,
                                      ),
                                    ),
                                    customLabel: session.isSimple
                                        ? l10n.workspaceChatLandingCustomLaunch
                                        : null,
                                    customSelected:
                                        session.isSimple &&
                                        session.presetId.trim().isEmpty,
                                    onCustom: session.isSimple
                                        ? () => unawaited(
                                            _openContinueCustomLaunchDialog(
                                              session: session,
                                            ),
                                          )
                                        : null,
                                    dangerouslySkipPermissions:
                                        _effectivePermission(
                                          session: session,
                                          team: team,
                                        ),
                                    defaultPermissionsLabel: l10n
                                        .workspaceChatLandingDefaultPermissions,
                                    fullAccessPermissionsLabel: l10n
                                        .workspaceChatLandingFullAccessPermissions,
                                    onPermissionSelected: (value) =>
                                        unawaited(
                                          _onPermissionSelected(
                                            value: value,
                                            team: team,
                                          ),
                                        ),
                                    teamSettingsTooltip: showTeamSettings
                                        ? l10n.teamSettings
                                        : null,
                                    onTeamSettings: showTeamSettings
                                        ? () => unawaited(
                                            _openTeamSettings(team),
                                          )
                                        : null,
                                    showTeamSettingsAttention:
                                        teamSettingsAttention,
                                    showStop: showComposeStop,
                                    onStop: showComposeStop
                                        ? () => unawaited(
                                            _handleComposeStop(chat),
                                          )
                                        : null,
                                  ),
                                  dropTarget: _composeDropIngestor(),
                                  deferFieldMount: false,
                                  attachTooltip:
                                      l10n.workspaceChatLandingAttach,
                                  enhanceTooltip:
                                      l10n.workspaceChatLandingEnhance,
                                  voiceTooltip:
                                      l10n.workspaceChatLandingVoice,
                                  voiceCancelTooltip:
                                      l10n.workspaceChatLandingVoiceCancel,
                                  voiceStopTooltip:
                                      l10n.workspaceChatLandingVoiceStop,
                                  isEnhancing: _enhancing,
                                  isVoiceListening: _voiceListening,
                                  voiceElapsed: _voiceElapsed,
                                  voiceSoundLevel: _voiceSoundLevel,
                                  onAttach: () => unawaited(_attachFiles()),
                                  onEnhance: () => unawaited(_enhancePrompt()),
                                  onVoice: () => unawaited(_toggleVoice()),
                                  onVoiceCancel: () =>
                                      unawaited(_cancelVoice()),
                                  onVoiceStop: () => unawaited(_stopVoice()),
                                  onPasteImage: _pasteComposeImage,
                                  workspaceRoot: _workspaceRoot,
                                  skills: skills,
                                  plugins: plugins,
                                  slashBundle: _slashBundle(context),
                                  onOpenAtFile: (path) {
                                    unawaited(
                                      context
                                          .read<WorkbenchEditorOpener>()
                                          .openFile(
                                            widget.session.workspaceId,
                                            path,
                                            preview: true,
                                            fs: filesystemForComposeAtFileOpen(
                                              path,
                                            ),
                                          ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
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
    );
  }
}
