import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../widgets/app_toast/app_toast.dart';

import '../../../cubits/app_provider_cubit.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/expert_hub_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/plugin_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/skill_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../models/config_bundle.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/launch_security_policy.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_preset.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/runtime_target.dart';
import '../../../models/git_worktree.dart';
import '../../../services/compose/compose_at_file_refs.dart';
import '../../../services/compose/compose_clip.dart';
import '../../../services/compose/compose_draft_cache.dart';
import '../../../services/compose/compose_file_attach.dart';
import '../../../services/compose/compose_file_drop_ingestor.dart';
import '../../../services/compose/compose_landing_bundle.dart';
import '../../../services/compose/compose_text_edit.dart';
import '../../../services/compose/compose_voice_input.dart';
import '../../../services/storage/app_storage.dart';
import '../../../services/expert_hub/expert_capability_resolver.dart';
import '../../../services/expert_hub/expert_hub_recent_store.dart';
import '../../../services/expert_hub/expert_landing_preflight.dart';
import '../../../services/expert_hub/expert_member_resolver.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/cli/registry/capabilities/native_command_capability.dart';
import '../../../services/cli/registry/capabilities/skill_capability.dart';
import '../../../services/cli/preset_resolver.dart';
import '../../../utils/team/team_member_naming.dart';
import '../../../pages/home_workspace/home_workspace_route.dart';
import '../../../utils/workspace/landing_draft_resolver.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../../services/storage/home_target_controller.dart';
import '../../../services/team/team_landing_recent_store.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../../../widgets/compose/compose_chrome.dart';
import '../../../widgets/compose/compose_model_preset_chip.dart';
import '../../../widgets/compose/simple_custom_launch_dialog.dart';
import '../../../widgets/compose/workspace_compose_card.dart';
import '../../../services/launch/workspace_landing_launch_gate.dart';
import '../../../services/workbench/workbench_editor_opener.dart';
import '../../../repositories/workspace_project_config_repository.dart';
import '../../expert_hub/expert_landing_chip_menu.dart';
import '../../expert_hub/expert_landing_picker_sheet.dart';
import '../../expert_hub/expert_landing_preflight_feedback.dart';
import '../../team_hub/team_landing_chip_menu.dart';
import '../../team_hub/team_landing_picker_sheet.dart';
import 'config/cli_preset_edit_dialog.dart';
import 'config/cli_presets_manage_dialog.dart';
import 'workspace_landing_launch_feedback.dart';
import 'workspace_landing_selectors.dart';
import 'workspace_landing_team_settings_dialog.dart';
import 'remote_cli_machine_readiness_panel.dart';

enum _LandingConversationMode { team, simple }

typedef LandingComposeSubmit =
    void Function(String message, LandingLaunchContext draft);

/// Unbound compose host: draft / enhance / voice / attach / drop / submit.
///
/// No Landing page chrome (back button, full-bleed shell). Optionally shows
/// the project/worktree [WorkspaceLandingHeaderRow] when [showLocationHeader]
/// is true (Landing page); Ask AI leaves it false.
class UnboundComposeBody extends StatefulWidget {
  const UnboundComposeBody({
    required this.workspace,
    required this.onSubmit,
    this.isSubmitting = false,
    this.disabled = false,
    this.initialText,
    this.initialTextRevision = 0,
    this.referencedSessionId,
    this.deferFieldMount = false,
    this.showLocationHeader = false,
    super.key,
  });

  final Workspace workspace;
  final LandingComposeSubmit onSubmit;
  final bool isSubmitting;
  final bool disabled;
  final String? initialText;
  final int initialTextRevision;
  final String? referencedSessionId;
  final bool deferFieldMount;

  /// When true, renders [WorkspaceLandingHeaderRow] above the compose card
  /// (Landing page). Ask AI keeps this false.
  final bool showLocationHeader;

  @override
  State<UnboundComposeBody> createState() => _UnboundComposeBodyState();
}

class _UnboundComposeBodyState extends State<UnboundComposeBody> {
  final _controller = TextEditingController();
  final _clip = ComposeClip();
  late final FocusNode _focusNode;
  late final ComposeVoiceInput _voiceInput;
  var _suppressDraftSync = false;

