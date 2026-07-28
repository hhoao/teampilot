import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

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
import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_preset.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/runtime_target.dart';
import '../../../services/ai/headless_ai_service.dart';
import '../../../services/compose/compose_file_attach.dart';
import '../../../services/compose/compose_file_drop_ingestor.dart';
import '../../../services/storage/app_storage.dart';
import '../../../services/compose/compose_landing_bundle.dart';
import '../../../services/compose/compose_prompt_enhance.dart';
import '../../../services/compose/compose_text_edit.dart';
import '../../../services/compose/compose_voice_input.dart';
import '../../../services/expert_hub/expert_capability_resolver.dart';
import '../../../services/expert_hub/expert_hub_recent_store.dart';
import '../../../services/expert_hub/expert_landing_preflight.dart';
import '../../../services/expert_hub/expert_member_resolver.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../pages/home_workspace/home_workspace_route.dart';
import '../../../utils/workspace/landing_draft_resolver.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../../services/storage/home_target_controller.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../../../widgets/compose/compose_chrome.dart';
import '../../../widgets/compose/compose_model_preset_chip.dart';
import '../../../widgets/compose/workspace_compose_card.dart';
import '../../../services/launch/workspace_landing_launch_gate.dart';
import '../../../repositories/workspace_project_config_repository.dart';
import '../../expert_hub/expert_landing_chip_menu.dart';
import '../../expert_hub/expert_landing_picker_sheet.dart';
import '../../expert_hub/expert_landing_preflight_feedback.dart';
import 'config/cli_presets_manage_dialog.dart';
import 'workspace_landing_launch_feedback.dart';
import 'workspace_landing_selectors.dart';
import 'workspace_landing_team_settings_dialog.dart';

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
    this.deferFieldMount = false,
    this.showLocationHeader = false,
    super.key,
  });

  final Workspace workspace;
  final LandingComposeSubmit onSubmit;
  final bool isSubmitting;
  final bool disabled;
  final String? initialText;
  final bool deferFieldMount;

  /// When true, renders [WorkspaceLandingHeaderRow] above the compose card
  /// (Landing page). Ask AI keeps this false.
  final bool showLocationHeader;

  @override
  State<UnboundComposeBody> createState() => _UnboundComposeBodyState();
}

