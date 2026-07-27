import 'dart:async';

import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/ai_history_cubit.dart';
import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/config_bundle.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/ai/headless_ai_service.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/compose/compose_file_attach.dart';
import '../../services/compose/compose_landing_bundle.dart';
import '../../services/compose/compose_prompt_enhance.dart';
import '../../services/compose/compose_text_edit.dart';
import '../../services/compose/compose_voice_input.dart';
import '../../services/expert_hub/expert_member_resolver.dart';
import '../../services/session/ai_history_live_refresh_controller.dart';
import '../../services/session/history_seat_key.dart';
import '../../services/session/session_continue_overrides_apply.dart';
import '../../services/session/session_history_pagination.dart';
import '../../services/storage/app_storage.dart';
import '../../services/terminal/pending_user_message.dart';
import '../../theme/app_markdown_style_sheet.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';
import '../home_workspace/workspace/workspace_landing_team_settings_dialog.dart';
import 'agent_permission_attention_banner.dart';
import 'history_awaiting_working_sync.dart';
import 'history_continue_delivery.dart';
import 'history_mailbox_queued_strip.dart';
import 'session_history_live_chrome.dart';
import 'session_history_review_messages.dart';
import 'session_history_review_submit.dart';
import 'session_review_compose_card.dart';

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

  /// Latched once this continue turn appears in [ChatState.workingSessionIds]
  /// (or was already working at submit); falling edge clears awaiting.
  var _sawSessionWorkingWhileAwaiting = false;
  Timer? _awaitingIdleGraceTimer;

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
      _bindSeat();
      // Defer: load → runtime.setLoading sync-notifies seat listeners
      // while ancestors (e.g. TpDeferredForegroundMount) are still building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _seat?.clearPendings();
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
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onComposeChanged() {
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

  LandingLaunchContext _enhanceDraft() {
    final isPersonal = widget.session.sessionTeam.trim().isEmpty;
    return LandingLaunchContext(
      isPersonal: isPersonal,
      teamId: isPersonal ? null : widget.session.sessionTeam,
      expertKey: widget.session.expertKey.trim().isEmpty
          ? null
          : widget.session.expertKey,
      workingDirectoryPath: _workspaceRoot,
    );
  }

  ConfigBundle _slashBundle(BuildContext context) {
    return slashBundleForLanding(
      draft: _enhanceDraft(),
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

  /// Display-only fallback when the cubit snapshot is not loaded yet.
  AppSession _displaySession(BuildContext context) =>
      _watchCubitSession(context) ?? widget.session;

  TeamProfile? _liveTeam(BuildContext context) {
    final session = _displaySession(context);
    if (session.isSimple) return null;
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) return null;
    final profile = context.watch<LaunchProfileCubit>().byId(teamId);
    if (profile is TeamProfile) return profile;
    return widget.team;
  }

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

    final setting = resolveLandingEnhanceSetting(
      draft: _enhanceDraft(),
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

  Future<void> _handleSubmit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSubmitting) return;
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
      final working = context
          .read<ChatCubit>()
          .state
          .workingSessionIds
          .contains(widget.session.sessionId);
      if (working) {
        _sawSessionWorkingWhileAwaiting = true;
        return;
      }
      seat.flushHeldTip(endAwaiting: true);
      _sawSessionWorkingWhileAwaiting = false;
    });
  }

  void _syncAwaitingFromWorkingSessions(ChatState chat) {
    final seat = _seat;
    if (seat == null) return;
    final working = chat.workingSessionIds.contains(widget.session.sessionId);
    final action = resolveHistoryAwaitingWorkingAction(
      awaitingAssistant: seat.state.awaitingAssistant,
      sessionWorking: working,
      sawWorkingWhileAwaiting: _sawSessionWorkingWhileAwaiting,
    );
    switch (action) {
      case HistoryAwaitingWorkingAction.none:
        return;
      case HistoryAwaitingWorkingAction.resetLatch:
        _sawSessionWorkingWhileAwaiting = false;
        _cancelAwaitingIdleGrace();
        return;
      case HistoryAwaitingWorkingAction.latchWorking:
        _sawSessionWorkingWhileAwaiting = true;
        _cancelAwaitingIdleGrace();
        return;
      case HistoryAwaitingWorkingAction.clearAwaiting:
        seat.flushHeldTip(endAwaiting: true);
        _sawSessionWorkingWhileAwaiting = false;
        _cancelAwaitingIdleGrace();
        return;
      case HistoryAwaitingWorkingAction.scheduleGraceClear:
        _scheduleAwaitingIdleGrace();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final cs = Theme.of(context).colorScheme;
    final skills = context.watch<SkillCubit>().state.installed;
    final plugins = context.watch<PluginCubit>().state.installed;
    final presets = context.watch<CliPresetsCubit>().state.presets;
    final session = _displaySession(context);
    final team = _liveTeam(context);
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
    final sameCliPresets = presetsForCli(presets, lockedCli);
    final selectedPresetId = _selectedPresetId(session: session, team: team);
    final selectedPreset = selectedPresetId == null
        ? null
        : sameCliPresets.where((p) => p.id == selectedPresetId).firstOrNull;
    final modelLabel = selectedPreset?.name.trim().isNotEmpty == true
        ? selectedPreset!.name.trim()
        : l10n.workspaceChatLandingUsePreset;
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

    return BlocListener<ChatCubit, ChatState>(
      listenWhen: (previous, current) =>
          previous.workingSessionIds != current.workingSessionIds,
      listener: (context, state) {
        _syncAwaitingFromWorkingSessions(state);
        _maybeStartLiveRefreshForRunningPty();
      },
      child: ColoredBox(
        color: cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // Full-bleed scroll surface: margins beside the text column still
              // receive wheel / drag. Message width is capped inside SessionHistoryThread.
              child: BlocSelector<LayoutCubit, LayoutState, (bool, bool)>(
                selector: (s) => (
                  s.preferences.cotExpandReasoningOnOpen,
                  s.preferences.cotExpandToolsOnOpen,
                ),
                builder: (context, cotExpand) {
                  final (expandReasoning, expandTools) = cotExpand;
                  return Theme(
                    data: Theme.of(context).copyWith(
                      extensions: [
                        for (final ext in Theme.of(context).extensions.values)
                          if (ext is! AiMessageTheme) ext,
                        AiMessageTheme.of(context).copyWith(
                          markdown: buildAppCompiledMarkdownStyle(
                            Theme.of(context),
                            mutedSurface: cs.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            ),
                          ),
                          userBubbleColor: cs.surfaceContainerHighest,
                          userBubbleForeground: cs.onSurface,
                          mutedSurface: cs.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
                          toolTriggerColor: cs.onSurfaceVariant,
                          messageSpacing: 24,
                          threadMaxWidth: kSessionHistoryColumnMaxWidth,
                          threadHorizontalPadding: spacing.md,
                          cotExpandReasoningOnOpen: expandReasoning,
                          cotExpandToolsOnOpen: expandTools,
                        ),
                      ],
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
                        exportMarkdown: l10n.aiMessageExportMarkdown,
                        messageIncomplete: l10n.aiMessageIncomplete,
                        messageCancelled: l10n.aiMessageCancelled,
                        scrollToBottom: l10n.aiMessageScrollToBottom,
                        showMore: l10n.aiMessageShowMore,
                        showLess: l10n.aiMessageShowLess,
                        thinkingProcess: l10n.aiMessageThinkingProcess,
                        formatThinkingProcessSteps: (count) =>
                            l10n.aiMessageThinkingProcessSteps(count as int),
                      ),
                      child: BlocBuilder<AiHistorySeat, AiHistoryState>(
                        bloc: _seat,
                        builder: (context, state) {
                          final historySeat = _seat;
                          if (historySeat == null) {
                            return const SizedBox.shrink();
                          }
                          final seat = context
                              .select<
                                ChatCubit,
                                ({
                                  bool sessionWorking,
                                  bool sessionConnecting,
                                  bool memberRunning,
                                  int stateVersion,
                                })
                              >((c) {
                                final sid = widget.session.sessionId;
                                final connectingId =
                                    c.state.sessionConnectingId;
                                return (
                                  sessionWorking: c.state.workingSessionIds
                                      .contains(sid),
                                  sessionConnecting:
                                      connectingId == sid ||
                                      connectingId == 'pending',
                                  memberRunning: c.isMemberRunning(
                                    sessionId: sid,
                                    memberId: _shellMemberId,
                                  ),
                                  // Connect completion bumps this so PTY-up rebuilds.
                                  stateVersion: c.state.stateVersion,
                                );
                              });
                          final liveChrome = SessionHistoryLiveChromeX.resolve(
                            turnInFlight:
                                _isSubmitting ||
                                state.awaitingAssistant ||
                                seat.sessionWorking,
                            memberRunning: seat.memberRunning,
                            sessionWorking: seat.sessionWorking,
                            sessionConnecting: seat.sessionConnecting,
                          );
                          return SessionHistoryReviewMessages(
                            state: state,
                            runtime: historySeat.runtime,
                            onRetry: () => _loadHistory(force: true),
                            onLoadOlder: historySeat.loadOlder,
                            liveChrome: liveChrome,
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kSessionHistoryColumnMaxWidth,
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
                            final seatKey = _mailboxQueuedSeats.remove(msg.id);
                            if (seatKey != _mailboxSeatKey()) return;
                            // Mail is read in the bus log now — refresh the
                            // merged timeline so the message appears as real
                            // history.
                            unawaited(_seat?.refreshMailboxTimeline());
                          },
                        ),
                      SessionReviewComposeCard(
                        floating: true,
                        controller: _controller,
                        focusNode: _focusNode,
                        hint: l10n.sessionHistoryComposeHint,
                        canSubmit: canSubmit,
                        isSubmitting: _isSubmitting,
                        composeEnabled: !permissionWaiting,
                        onSubmit: () => unawaited(_handleSubmit()),
                        onChanged: (_) => setState(() {}),
                        attachTooltip: l10n.workspaceChatLandingAttach,
                        enhanceTooltip: l10n.workspaceChatLandingEnhance,
                        voiceTooltip: l10n.workspaceChatLandingVoice,
                        voiceCancelTooltip:
                            l10n.workspaceChatLandingVoiceCancel,
                        voiceStopTooltip: l10n.workspaceChatLandingVoiceStop,
                        isEnhancing: _enhancing,
                        isVoiceListening: _voiceListening,
                        voiceElapsed: _voiceElapsed,
                        voiceSoundLevel: _voiceSoundLevel,
                        onAttach: () => unawaited(_attachFiles()),
                        onEnhance: () => unawaited(_enhancePrompt()),
                        onVoice: () => unawaited(_toggleVoice()),
                        onVoiceCancel: () => unawaited(_cancelVoice()),
                        onVoiceStop: () => unawaited(_stopVoice()),
                        workspaceRoot: _workspaceRoot,
                        skills: skills,
                        plugins: plugins,
                        slashBundle: _slashBundle(context),
                        launchError: widget.launchError,
                        onRemapDeadTarget: widget.onRemapDeadTarget,
                        onPasteImage: _pasteComposeImage,
                        identityLabel: identityLabel,
                        identityIcon: session.isSimple
                            ? Icons.psychology_outlined
                            : Icons.groups_outlined,
                        sameCliPresets: sameCliPresets,
                        selectedPresetId: selectedPresetId,
                        modelPresetLabel: modelLabel,
                        emptyPresetHintLabel: l10n.workspaceCliPresetsEmptyHint,
                        onPresetSelected: (presetId) => unawaited(
                          _onPresetSelected(
                            presetId: presetId,
                            team: team,
                            sameCliPresets: sameCliPresets,
                            lockedCli: lockedCli,
                          ),
                        ),
                        dangerouslySkipPermissions: _effectivePermission(
                          session: session,
                          team: team,
                        ),
                        defaultPermissionsLabel:
                            l10n.workspaceChatLandingDefaultPermissions,
                        fullAccessPermissionsLabel:
                            l10n.workspaceChatLandingFullAccessPermissions,
                        onPermissionSelected: (value) => unawaited(
                          _onPermissionSelected(value: value, team: team),
                        ),
                        teamSettingsTooltip: showTeamSettings
                            ? l10n.teamSettings
                            : null,
                        onTeamSettings: showTeamSettings
                            ? () => unawaited(_openTeamSettings(team))
                            : null,
                        showTeamSettingsAttention: teamSettingsAttention,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