  var _conversationMode = _LandingConversationMode.simple;
  var _generateLaunch = false;
  var _launchSecurityPolicy = LaunchSecurityPolicy.fullAccess;
  String? _selectedPresetId;
  CliTool? _selectedCli;
  String? _selectedProvider;
  String? _selectedModel;
  String? _selectedEffort;
  String? _selectedTeamId;
  String? _selectedExpertKey;
  var _voiceListening = false;
  var _voiceSoundLevel = 0.0;
  var _discardVoiceTranscript = false;
  TextEditingValue? _voiceInsertBaseline;
  Stopwatch? _voiceStopwatch;
  Timer? _voiceTimer;
  String? _selectedProjectPath;
  String? _selectedWorktreePath;
  List<RuntimeTarget> _runtimeTargets = const [];
  Future<void>? _runtimeTargetsLoad;
  final _launchGate = WorkspaceLandingLaunchGate();
  var _teamConfigLaunchReady = true;
  WorkspaceLandingLaunchBlock? _launchWarningBlock;
  int _teamLaunchReadinessGeneration = 0;
  ConfigBundle _workspaceProjectBundle = const ConfigBundle();
  int _workspaceBundleGeneration = 0;
  String? _lastRouteExpert;
  final _expertRecentStore = ExpertHubRecentStore();
  List<String> _recentExpertKeys = const [];
  final _teamRecentStore = TeamLandingRecentStore();
  List<String> _recentTeamIds = const [];
  CascadeCatalogListenable? _cascadeCatalog;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
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
    // Speech init is deferred to first mic tap (_toggleVoice) so workspace
    // open does not block on speech_to_text platform channels.
    final seed = widget.initialText;
    if (seed != null && seed.isNotEmpty) {
      _setComposeText(seed);
    } else if (widget.initialText == null) {
      // Restore the cached landing draft so navigating away and back does not
      // lose typed text. Ask AI (initialText != null) never reads the cache.
      final draft = composeDraftCache.landingDraft(
        widget.workspace.workspaceId,
      );
      if (draft != null && draft.isNotEmpty) {
        _setComposeText(draft);
      }
    }
    _controller.addListener(_syncComposeDraft);
    if (widget.initialText == null) {
      unawaited(_hydrateComposeDraft());
    }
    unawaited(_loadDraft());
    unawaited(_loadWorkspaceProjectBundle());
    unawaited(_loadRecentExperts());
    unawaited(_loadRecentTeams());
  }

  /// Keeps [composeDraftCache] in sync with the compose field on every change
  /// (typing, voice insert, enhance). No setState — the field's own onChanged
  /// rebuilds; this fires for programmatic edits too.
  void _syncComposeDraft() {
    if (_suppressDraftSync) return;
    unawaited(
      composeDraftCache.saveLanding(
        widget.workspace.workspaceId,
        _controller.text,
      ),
    );
  }

  Future<void> _hydrateComposeDraft() async {
    final draft = await composeDraftCache.hydrateLanding(
      widget.workspace.workspaceId,
      shouldSeed: () => mounted && _controller.text.isEmpty,
    );
    if (!mounted ||
        _controller.text.isNotEmpty ||
        draft == null ||
        draft.isEmpty) {
      return;
    }
    _setComposeText(draft);
  }

  void _setComposeText(String text) {
    _suppressDraftSync = true;
    try {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } finally {
      _suppressDraftSync = false;
    }
  }

  Future<void> _loadRecentExperts() async {
    final keys = await _expertRecentStore.loadOrderedKeys();
    if (!mounted) return;
    setState(() => _recentExpertKeys = keys);
  }

  Future<void> _loadRecentTeams() async {
    final ids = await _teamRecentStore.loadOrderedKeys();
    if (!mounted) return;
    setState(() => _recentTeamIds = ids);
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cascadeCatalog ??= CascadeCatalogListenable(
      registry:
          CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn(),
    );
    _runtimeTargetsLoad ??= _loadRuntimeTargets();
    _reloadDraftIfRouteExpertChanged();
  }

  void _reloadDraftIfRouteExpertChanged() {
    // GoRouterState.of walks up to the enclosing GoRoute page and throws when
    // there is none: widget tests mount landing under a plain MaterialApp, and
    // Selection → Ask AI mounts it inside a showDialog route.
    final location = GoRouter.maybeOf(context)?.state.uri.toString();
    if (location == null) return;
    final routeExpert = HomeWorkspaceRoute.expert(location);
    if (routeExpert == _lastRouteExpert) return;
    _lastRouteExpert = routeExpert;
    if (routeExpert == null) return;
    unawaited(_loadDraft());
  }

  @override
  void didUpdateWidget(covariant UnboundComposeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.workspaceId != widget.workspace.workspaceId) {
      unawaited(_loadWorkspaceProjectBundle());
    }
    final nextInitialText = widget.initialText;
    final prefillChanged =
        oldWidget.initialText != nextInitialText ||
        oldWidget.initialTextRevision != widget.initialTextRevision ||
        oldWidget.referencedSessionId != widget.referencedSessionId;
    if (prefillChanged) {
      if (nextInitialText != null && nextInitialText.isNotEmpty) {
        _setComposeText(nextInitialText);
      } else if (oldWidget.referencedSessionId != null &&
          _controller.text == oldWidget.initialText) {
        _setComposeText('');
      }
    }
    if (!mapEquals(
          oldWidget.workspace.memberTargetsByTeam,
          widget.workspace.memberTargetsByTeam,
        ) ||
        oldWidget.workspace.updatedAt != widget.workspace.updatedAt) {
      _scheduleTeamLaunchReadinessCheck();
    }
  }

  /// Latest workspace manifest (member machine pins) from [ChatCubit].
  Workspace _workspaceForLaunch() {
    final id = widget.workspace.workspaceId;
    return context.read<ChatCubit>().state.workspaces.firstWhere(
      (w) => w.workspaceId == id,
      orElse: () => widget.workspace,
    );
  }

  Future<void> _loadRuntimeTargets() async {
    try {
      final targets = await context
          .read<HomeTargetController>()
          .listSelectable();
      if (!mounted) return;
      setState(() => _runtimeTargets = targets);
      _scheduleTeamLaunchReadinessCheck();
    } on Object {
      // HomeTargetController unavailable outside the app shell.
    }
  }

  RuntimeTarget _homeTargetForLaunch() {
    try {
      return context.read<HomeTargetController>().current;
    } on Object {
      return RuntimeTarget.local();
    }
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

  Duration get _voiceElapsed => _voiceStopwatch?.elapsed ?? Duration.zero;

  @override
  void dispose() {
    _stopVoiceSessionClock();
    _cascadeCatalog?.dispose();
    _voiceInput.dispose();
    _controller.removeListener(_syncComposeDraft);
    _clip.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _attachFiles() async {
    if (widget.isSubmitting) return;
    await pickAndInsertComposeFileReferences(
      controller: _controller,
      workspaceRoot: _activeLaunchDirectory(),
      filesystem: AppStorage.fs,
    );
    if (!mounted) return;
    setState(() {});
    _focusNode.requestFocus();
  }

  ComposeFileDropIngestor _composeDropIngestor() {
    return ComposeFileDropIngestor(
      workspaceRoot: _activeLaunchDirectory(),
      onInsertReferences: _insertComposeReferences,
    );
  }

  void _insertComposeReferences(List<String> references) {
    insertComposeReferences(_controller, references);
    if (!mounted) return;
    setState(() {});
    _focusNode.requestFocus();
  }

  Future<bool> _pasteComposeImage() async {
    if (widget.isSubmitting) return false;
    final pasted = await pasteComposeImageAttachment(
      controller: _controller,
      workspaceRoot: _activeLaunchDirectory(),
    );
    if (pasted && mounted) setState(() {});
    return pasted;
  }

  Future<void> _toggleVoice() async {
    if (widget.isSubmitting) return;

    final available = await _voiceInput.initialize();
    if (!mounted) return;
    if (!available) {
      AppToast.show(
        context,
        message: composeVoiceInitFailureMessage(context.l10n, _voiceInput),
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

  Future<void> _loadWorkspaceProjectBundle() async {
    final generation = ++_workspaceBundleGeneration;
    try {
      final config = await WorkspaceProjectConfigRepository().load(
        widget.workspace.workspaceId,
      );
      if (!mounted || generation != _workspaceBundleGeneration) return;
      setState(() => _workspaceProjectBundle = config.bundle);
    } on Object {
      if (!mounted || generation != _workspaceBundleGeneration) return;
      setState(() => _workspaceProjectBundle = const ConfigBundle());
    }
  }

  ConfigBundle _slashBundleForDraft(
    LandingLaunchContext draft,
    List<TeamProfile> teams,
    ExpertHubState? hubState,
  ) {
    TeamProfile? team;
    if (!draft.isPersonal) {
      final teamId = draft.teamId?.trim() ?? '';
      if (teamId.isNotEmpty) {
        team = teams.where((t) => t.id == teamId).firstOrNull;
      }
    }
    return slashBundleForLanding(
      draft: draft,
      team: team,
      workspace: _workspaceProjectBundle,
      hubState: hubState,
    );
  }

  /// CLI that will receive the composed prompt: the selected preset's CLI
  /// (simple) or the team lead's CLI (team).
  CliTool? _cliForDraft({
    required List<CliPreset> presets,
    required TeamProfile? selectedTeam,
  }) {
    CliTool? cli;
    if (_conversationMode == _LandingConversationMode.simple) {
      final preset = presets
          .where((p) => p.id == _selectedPresetId)
          .firstOrNull;
      cli = preset?.cli ?? _selectedCli;
    } else if (selectedTeam != null) {
      final lead = selectedTeam.members
          .where(TeamMemberNaming.isTeamLead)
          .firstOrNull;
      cli = lead == null
          ? selectedTeam.cli
          : memberLaunchCli(
              team: selectedTeam,
              member: lead,
              globalPresets: presets,
            );
    }
    return cli;
  }

  Future<void> _loadDraft() async {
    final draft = await resolveLandingDraft(
      workspaceId: widget.workspace.workspaceId,
      simpleModeDefaultFullAccess: context
          .read<SessionPreferencesCubit>()
          .state
          .preferences
          .simpleModeDefaultFullAccess,
    );
    if (!mounted) return;

    // Drop stale prefs keys so the chip cannot show "none selected" while
    // still holding a dead expertKey.
    var expertKey = draft.expertKey;
    final rawExpert = expertKey?.trim() ?? '';
    if (rawExpert.isNotEmpty) {
      ExpertHubCubit? hubCubit;
      try {
        hubCubit = context.read<ExpertHubCubit>();
      } on ProviderNotFoundException {
        hubCubit = null;
      }
      final resolved = await ExpertMemberResolver.resolveMember(
        key: rawExpert,
        hubState: hubCubit?.state,
        cubit: hubCubit,
      );
      if (!mounted) return;
      if (resolved == null) expertKey = null;
    }

    final cleaned = identical(expertKey, draft.expertKey)
        ? draft
        : draft.copyWith(expertKey: expertKey);
    final presets = context.read<CliPresetsCubit>().state.presets;
    final seeded = seedLandingDraftPresetDefault(cleaned, presets);
    setState(() => _applyDraft(seeded));
    if (!identical(cleaned, draft) || seeded.presetId != cleaned.presetId) {
      _persistDraft();
    }
    await _syncActiveProjectFromDraft();
    // Sync may return early after dispose; do not touch context/setState.
    if (!mounted) return;
    _scheduleTeamLaunchReadinessCheck();
  }

  Future<void> _syncActiveProjectFromDraft() async {
    final projectPath = _projectResolver().resolveSelectedProjectPath();
    if (projectPath.trim().isEmpty) return;
    try {
      final cubit = context.read<WorktreeCubit>();
      // WorktreeCubit is bound by WorkspaceToolsScopeSync once the tools plane
      // resolves (loading stays true until that first bind+load completes).
      if (cubit.state.loading) {
        await cubit.stream.firstWhere((s) => !s.loading);
        if (!mounted) return;
      }
      await cubit.selectProject(
        projectPath,
        preferWorktreePath: _selectedWorktreePath,
      );
      if (!mounted) return;
      final worktreePath = _worktreeResolver(
        cubit.state,
      ).resolveSelectedWorktreePath();
      setState(() => _selectedWorktreePath = worktreePath);
    } on ProviderNotFoundException {
      // Landing rendered outside the workspace split pane.
    }
  }

  void _scheduleTeamLaunchReadinessCheck() {
    if (!mounted) return;
    final generation = ++_teamLaunchReadinessGeneration;
    unawaited(_refreshLaunchReadiness(generation));
  }

  Future<void> _refreshLaunchReadiness(int generation) async {
    if (!mounted || generation != _teamLaunchReadinessGeneration) return;
    final workspace = _workspaceForLaunch();
    final draft = _currentDraft();
    final presets = context.read<CliPresetsCubit>().state.presets;
    final readiness = context.read<ChatCubit>().remoteCliReadiness;

    if (_conversationMode == _LandingConversationMode.simple) {
      WorkspaceLandingLaunchBlock? remoteBlock;
      if (readiness != null && _runtimeTargets.isNotEmpty) {
        final projectPath = _projectResolver().resolveSelectedProjectPath();
        remoteBlock = await _launchGate.asyncRemoteCliBlockForSimple(
          workspace: workspace,
          draft: draft,
          projectFolderPath: projectPath,
          globalPresets: presets,
          selectableTargets: _runtimeTargets,
          readiness: readiness,
          home: _homeTargetForLaunch(),
        );
      }
      if (!mounted || generation != _teamLaunchReadinessGeneration) return;
      setState(() {
        _teamConfigLaunchReady = remoteBlock == null;
        _launchWarningBlock = remoteBlock;
      });
      return;
    }

    final teams = context.read<LaunchProfileCubit>().state.teams;
    final team = _selectedTeamProfile(teams);
    if (team == null) {
      if (!mounted || generation != _teamLaunchReadinessGeneration) return;
      setState(() {
        _teamConfigLaunchReady = false;
        _launchWarningBlock = const TeamNotSelectedLaunchBlock();
      });
      return;
    }
    final sync = _launchGate.syncBlock(
      workspace: workspace,
      draft: draft,
      team: team,
    );
    if (sync != null) {
      if (!mounted || generation != _teamLaunchReadinessGeneration) return;
      setState(() {
        _teamConfigLaunchReady = false;
        _launchWarningBlock = sync;
      });
      return;
    }
    final configBlock = await _launchGate.asyncBlock(
      team: team,
      globalPresets: presets,
    );
    if (!mounted || generation != _teamLaunchReadinessGeneration) return;
    if (configBlock != null) {
      setState(() {
        _teamConfigLaunchReady = false;
        _launchWarningBlock = configBlock;
      });
      return;
    }

    final remoteBlock = readiness == null
        ? null
        : await _launchGate.asyncRemoteCliBlock(
            workspace: workspace,
            team: team,
            globalPresets: presets,
            selectableTargets: _runtimeTargets,
            readiness: readiness,
          );
    if (!mounted || generation != _teamLaunchReadinessGeneration) return;
    setState(() {
      _teamConfigLaunchReady = remoteBlock == null;
      _launchWarningBlock = remoteBlock;
    });
  }

  WorkspaceLandingLaunchBlock? _resolveLaunchWarningBlock(TeamProfile? team) {
    if (_launchWarningBlock is RemoteCliMissingLaunchBlock) {
      return _launchWarningBlock;
    }
    if (_conversationMode != _LandingConversationMode.team) return null;
    final sync = _launchGate.syncBlock(
      workspace: _workspaceForLaunch(),
      draft: _currentDraft(),
      team: team,
    );
    if (sync != null) return sync;
    if (_launchWarningBlock is TeamConfigIncompleteLaunchBlock) {
      return _launchWarningBlock;
    }
    return null;
  }

  void _applyDraft(LandingLaunchContext draft) {
    _conversationMode = draft.isPersonal
        ? _LandingConversationMode.simple
        : _LandingConversationMode.team;
    _generateLaunch = draft.generateLaunch;
    _selectedTeamId = draft.teamId;
    _selectedPresetId = draft.presetId;
    _selectedCli = draft.cli;
    _selectedProvider = draft.provider;
    _selectedModel = draft.model;
    _selectedEffort = draft.effort;
    _selectedExpertKey = draft.expertKey?.trim().isNotEmpty == true
        ? draft.expertKey!.trim()
        : null;
    _selectedProjectPath = draft.projectFolderPath?.trim().isNotEmpty == true
        ? draft.projectFolderPath!.trim()
        : null;
    _selectedWorktreePath =
        draft.workingDirectoryPath?.trim().isNotEmpty == true
        ? draft.workingDirectoryPath!.trim()
        : null;
    _launchSecurityPolicy = draft.launchSecurityPolicy;

    if ((_selectedTeamId == null || _selectedTeamId!.isEmpty) &&
        _conversationMode == _LandingConversationMode.team) {
      final teams = context.read<LaunchProfileCubit>().state.teams;
      if (teams.isNotEmpty) _selectedTeamId = teams.first.id;
    }

    if (draft.isPersonal) {
      _selectedPresetId ??= draft.presetId;
    }
  }

  WorktreeState? _worktreeState(BuildContext context) {
    try {
      final bits = context
          .select<WorktreeCubit, (String, List<GitWorktree>, String, bool)>(
            (c) => (
              c.state.repoPath,
              c.state.worktrees,
              c.state.currentWorktreePath,
              c.state.loading,
            ),
          );
      return WorktreeState(
        repoPath: bits.$1,
        worktrees: bits.$2,
        currentWorktreePath: bits.$3,
        loading: bits.$4,
      );
    } on ProviderNotFoundException {
      return null;
    }
  }

  WorkspaceLandingProjectResolver _projectResolver() {
    return WorkspaceLandingProjectResolver(
      workspace: widget.workspace,
      runtimeTargets: _runtimeTargets,
      storedProjectPath: _selectedProjectPath,
    );
  }

  WorkspaceLandingWorktreeResolver _worktreeResolver(
    WorktreeState? worktreeState,
  ) {
    final projectPath = _projectResolver().resolveSelectedProjectPath();
    WorktreeCubit? cubit;
    try {
      cubit = context.read<WorktreeCubit>();
    } on ProviderNotFoundException {
      cubit = null;
    }
    return WorkspaceLandingWorktreeResolver(
      projectPath: projectPath,
      worktreeState: worktreeState,
      storedWorktreePath: _selectedWorktreePath,
      cachedWorktrees: cubit?.worktreesForProject(projectPath) ?? const [],
    );
  }

  Future<void> _selectProject(Object? value) async {
    if (value is! String || value.trim().isEmpty) return;
    final path = normalizeWorkspacePath(value);
    setState(() {
      _selectedProjectPath = path;
      _selectedWorktreePath = null;
    });
    try {
      final cubit = context.read<WorktreeCubit>();
      await cubit.selectProject(
        path,
        preferWorktreePath: _selectedWorktreePath,
      );
      if (!mounted) return;
      final worktreePath = _worktreeResolver(
        cubit.state,
      ).resolveSelectedWorktreePath();
      setState(() => _selectedWorktreePath = worktreePath);
      cubit.setCurrentWorktree(worktreePath);
    } on ProviderNotFoundException {
      // Landing rendered outside the workspace split pane.
    }
    _persistDraft();
    _scheduleTeamLaunchReadinessCheck();
  }

  void _selectWorktree(Object? value) {
    if (value is! String || value.trim().isEmpty) return;
    final path = normalizeWorkspacePath(value);
    setState(() => _selectedWorktreePath = path);
    _persistDraft();
    try {
      context.read<WorktreeCubit>().setCurrentWorktree(path);
    } on ProviderNotFoundException {
      // Landing rendered outside the workspace split pane.
    }
  }

  void _syncLaunchFromWorktree(WorktreeState state) {
    final projectPath = _projectResolver().resolveSelectedProjectPath();
    if (!workspacePathsEqual(state.repoPath, projectPath)) return;
    final path = normalizeWorkspacePath(state.currentWorktreePath);
    if (path.isEmpty) return;
    final resolver = _worktreeResolver(state);
    if (!resolver.options.any((o) => workspacePathsEqual(o.path, path))) {
      return;
    }
    final stored = _selectedWorktreePath?.trim() ?? '';
    if (stored.isNotEmpty && workspacePathsEqual(stored, path)) return;
    setState(() => _selectedWorktreePath = path);
    _persistDraft();
  }

  String _activeLaunchDirectory() {
    WorktreeState? worktreeState;
    try {
      worktreeState = context.read<WorktreeCubit>().state;
    } on ProviderNotFoundException {
      worktreeState = null;
    }
    return _worktreeResolver(worktreeState).resolveSelectedWorktreePath();
  }

  LandingLaunchContext _currentDraft() {
    WorktreeState? worktreeState;
    try {
      worktreeState = context.read<WorktreeCubit>().state;
    } on ProviderNotFoundException {
      worktreeState = null;
    }
    final projectResolver = _projectResolver();
    final selectedProjectPath = projectResolver.resolveSelectedProjectPath();
    final worktreeResolver = _worktreeResolver(worktreeState);
    final selectedWorktreePath = worktreeResolver.resolveSelectedWorktreePath();
    final isSimple = _conversationMode == _LandingConversationMode.simple;
    return LandingLaunchContext(
      isPersonal: isSimple,
      generateLaunch: !isSimple && _generateLaunch,
      presetId: _selectedPresetId,
      teamId: _selectedTeamId,
      expertKey: isSimple ? _selectedExpertKey : null,
      projectFolderPath: selectedProjectPath.trim().isEmpty
          ? null
          : selectedProjectPath,
      workingDirectoryPath: selectedWorktreePath.trim().isEmpty
          ? null
          : selectedWorktreePath,
      launchSecurityPolicy: _launchSecurityPolicy,
      // Keep custom four-tuple across Simple↔Team switches (ignored on Team submit).
      cli: _selectedCli,
      provider: _selectedProvider,
      model: _selectedModel,
      effort: _selectedEffort,
    );
  }

  void _persistDraft() {
    unawaited(
      persistLandingDraft(widget.workspace.workspaceId, _currentDraft()),
    );
  }

  bool get _canSubmit {
    if (widget.disabled || widget.isSubmitting) return false;
    if (_launchWarningBlock is RemoteCliMissingLaunchBlock) return false;
    if (_conversationMode == _LandingConversationMode.team) {
      final teams = context.read<LaunchProfileCubit>().state.teams;
      final team = _selectedTeamProfile(teams);
      if (_launchGate.syncBlock(
            workspace: _workspaceForLaunch(),
            draft: _currentDraft(),
            team: team,
          ) !=
          null) {
        return false;
      }
      if (_launchWarningBlock is TeamConfigIncompleteLaunchBlock) {
        return false;
      }
    }
    return true;
  }

  void _submit() {
    unawaited(_submitAfterLaunchGate());
  }

  Future<void> _submitAfterLaunchGate() async {
    final text = _clip.composeMessage(_controller.text.trim());
    if (text.isEmpty || widget.disabled || widget.isSubmitting) return;

    if (_conversationMode == _LandingConversationMode.team) {
      final teams = context.read<LaunchProfileCubit>().state.teams;
      final team = _selectedTeamProfile(teams);
      final draft = _currentDraft();
      final workspace = _workspaceForLaunch();

      final sync = _launchGate.syncBlock(
        workspace: workspace,
        draft: draft,
        team: team,
      );
      if (!mounted) return;
      if (sync != null) {
        showWorkspaceLandingLaunchBlock(context, sync);
        _scheduleTeamLaunchReadinessCheck();
        return;
      }

      if (_launchWarningBlock is TeamConfigIncompleteLaunchBlock) {
        showWorkspaceLandingLaunchBlock(context, _launchWarningBlock!);
        _scheduleTeamLaunchReadinessCheck();
        return;
      }

      if (_launchWarningBlock is RemoteCliMissingLaunchBlock) {
        showWorkspaceLandingLaunchBlock(context, _launchWarningBlock!);
        _scheduleTeamLaunchReadinessCheck();
        return;
      }

      if (team != null) {
        final presets = context.read<CliPresetsCubit>().state.presets;
        final configBlock = await _launchGate.asyncBlock(
          team: team,
          globalPresets: presets,
        );
        if (!mounted) return;
        if (configBlock != null) {
          setState(() {
            _teamConfigLaunchReady = false;
            _launchWarningBlock = configBlock;
          });
          showWorkspaceLandingLaunchBlock(context, configBlock);
          return;
        }

        final readiness = context.read<ChatCubit>().remoteCliReadiness;
        if (readiness != null) {
          final remoteBlock = await _launchGate.asyncRemoteCliBlock(
            workspace: workspace,
            team: team,
            globalPresets: presets,
            selectableTargets: _runtimeTargets,
            readiness: readiness,
          );
          if (!mounted) return;
          if (remoteBlock != null) {
            setState(() {
              _teamConfigLaunchReady = false;
              _launchWarningBlock = remoteBlock;
            });
            showWorkspaceLandingLaunchBlock(context, remoteBlock);
            return;
          }
        }

        setState(() {
          _teamConfigLaunchReady = true;
          _launchWarningBlock = null;
        });
      }
    } else {
      final readiness = context.read<ChatCubit>().remoteCliReadiness;
      if (readiness != null && _runtimeTargets.isNotEmpty) {
        final presets = context.read<CliPresetsCubit>().state.presets;
        final projectPath = _projectResolver().resolveSelectedProjectPath();
        final remoteBlock = await _launchGate.asyncRemoteCliBlockForSimple(
          workspace: _workspaceForLaunch(),
          draft: _currentDraft(),
          projectFolderPath: projectPath,
          globalPresets: presets,
          selectableTargets: _runtimeTargets,
          readiness: readiness,
          home: _homeTargetForLaunch(),
        );
        if (!mounted) return;
        if (remoteBlock != null) {
          setState(() {
            _teamConfigLaunchReady = false;
            _launchWarningBlock = remoteBlock;
          });
          showWorkspaceLandingLaunchBlock(context, remoteBlock);
          return;
        }
      }
      setState(() {
        _teamConfigLaunchReady = true;
        _launchWarningBlock = null;
      });
    }

    widget.onSubmit(text, _currentDraft());
    _clip.clear();
  }

  void _setConversationMode(_LandingConversationMode mode) {
    if (_conversationMode == mode && !_generateLaunch) return;
    setState(() {
      _conversationMode = mode;
      // Selecting Simple or a concrete team clears generation mode without
      // discarding the last concrete team id.
      if (mode == _LandingConversationMode.simple) {
        _generateLaunch = false;
        _seedFirstPresetIfNeeded();
      }
    });
    _persistDraft();
    _scheduleTeamLaunchReadinessCheck();
  }

  /// Mirrors automation editor: default Simple landing to the first global preset.
  bool _seedFirstPresetIfNeeded() {
    if (_selectedPresetId?.trim().isNotEmpty == true) return false;
    if (_selectedCli != null) return false;
    final presets = context.read<CliPresetsCubit>().state.presets;
    final first = presets.firstOrNull;
    if (first == null) return false;
    _selectedPresetId = first.id;
    return true;
  }

  void _setLaunchSecurityPolicy(LaunchSecurityPolicy value) {
    if (_launchSecurityPolicy == value) return;
    setState(() => _launchSecurityPolicy = value);
    _persistDraft();
  }

  void _selectPreset(String presetId) {
    setState(
      () => _applyDraft(landingDraftSelectingPreset(_currentDraft(), presetId)),
    );
    _persistDraft();
    _scheduleTeamLaunchReadinessCheck();
  }

  Future<void> _applyCascadeLaunch(SimpleLaunchFourTuple tuple) async {
    setState(
      () => _applyDraft(
        landingDraftSelectingCustom(
          _currentDraft(),
          cli: tuple.cli,
          provider: tuple.providerId,
          model: tuple.modelId,
          effort: tuple.effort,
        ),
      ),
    );
    _persistDraft();
    _scheduleTeamLaunchReadinessCheck();
  }

  Future<void> _applyCustomModelId({
    required CascadeCustomModelRequest request,
  }) async {
    final modelId = await showComposeCustomModelIdDialog(
      context,
      title: context.l10n.composeCascadeCustomModelIdTitle,
      confirmLabel: context.l10n.confirm,
      initial: _selectedModel ?? '',
    );
    if (!mounted || modelId == null || modelId.isEmpty) return;
    await _applyCascadeLaunch(
      SimpleLaunchFourTuple(
        cli: request.cli,
        providerId: request.providerId,
        modelId: modelId,
        effort: _selectedEffort ?? '',
      ),
    );
  }

  void _openSaveAsPresetDialog() {
    final draft = CliPreset(
      id: '',
      name: '',
      cli: _selectedCli ?? CliTool.claude,
      provider: _selectedProvider ?? '',
      model: _selectedModel ?? '',
      effort: _selectedEffort ?? '',
      createdAt: 0,
      updatedAt: 0,
    );
    showDialog<void>(
      context: context,
      builder: (_) => CliPresetEditDialog(draft: draft),
    );
  }

  void _openPresetsManageDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const CliPresetsManageDialog(),
    );
  }

  void _selectTeam(String teamId) {
    setState(() => _selectedTeamId = teamId);
    _persistDraft();
    _scheduleTeamLaunchReadinessCheck();
  }

  Future<void> _touchRecentTeam(String teamId) async {
    await _teamRecentStore.touch(teamId);
    await _loadRecentTeams();
  }

  Future<void> _openTeamPicker() async {
    final id = await showTeamLandingPickerSheet(
      context,
      selectedTeamId: _selectedTeamId,
      touchRecent: _teamRecentStore.touch,
    );
    if (!mounted || id == null) return;
    _selectTeam(id);
    unawaited(_touchRecentTeam(id));
  }

  void _onTeamChipSelected(Object? value) {
    if (value == TeamLandingChipAction.generateLaunch) {
      setState(() {
        _conversationMode = _LandingConversationMode.team;
        _generateLaunch = true;
      });
      _persistDraft();
      return;
    }
    if (value == TeamLandingChipAction.browseAll) {
      unawaited(_openTeamPicker());
      return;
    }
    if (value is String && value.isNotEmpty) {
      setState(() => _generateLaunch = false);
      _selectTeam(value);
      unawaited(_touchRecentTeam(value));
    }
  }

  TeamProfile? _selectedTeamProfile(List<TeamProfile> teams) {
    final id = _selectedTeamId?.trim() ?? '';
    if (id.isEmpty) return null;
    return teams.where((team) => team.id == id).firstOrNull;
  }

  Future<void> _openTeamSettings(List<TeamProfile> teams) async {
    final team = _selectedTeamProfile(teams);
    if (team == null) return;
    final saved = await showLandingTeamSettingsDialog(
      context,
      workspace: _workspaceForLaunch(),
      team: team,
    );
    if (saved == true && mounted) {
      _scheduleTeamLaunchReadinessCheck();
    }
  }

  void _selectExpert(String? expertKey) {
    final trimmed = expertKey?.trim();
    setState(
      () => _selectedExpertKey = trimmed?.isNotEmpty == true ? trimmed : null,
    );
    _persistDraft();
  }

  Future<void> _selectExpertWithPreflight(String expertKey) async {
    final trimmed = expertKey.trim();
    if (trimmed.isEmpty) {
      _selectExpert(null);
      return;
    }

    ExpertCapabilityResolver? resolver;
    try {
      resolver = context.read<ExpertCapabilityResolver>();
    } on ProviderNotFoundException {
      return;
    }

    final result = await selectLandingExpert(
      resolver: resolver,
      expertKey: trimmed,
    );
    if (!mounted) return;

    if (result.cleared) {
      _selectExpert(null);
      if (result.preflight?.notFound == true) {
        AppToast.show(
          context,
          message: context.l10n.expertHubNotFound,
          variant: TpToastVariant.warning,
        );
      }
      return;
    }

    // Keep selection even when some deps fail (soft fail policy).
    _selectExpert(result.selectedKey);
    unawaited(_touchRecentExpert(trimmed));

    final pack = result.preflight?.pack;
    if (pack == null || !pack.hasFailures) return;
    final message = expertLandingPreflightToastMessage(
      context.l10n,
      expertName: pack.member.name,
      pack: pack,
    );
    if (message.isEmpty) return;
    AppToast.show(context, message: message, variant: TpToastVariant.warning);
  }

  Future<void> _touchRecentExpert(String expertKey) async {
    await _expertRecentStore.touch(expertKey);
    await _loadRecentExperts();
  }

  Future<void> _openExpertPicker() async {
    final key = await showExpertLandingPickerSheet(
      context,
      selectedKey: _selectedExpertKey,
    );
    if (!mounted || key == null) return;
    await _selectExpertWithPreflight(key);
  }

  void _onExpertChipSelected(Object? value) {
    if (value == ExpertLandingChipAction.clear) {
      _selectExpert(null);
      return;
    }
    if (value == ExpertLandingChipAction.browseAll) {
      unawaited(_openExpertPicker());
      return;
    }
    if (value is String && value.isNotEmpty) {
      unawaited(_selectExpertWithPreflight(value));
    }
  }

  ExpertHubState? _expertHubState(BuildContext context) {
    try {
      return context.select<ExpertHubCubit, ExpertHubState>(
        (c) => ExpertHubState(allMembers: c.state.allMembers),
      );
    } on ProviderNotFoundException {
      return null;
    }
  }

  String _expertChipLabel(AppLocalizations l10n, ExpertHubState? hubState) {
    return ExpertMemberResolver.labelForKey(
      key: _selectedExpertKey,
      fallbackLabel: l10n.expertHubNoneSelected,
      hubState: hubState,
    );
  }

  List<TpActionMenuSpec> _expertChipSpecs(
    AppLocalizations l10n,
    ExpertHubState? hubState,
  ) {
    final recent = <({String key, String name})>[];
    for (final key in _recentExpertKeys) {
      final member = ExpertMemberResolver.resolve(key: key, hubState: hubState);
      final name = member?.name.trim() ?? '';
      if (name.isEmpty) continue;
      recent.add((key: key, name: name));
      if (recent.length >= kExpertLandingChipRecentLimit) break;
    }
    return buildExpertLandingChipMenuSpecs(
      noneSelectedLabel: l10n.expertHubNoneSelected,
      browseAllLabel: l10n.expertHubBrowseAll,
      selectedExpertKey: _selectedExpertKey,
      recentExperts: recent,
    );
  }

  String _conversationModeLabel(AppLocalizations l10n) {
    return switch (_conversationMode) {
      _LandingConversationMode.team => l10n.workspaceChatLandingModeTeam,
      _LandingConversationMode.simple => l10n.workspaceChatLandingModeSimple,
    };
  }

  String _autoChipLabel(
    BuildContext context,
    AppLocalizations l10n, {
    required List<CliPreset> presets,
    required List<TeamProfile> teams,
  }) {
    if (_conversationMode == _LandingConversationMode.simple) {
      final preset = presets
          .where((p) => p.id == _selectedPresetId)
          .firstOrNull;
      return simpleLaunchChipLabel(
        presetName: preset?.name,
        cli: _selectedCli,
        provider: _selectedProvider,
        model: _selectedModel,
        emptyLabel: l10n.workspaceChatLandingUsePreset,
      );
    }

    final team = teams.where((t) => t.id == _selectedTeamId).firstOrNull;
    return team?.name.trim().isNotEmpty == true
        ? team!.name.trim()
        : l10n.selectTeam;
  }

  Widget? _autoChipLeading(
    BuildContext context, {
    required List<CliPreset> presets,
  }) {
    if (_conversationMode != _LandingConversationMode.simple) return null;
    final preset = presets.where((p) => p.id == _selectedPresetId).firstOrNull;
    final CliTool? cli =
        preset?.cli ??
        _selectedCli ??
        (_selectedPresetId?.trim().isNotEmpty == true
            ? null
            : presets.firstOrNull?.cli);
    if (cli == null) return null;
    final icons = context.tpIconSizes;
    return CliBrandIcon(
      cli: cli,
      size: icons.sm,
      borderRadius: 4,
      showBorder: false,
    );
  }

  List<TpActionMenuSpec> _conversationModeSpecs(AppLocalizations l10n) {
    return [
      TpActionMenuSpec.item(
        value: _LandingConversationMode.team,
        icon: Icons.groups_outlined,
        label: l10n.workspaceChatLandingModeTeam,
        selected: _conversationMode == _LandingConversationMode.team,
      ),
      TpActionMenuSpec.item(
        value: _LandingConversationMode.simple,
        icon: Icons.chat_bubble_outline,
        label: l10n.workspaceChatLandingModeSimple,
        selected: _conversationMode == _LandingConversationMode.simple,
      ),
    ];
  }

  List<TpActionMenuSpec> _autoChipSpecs(
    AppLocalizations l10n, {
    required List<CliPreset> presets,
    required List<TeamProfile> teams,
  }) {
    if (_conversationMode == _LandingConversationMode.simple) {
      final registry = CliToolRegistryScope.of(context);
      final providerCubit = context.read<AppProviderCubit>();
      final cliItems = registry.launchable
          .map((d) => d.id)
          .toList(growable: false);
      _cascadeCatalog?.attach(cliItems);
      final groups = resolveComposeCascadeCliGroups(
        registry: registry,
        providersByCli: {
          for (final cli in cliItems)
            cli: providerCubit.state.providersFor(cli).toList(growable: false),
        },
        cliItems: cliItems,
      );
      return buildComposeModelCascadeMenuSpecs(
        presets: presets,
        selectedPresetId: _selectedPresetId,
        emptyHintLabel: l10n.workspaceCliPresetsEmptyHint,
        emptyProvidersLabel: l10n.composeCascadeNoProviders,
        presetsLabel: l10n.composeCascadePresets,
        defaultEffortLabel: l10n.composeCascadeDefaultEffort,
        customModelIdLabel: l10n.composeCascadeCustomModelId,
        noModelsLabel: l10n.composeCascadeNoModels,
        savePresetLabel: l10n.composeCascadeSavePreset,
        managePresetsLabel: l10n.workspaceCliAddPresetTitle,
        cliGroups: groups,
        groupByCli: true,
        onModelsOpened: (cli, providerId, config) => unawaited(
          refreshComposeCascadeCatalog(
            context,
            cli: cli,
            providerId: providerId,
            provider: config,
          ),
        ),
      );
    }

    final recent = <({String id, String name})>[];
    for (final id in _recentTeamIds) {
      final team = teams.where((t) => t.id == id).firstOrNull;
      final name = team?.name.trim() ?? '';
      if (name.isEmpty) continue;
      recent.add((id: id, name: name));
      if (recent.length >= kTeamLandingChipRecentLimit) break;
    }
    return buildTeamLandingChipMenuSpecs(
      browseAllLabel: l10n.teamHubBrowseAll,
      generateLaunchLabel: l10n.teamGenerateLaunch,
      selectedTeamId: _generateLaunch ? null : _selectedTeamId,
      generateLaunchSelected: _generateLaunch,
      recentTeams: recent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final launchWorkspace = context.select<ChatCubit, Workspace>(
      (c) => c.state.workspaces.firstWhere(
        (w) => w.workspaceId == widget.workspace.workspaceId,
        orElse: () => widget.workspace,
      ),
    );
    final presets = context.select((CliPresetsCubit c) => c.state.presets);
    final identities = context.select(
      (LaunchProfileCubit c) => c.state.identities,
    );
    final teams = identities.whereType<TeamProfile>().toList(growable: false);
    final skills = context.select((SkillCubit c) => c.state.installed);
    final plugins = context.select((PluginCubit c) => c.state.installed);
    final hubState = _expertHubState(context);
    final slashBundle = _slashBundleForDraft(_currentDraft(), teams, hubState);
    final isSimple = _conversationMode == _LandingConversationMode.simple;
    final worktreeState = _worktreeState(context);
    final projectResolver = _projectResolver();
    final selectedProjectPath = projectResolver.resolveSelectedProjectPath();
    final projectLabel = projectResolver.labelFor(selectedProjectPath);
    final worktreeResolver = _worktreeResolver(worktreeState);
    final selectedWorktreePath = worktreeResolver.resolveSelectedWorktreePath();
    final worktreeLabel = worktreeResolver.labelFor(selectedWorktreePath);
    final selectedTeam = _conversationMode == _LandingConversationMode.team
        ? _selectedTeamProfile(teams)
        : null;
    final cli = _cliForDraft(presets: presets, selectedTeam: selectedTeam);
    final registry = CliToolRegistryScope.of(context);
    final skillSyntax = cli == null
        ? null
        : registry.capability<SkillCapability>(cli);
    final nativeCommands = cli == null
        ? const <NativeCommand>[]
        : registry.capability<NativeCommandCapability>(cli)?.commands ??
              const <NativeCommand>[];
    final launchWarningBlock = _resolveLaunchWarningBlock(selectedTeam);
    final remoteCliReadiness = context.read<ChatCubit>().remoteCliReadiness;
    final remoteCliMissing = launchWarningBlock is RemoteCliMissingLaunchBlock
        ? launchWarningBlock.missing
        : null;

    WorkspaceComposeCard buildCard(
      BuildContext context,
    ) => WorkspaceComposeCard(
      controller: _controller,
      clip: _clip,
      focusNode: _focusNode,
      hint: l10n.workspaceChatLandingInputHint,
      isSubmitting: widget.isSubmitting,
      canSubmit: _canSubmit,
      onSubmit: _submit,
      onChanged: (_) {},
      chrome: UnboundComposeChrome(
        conversationModeLabel: _conversationModeLabel(l10n),
        autoChipLabel: _autoChipLabel(
          context,
          l10n,
          presets: presets,
          teams: teams,
        ),
        autoChipLeading: _autoChipLeading(context, presets: presets),
        launchSecurityPolicy: _launchSecurityPolicy,
        defaultPermissionsLabel: l10n.workspaceChatLandingDefaultPermissions,
        fullAccessPermissionsLabel:
            l10n.workspaceChatLandingFullAccessPermissions,
        askReadOnlyPermissionsLabel:
            l10n.workspaceChatLandingAskReadOnlyPermissions,
        autoApproveWorkspaceWritePermissionsLabel:
            l10n.workspaceChatLandingAutoApproveWorkspaceWritePermissions,
        customPermissionsLabel: l10n.workspaceChatLandingCustomPermissions,
        conversationModeSpecs: _conversationModeSpecs(l10n),
        autoChipSpecs: _autoChipSpecs(l10n, presets: presets, teams: teams),
        onConversationModeSelected: (value) {
          if (value is _LandingConversationMode) {
            _setConversationMode(value);
          }
        },
        onAutoChipSelected: (value) async {
          if (value == ComposeModelPresetChipAction.manage) {
            _openPresetsManageDialog();
            return;
          }
          final tuple = decodeComposeCascadeValue(value);
          if (tuple != null) {
            await _applyCascadeLaunch(tuple);
            return;
          }
          if (value is CascadeCustomModelRequest) {
            await _applyCustomModelId(request: value);
            return;
          }
          if (value == ComposeModelPresetChipAction.savePreset) {
            _openSaveAsPresetDialog();
            return;
          }
          if (_conversationMode == _LandingConversationMode.team) {
            _onTeamChipSelected(value);
            return;
          }
          if (value is! String || value.isEmpty) return;
          _selectPreset(value);
        },
        onPermissionSelected: _setLaunchSecurityPolicy,
        expertChipLabel: isSimple ? _expertChipLabel(l10n, hubState) : null,
        expertChipSpecs: isSimple ? _expertChipSpecs(l10n, hubState) : const [],
        onExpertChipSelected: isSimple ? _onExpertChipSelected : null,
        teamSettingsTooltip: selectedTeam != null ? l10n.teamSettings : null,
        onTeamSettings: selectedTeam != null
            ? () => unawaited(_openTeamSettings(teams))
            : null,
        showTeamSettingsAttention:
            selectedTeam != null &&
            landingTeamSettingsNeedsAttention(
              workspace: launchWorkspace,
              team: selectedTeam,
            ),
      ),
      dropTarget: _composeDropIngestor(),
      attachTooltip: l10n.workspaceChatLandingAttach,
      voiceTooltip: l10n.workspaceChatLandingVoice,
      voiceCancelTooltip: l10n.workspaceChatLandingVoiceCancel,
      voiceStopTooltip: l10n.workspaceChatLandingVoiceStop,
      isVoiceListening: _voiceListening,
      voiceElapsed: _voiceElapsed,
      voiceSoundLevel: _voiceSoundLevel,
      onAttach: () => unawaited(_attachFiles()),
      onVoice: () => unawaited(_toggleVoice()),
      onVoiceCancel: () => unawaited(_cancelVoice()),
      onVoiceStop: () => unawaited(_stopVoice()),
      onPasteImage: _pasteComposeImage,
      workspaceRoot: _activeLaunchDirectory(),
      skills: skills,
      plugins: plugins,
      slashBundle: slashBundle,
      skillSyntax: skillSyntax,
      nativeCommands: nativeCommands,
      onOpenAtFile: (path) {
        unawaited(
          context.read<WorkbenchEditorOpener>().openFile(
            widget.workspace.workspaceId,
            path,
            preview: true,
            fs: filesystemForComposeAtFileOpen(path),
          ),
        );
      },
      deferFieldMount: widget.deferFieldMount,
      submitBlockedTooltip:
          launchWarningBlock != null && _controller.text.trim().isNotEmpty
          ? landingLaunchBlockMessage(
              l10n,
              launchWarningBlock,
              registry: registry,
            )
          : null,
    );

    final cascadeCatalog = _cascadeCatalog;
    final composeCard =
        _conversationMode == _LandingConversationMode.simple &&
            cascadeCatalog != null
        ? ListenableBuilder(
            listenable: cascadeCatalog,
            builder: (context, _) => buildCard(context),
          )
        : buildCard(context);

    Widget composeSection = composeCard;
    if (remoteCliMissing != null &&
        remoteCliMissing.isNotEmpty &&
        remoteCliReadiness != null) {
      composeSection = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          composeCard,
          RemoteCliMachineReadinessPanel(
            fixedRequirements: remoteCliMissing,
            selectableTargets: _runtimeTargets,
            readiness: remoteCliReadiness,
            onReadinessChanged: _scheduleTeamLaunchReadinessCheck,
          ),
        ],
      );
    }

    final body = widget.showLocationHeader
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WorkspaceLandingHeaderRow(
                projectLabel: projectLabel,
                projectHintWhenEmpty: l10n.workspaceChatLandingSelectProject,
                projectMenuSpecs: projectResolver.menuSpecs(
                  selectedProjectPath,
                ),
                onProjectSelected: (value) => unawaited(_selectProject(value)),
                showWorktreeSelector: worktreeResolver.showsWorktreeSelector,
                worktreeLabel: worktreeLabel,
                worktreeHintWhenEmpty: l10n.workspaceChatLandingSelectWorktree,
                worktreeMenuSpecs: worktreeResolver.menuSpecs(
                  selectedWorktreePath,
                ),
                onWorktreeSelected: _selectWorktree,
              ),
              SizedBox(height: spacing.sm),
              composeSection,
            ],
          )
        : composeSection;

    return BlocListener<LaunchProfileCubit, LaunchProfileState>(
      listenWhen: (previous, current) {
        final id = _selectedTeamId?.trim() ?? '';
        if (id.isEmpty) return false;
        TeamProfile? teamIn(List<TeamProfile> teams) =>
            teams.where((t) => t.id == id).firstOrNull;
        return teamIn(previous.teams) != teamIn(current.teams);
      },
      listener: (context, state) => _scheduleTeamLaunchReadinessCheck(),
      child: BlocListener<WorktreeCubit, WorktreeState>(
        listenWhen: (previous, current) =>
            previous.currentWorktreePath != current.currentWorktreePath,
        listener: (context, state) => _syncLaunchFromWorktree(state),
        child: body,
      ),
    );
  }
}