class _UnboundComposeBodyState extends State<UnboundComposeBody> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  late final ComposeVoiceInput _voiceInput;
  final _headlessAi = HeadlessAiService();

  var _conversationMode = _LandingConversationMode.simple;
  var _dangerouslySkipPermissions = true;
  String? _selectedPresetId;
  String? _selectedTeamId;
  String? _selectedExpertKey;
  var _enhancing = false;
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
      _controller.value = TextEditingValue(
        text: seed,
        selection: TextSelection.collapsed(offset: seed.length),
      );
    }
    unawaited(_loadDraft());
    unawaited(_loadWorkspaceProjectBundle());
    unawaited(_loadRecentExperts());
  }

  Future<void> _loadRecentExperts() async {
    final keys = await _expertRecentStore.loadOrderedKeys();
    if (!mounted) return;
    setState(() => _recentExpertKeys = keys);
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
    } on Object {
      // HomeTargetController unavailable outside the app shell.
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
    _voiceInput.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _attachFiles() async {
    if (widget.isSubmitting || _enhancing) return;
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
    if (widget.isSubmitting || _enhancing) return false;
    final pasted = await pasteComposeImageAttachment(
      controller: _controller,
      workspaceRoot: _activeLaunchDirectory(),
    );
    if (pasted && mounted) setState(() {});
    return pasted;
  }

  Future<void> _enhancePrompt() async {
    final draft = _controller.text.trim();
    if (draft.isEmpty || widget.isSubmitting || _enhancing) return;

    final setting = resolveLandingEnhanceSetting(
      draft: _currentDraft(),
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
        workingDirectory: _optionalLaunchDirectory(),
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
    if (widget.isSubmitting || _enhancing) return;

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
    setState(() => _applyDraft(draft));
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
    if (_conversationMode != _LandingConversationMode.team) {
      if (_teamConfigLaunchReady && _launchWarningBlock == null) return;
      setState(() {
        _teamConfigLaunchReady = true;
        _launchWarningBlock = null;
      });
      return;
    }
    final generation = ++_teamLaunchReadinessGeneration;
    unawaited(_refreshTeamLaunchReadiness(generation));
  }

  Future<void> _refreshTeamLaunchReadiness(int generation) async {
    if (!mounted || generation != _teamLaunchReadinessGeneration) return;
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
      workspace: _workspaceForLaunch(),
      draft: _currentDraft(),
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
    final presets = context.read<CliPresetsCubit>().state.presets;
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

    final readiness = context.read<ChatCubit>().remoteCliReadiness;
    final remoteBlock = readiness == null
        ? null
        : await _launchGate.asyncRemoteCliBlock(
            workspace: _workspaceForLaunch(),
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
    if (_launchWarningBlock is RemoteCliMissingLaunchBlock) {
      return _launchWarningBlock;
    }
    return null;
  }

  void _applyDraft(LandingLaunchContext draft) {
    _conversationMode = draft.isPersonal
        ? _LandingConversationMode.simple
        : _LandingConversationMode.team;
    _selectedTeamId = draft.teamId;
    _selectedPresetId = draft.presetId;
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
    _dangerouslySkipPermissions = draft.dangerouslySkipPermissions;

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
      return context.watch<WorktreeCubit>().state;
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

  String? _optionalLaunchDirectory() {
    final path = _activeLaunchDirectory().trim();
    return path.isEmpty ? null : path;
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
      presetId: _selectedPresetId,
      teamId: _selectedTeamId,
      expertKey: isSimple ? _selectedExpertKey : null,
      projectFolderPath: selectedProjectPath.trim().isEmpty
          ? null
          : selectedProjectPath,
      workingDirectoryPath: selectedWorktreePath.trim().isEmpty
          ? null
          : selectedWorktreePath,
      dangerouslySkipPermissions: _dangerouslySkipPermissions,
    );
  }

  void _persistDraft() {
    unawaited(
      persistLandingDraft(widget.workspace.workspaceId, _currentDraft()),
    );
  }

  bool get _canSubmit {
    if (widget.disabled || widget.isSubmitting) return false;
    if (_controller.text.trim().isEmpty) return false;
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
      if (_launchWarningBlock is RemoteCliMissingLaunchBlock) {
        return false;
      }
    }
    return true;
  }

  void _submit() {
    unawaited(_submitAfterLaunchGate());
  }

  Future<void> _submitAfterLaunchGate() async {
    final text = _controller.text.trim();
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
    }

    widget.onSubmit(text, _currentDraft());
  }

  void _setConversationMode(_LandingConversationMode mode) {
    if (_conversationMode == mode) return;
    setState(() => _conversationMode = mode);
    _persistDraft();
    _scheduleTeamLaunchReadinessCheck();
  }

  void _setDangerouslySkipPermissions(bool value) {
    if (_dangerouslySkipPermissions == value) return;
    setState(() => _dangerouslySkipPermissions = value);
    _persistDraft();
  }

  void _selectPreset(String presetId) {
    setState(() => _selectedPresetId = presetId);
    _persistDraft();
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

    // Keep selection even when some deps fail (soft fail policy).
    _selectExpert(trimmed);
    unawaited(_touchRecentExpert(trimmed));

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

    final preflight = result.preflight;
    if (preflight == null) return;

    final l10n = context.l10n;
    if (preflight.notFound) {
      AppToast.show(
        context,
        message: l10n.expertHubNotFound,
        variant: TpToastVariant.warning,
      );
      return;
    }

    final pack = preflight.pack;
    if (pack == null || !pack.hasFailures) return;
    final message = expertLandingPreflightToastMessage(
      l10n,
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
      return context.watch<ExpertHubCubit>().state;
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
    AppLocalizations l10n, {
    required List<CliPreset> presets,
    required List<TeamProfile> teams,
  }) {
    if (_conversationMode == _LandingConversationMode.simple) {
      final preset = presets
          .where((p) => p.id == _selectedPresetId)
          .firstOrNull;
      return preset?.name.trim().isNotEmpty == true
          ? preset!.name.trim()
          : l10n.workspaceChatLandingUsePreset;
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
    final preset =
        presets.where((p) => p.id == _selectedPresetId).firstOrNull ??
        presets.firstOrNull;
    if (preset == null) return null;
    final icons = context.tpIconSizes;
    return CliBrandIcon(
      cli: preset.cli,
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
      return buildComposeModelPresetMenuSpecs(
        sameCliPresets: presets,
        selectedPresetId: _selectedPresetId,
        emptyHintLabel: l10n.workspaceCliPresetsEmptyHint,
        managePresetsLabel: l10n.workspaceCliAddPresetTitle,
      );
    }

    if (teams.isEmpty) {
      return [
        TpActionMenuSpec.item(
          value: null,
          icon: Icons.groups_outlined,
          label: l10n.selectTeam,
          enabled: false,
        ),
      ];
    }
    return [
      for (final team in teams)
        TpActionMenuSpec.item(
          value: team.id,
          icon: Icons.groups_outlined,
          label: team.name,
          selected: team.id == _selectedTeamId,
        ),
    ];
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
    final presets = context.watch<CliPresetsCubit>().state.presets;
    final teams = context.watch<LaunchProfileCubit>().state.teams;
    final skills = context.watch<SkillCubit>().state.installed;
    final plugins = context.watch<PluginCubit>().state.installed;
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
    final launchWarningBlock = _resolveLaunchWarningBlock(selectedTeam);

    final composeCard = WorkspaceComposeCard(
      controller: _controller,
      focusNode: _focusNode,
      hint: l10n.workspaceChatLandingInputHint,
      isSubmitting: widget.isSubmitting,
      canSubmit: _canSubmit,
      onSubmit: _submit,
      onChanged: (_) => setState(() {}),
      chrome: UnboundComposeChrome(
        conversationModeLabel: _conversationModeLabel(l10n),
        autoChipLabel: _autoChipLabel(
          l10n,
          presets: presets,
          teams: teams,
        ),
        autoChipLeading: _autoChipLeading(
          context,
          presets: presets,
        ),
        dangerouslySkipPermissions: _dangerouslySkipPermissions,
        defaultPermissionsLabel: l10n.workspaceChatLandingDefaultPermissions,
        fullAccessPermissionsLabel:
            l10n.workspaceChatLandingFullAccessPermissions,
        conversationModeSpecs: _conversationModeSpecs(l10n),
        autoChipSpecs: _autoChipSpecs(
          l10n,
          presets: presets,
          teams: teams,
        ),
        onConversationModeSelected: (value) {
          if (value is _LandingConversationMode) {
            _setConversationMode(value);
          }
        },
        onAutoChipSelected: (value) {
          if (value == ComposeModelPresetChipAction.manage) {
            _openPresetsManageDialog();
            return;
          }
          if (value is! String || value.isEmpty) return;
          if (_conversationMode == _LandingConversationMode.simple) {
            _selectPreset(value);
          } else {
            _selectTeam(value);
          }
        },
        onPermissionSelected: _setDangerouslySkipPermissions,
        expertChipLabel: isSimple ? _expertChipLabel(l10n, hubState) : null,
        expertChipSpecs: isSimple
            ? _expertChipSpecs(l10n, hubState)
            : const [],
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
      enhanceTooltip: l10n.workspaceChatLandingEnhance,
      voiceTooltip: l10n.workspaceChatLandingVoice,
      voiceCancelTooltip: l10n.workspaceChatLandingVoiceCancel,
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
      onPasteImage: _pasteComposeImage,
      workspaceRoot: _activeLaunchDirectory(),
      skills: skills,
      plugins: plugins,
      slashBundle: slashBundle,
      deferFieldMount: widget.deferFieldMount,
      submitBlockedTooltip:
          launchWarningBlock != null && _controller.text.trim().isNotEmpty
          ? landingLaunchBlockMessage(
              l10n,
              launchWarningBlock,
              registry: CliToolRegistryScope.of(context),
            )
          : null,
    );

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
              composeCard,
            ],
          )
        : composeCard;

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
