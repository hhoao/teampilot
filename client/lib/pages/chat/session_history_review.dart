import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/session_history_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/config_bundle.dart';
import '../../models/landing_launch_context.dart';
import '../../models/team_config.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../../services/ai/headless_ai_service.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/compose/compose_file_attach.dart';
import '../../services/compose/compose_landing_bundle.dart';
import '../../services/compose/compose_prompt_enhance.dart';
import '../../services/compose/compose_text_edit.dart';
import '../../services/compose/compose_voice_input.dart';
import '../../services/storage/app_storage.dart';
import '../../theme/app_spacing.dart';
import 'session_history_turn_list.dart';
import 'session_review_compose_card.dart';

/// History list + slim compose for a non-running session body.
class SessionHistoryReview extends StatefulWidget {
  const SessionHistoryReview({
    required this.session,
    required this.selectedMemberId,
    required this.onSubmit,
    this.team,
    this.launchError,
    this.isSubmitting = false,
    super.key,
  });

  final AppSession session;
  final String selectedMemberId;
  final TeamProfile? team;
  /// Returns `true` after successful connect+inject so compose can clear.
  final Future<bool> Function(String message) onSubmit;
  final String? launchError;
  final bool isSubmitting;

  @override
  State<SessionHistoryReview> createState() => _SessionHistoryReviewState();
}

class _SessionHistoryReviewState extends State<SessionHistoryReview> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  late final ComposeVoiceInput _voiceInput;
  final _headlessAi = HeadlessAiService();

  var _enhancing = false;
  var _voiceListening = false;
  var _voiceSoundLevel = 0.0;
  var _discardVoiceTranscript = false;
  TextEditingValue? _voiceInsertBaseline;
  Stopwatch? _voiceStopwatch;
  Timer? _voiceTimer;
  var _workspaceProjectBundle = const ConfigBundle();
  var _workspaceBundleGeneration = 0;

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
          variant: AppToastVariant.warning,
        );
        _applyVoiceListening(false);
      },
    );
    unawaited(_voiceInput.initialize());
    _controller.addListener(_onComposeChanged);
    _loadHistory();
    unawaited(_loadWorkspaceProjectBundle());
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
  void didUpdateWidget(covariant SessionHistoryReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.sessionId != widget.session.sessionId ||
        oldWidget.selectedMemberId != widget.selectedMemberId ||
        oldWidget.team?.id != widget.team?.id) {
      _loadHistory();
    }
    if (oldWidget.session.workspaceId != widget.session.workspaceId) {
      unawaited(_loadWorkspaceProjectBundle());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onComposeChanged);
    _stopVoiceSessionClock();
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

  Duration get _voiceElapsed => _voiceStopwatch?.elapsed ?? Duration.zero;

  String get _workspaceRoot {
    final work = widget.session.workDirsForMember(
      widget.selectedMemberId,
      folders: widget.session.folders,
    );
    if (work.workingDirectory.isNotEmpty) return work.workingDirectory;
    return widget.session.firstFolderPath;
  }

  void _loadHistory({bool force = false}) {
    context.read<SessionHistoryCubit>().load(
      session: widget.session,
      memberId: widget.selectedMemberId,
      team: widget.team,
      workingDirectory: _workspaceRoot,
      force: force,
    );
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

  ConfigBundle _slashBundle() {
    final draft = _enhanceDraft();
    final identity = identityBundleForLanding(draft: draft, team: widget.team);
    return unionConfigBundles(identity, _workspaceProjectBundle);
  }

  Future<void> _attachFiles() async {
    if (widget.isSubmitting || _enhancing) return;
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
    if (widget.isSubmitting || _enhancing) return false;
    final pasted = await pasteComposeImageAttachment(
      controller: _controller,
      workspaceRoot: _workspaceRoot,
    );
    if (pasted && mounted) setState(() {});
    return pasted;
  }

  Future<void> _enhancePrompt() async {
    final draft = _controller.text.trim();
    if (draft.isEmpty || widget.isSubmitting || _enhancing) return;

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
        variant: AppToastVariant.warning,
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
          variant: AppToastVariant.warning,
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
        variant: AppToastVariant.warning,
      );
    } on Object {
      if (!mounted) return;
      AppToast.show(
        context,
        message: context.l10n.workspaceChatLandingEnhanceFailed,
        variant: AppToastVariant.warning,
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
        variant: AppToastVariant.warning,
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
    if (text.isEmpty || widget.isSubmitting) return;
    final ok = await widget.onSubmit(text);
    if (!ok || !mounted) return;
    // Clear only after successful inject; keep text on connect/inject failure.
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.appSpacing;
    final cs = Theme.of(context).colorScheme;
    final skills = context.watch<SkillCubit>().state.installed;
    final plugins = context.watch<PluginCubit>().state.installed;
    final canSubmit =
        _controller.text.trim().isNotEmpty && !widget.isSubmitting;

    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: BlocBuilder<SessionHistoryCubit, SessionHistoryState>(
              builder: (context, state) {
                return SessionHistoryTurnList(
                  state: state,
                  onRetry: () => _loadHistory(force: true),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.sm,
              spacing.lg,
              spacing.lg,
            ),
            child: SessionReviewComposeCard(
              controller: _controller,
              focusNode: _focusNode,
              hint: l10n.sessionHistoryComposeHint,
              canSubmit: canSubmit,
              isSubmitting: widget.isSubmitting,
              onSubmit: () => unawaited(_handleSubmit()),
              onChanged: (_) => setState(() {}),
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
              workspaceRoot: _workspaceRoot,
              skills: skills,
              plugins: plugins,
              slashBundle: _slashBundle(),
              launchError: widget.launchError,
              onPasteImage: _pasteComposeImage,
            ),
          ),
        ],
      ),
    );
  }
}
