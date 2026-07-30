import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/automation_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../pages/home_workspace/workspace/workspace_landing_selectors.dart';
import '../../services/automation/automation_launch_session_binding.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/workspace/workspace_pane_policy.dart';
import '../../utils/workspace/landing_draft_resolver.dart';
import '../../utils/workspace/workspace_path_utils.dart';
import 'package:shared_ui/shared_ui.dart';
import 'automation_editor_form_body.dart';
import 'automation_schedule_picker.dart';

enum AutomationEditorKind { scheduledMessage, launchPrompt }

/// Editor for session scheduled messages or workspace launch-prompt automations.
class AutomationEditorDialog extends StatefulWidget {
  const AutomationEditorDialog({
    this.initial,
    this.kind = AutomationEditorKind.launchPrompt,
    this.workspaceId,
    this.sessionId,
    this.defaultName,
    super.key,
  });

  final Automation? initial;
  final AutomationEditorKind kind;
  final String? workspaceId;
  final String? sessionId;
  final String? defaultName;

  static Future<Automation?> show(
    BuildContext context, {
    Automation? initial,
    AutomationEditorKind kind = AutomationEditorKind.launchPrompt,
    String? workspaceId,
    String? sessionId,
    String? defaultName,
  }) {
    return showTpDialog<Automation>(
      context: context,
      presentation: TpDialogPresentation.page,
      mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
      maxWidth: kind == AutomationEditorKind.scheduledMessage ? 480 : 560,
      builder: (_) => AutomationEditorDialog(
        initial: initial,
        kind: kind,
        workspaceId: workspaceId,
        sessionId: sessionId,
        defaultName: defaultName,
      ),
    );
  }

  @override
  State<AutomationEditorDialog> createState() => _AutomationEditorDialogState();
}

class _AutomationEditorDialogState extends State<AutomationEditorDialog> {
  final _formKey = GlobalKey<TpFormState>();
  final _calculator = AutomationScheduleCalculator();
  late final TextEditingController _nameCtl;
  late final TextEditingController _messageCtl;
  late final TextEditingController _maxRunCountCtl;
  late bool _reuseSession;
  late bool _enabled;
  late AutomationScheduleDraft _schedule;
  late bool _isPersonal;
  String? _presetId;
  String? _teamId;
  String? _expertKey;
  String? _projectFolderPath;
  String? _workingDirectoryPath;
  late bool _dangerouslySkipPermissions;
  late String _targetMemberId;
  var _didSeedLaunchFields = false;

  bool get _isScheduledMessage =>
      widget.kind == AutomationEditorKind.scheduledMessage;

  bool get _isEditing => widget.initial != null;

  bool get _runLimitReached {
    final runCount = widget.initial?.runCount ?? 0;
    final maxRunRaw = _maxRunCountCtl.text.trim();
    if (maxRunRaw.isEmpty) return false;
    final maxRun = int.tryParse(maxRunRaw);
    if (maxRun == null || maxRun < 1) return false;
    return runCount >= maxRun;
  }

  TeamProfile? get _selectedTeam {
    final id = _teamId?.trim() ?? '';
    if (id.isEmpty) return null;
    return context.read<LaunchProfileCubit>().state.teams
        .where((t) => t.id == id)
        .firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;

    _nameCtl = TextEditingController(
      text: initial?.name ?? widget.defaultName ?? '',
    );
    _messageCtl = TextEditingController(text: initial?.message ?? '');
    _maxRunCountCtl = TextEditingController(
      text: initial?.maxRunCount?.toString() ?? '',
    );
    _isPersonal = initial?.isPersonal ?? true;
    _presetId = initial?.presetId;
    _teamId = initial?.teamId;
    _expertKey = initial?.expertKey;
    _projectFolderPath = initial?.projectFolderPath;
    _workingDirectoryPath = initial?.workingDirectoryPath;
    _dangerouslySkipPermissions = initial?.dangerouslySkipPermissions ?? false;
    _targetMemberId = initial?.targetMemberId ?? 'team-lead';
    _reuseSession = initial?.reuseSession ?? false;
    _enabled = initial?.enabled ?? true;
    _schedule = initial != null
        ? scheduleDraftFromAutomation(initial)
        : AutomationScheduleDraft(
            preset: AutomationSchedulePreset.daily,
            minute: 0,
            hourMinute: '09:00',
            timezone: DateTime.now().timeZoneName,
          );

    if (!_isScheduledMessage && initial == null) {
      unawaited(_seedFromLandingDraft());
    }
  }

  Workspace? get _workspace {
    final workspaceId = widget.initial?.workspaceId ?? widget.workspaceId ?? '';
    if (workspaceId.isEmpty) return null;
    return context.read<ChatCubit>().state.workspaces
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didSeedLaunchFields || _isScheduledMessage) return;
    _didSeedLaunchFields = true;
    _seedLaunchDefaults();
  }

  Future<void> _seedFromLandingDraft() async {
    final workspaceId = widget.initial?.workspaceId ?? widget.workspaceId ?? '';
    if (workspaceId.isEmpty) return;

    final draft = await resolveLandingDraft(
      workspaceId: workspaceId,
      simpleModeDefaultFullAccess: context
          .read<SessionPreferencesCubit>()
          .state
          .preferences
          .simpleModeDefaultFullAccess,
    );
    if (!mounted) return;
    setState(() {
      _isPersonal = draft.isPersonal;
      _presetId = draft.presetId;
      _teamId = draft.teamId;
      _expertKey = draft.expertKey;
      _projectFolderPath = draft.projectFolderPath;
      _workingDirectoryPath = draft.workingDirectoryPath;
      _dangerouslySkipPermissions = draft.dangerouslySkipPermissions;
    });
    _seedTeamMemberDefault();
    _seedPresetDefault();
    _seedLocationDefaults();
  }

  void _seedLaunchDefaults() {
    if (widget.initial != null) return;
    _seedPresetDefault();
    _seedTeamMemberDefault();
    _seedLocationDefaults();
  }

  void _seedLocationDefaults() {
    if (_isScheduledMessage) return;
    final workspace = _workspace;
    if (workspace == null) return;
    final resolver = WorkspaceLandingProjectResolver(
      workspace: workspace,
      storedProjectPath: _projectFolderPath,
    );
    final project = resolver.resolveSelectedProjectPath().trim();
    if (project.isEmpty) return;
    setState(() {
      if (_projectFolderPath == null || _projectFolderPath!.trim().isEmpty) {
        _projectFolderPath = project;
      }
      if (_workingDirectoryPath == null ||
          _workingDirectoryPath!.trim().isEmpty) {
        _workingDirectoryPath = project;
      }
    });
  }

  String? _resolvedProjectFolderPath(Workspace? workspace) {
    final stored = _projectFolderPath?.trim() ?? '';
    if (stored.isNotEmpty) return normalizeWorkspacePath(stored);
    if (workspace == null) return null;
    final resolved = WorkspaceLandingProjectResolver(
      workspace: workspace,
      storedProjectPath: _projectFolderPath,
    ).resolveSelectedProjectPath().trim();
    if (resolved.isEmpty) return null;
    return normalizeWorkspacePath(resolved);
  }

  String? _resolvedWorkingDirectoryPath(Workspace? workspace) {
    final stored = _workingDirectoryPath?.trim() ?? '';
    if (stored.isNotEmpty) return normalizeWorkspacePath(stored);
    return _resolvedProjectFolderPath(workspace);
  }

  void _seedPresetDefault() {
    if (!_isPersonal) return;
    if (_presetId != null && _presetId!.trim().isNotEmpty) return;
    final presets = context.read<CliPresetsCubit>().state.presets;
    if (presets.isEmpty) return;
    setState(() => _presetId = presets.first.id);
  }

  void _seedTeamMemberDefault() {
    if (_isPersonal) return;
    final team = _selectedTeam ??
        context.read<LaunchProfileCubit>().state.teams.firstOrNull;
    if (team == null) return;
    if (_teamId == null || _teamId!.trim().isEmpty) {
      setState(() => _teamId = team.id);
    }
    final members = team.members.where((m) => m.isValid).toList();
    if (members.isEmpty) return;
    if (members.any((m) => m.id == _targetMemberId)) return;
    final lead = members.where((m) => m.id == 'team-lead').firstOrNull;
    setState(() => _targetMemberId = lead?.id ?? members.first.id);
  }

  void _onIsPersonalChanged(bool isPersonal) {
    setState(() {
      _isPersonal = isPersonal;
      if (isPersonal) {
        _teamId = null;
      } else {
        _presetId = null;
        _expertKey = null;
        final teams = context.read<LaunchProfileCubit>().state.teams;
        _teamId = teams.firstOrNull?.id;
      }
    });
    if (isPersonal) {
      _seedPresetDefault();
    } else {
      _seedTeamMemberDefault();
    }
  }

  void _onTeamChanged(String? teamId) {
    setState(() {
      _teamId = teamId;
      _targetMemberId = 'team-lead';
    });
    _seedTeamMemberDefault();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _messageCtl.dispose();
    _maxRunCountCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final name = _nameCtl.text.trim();
    final message = _messageCtl.text.trim();

    final maxRunRaw = _maxRunCountCtl.text.trim();
    int? maxRunCount;
    if (maxRunRaw.isNotEmpty) {
      maxRunCount = int.tryParse(maxRunRaw);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final workspaceId = widget.initial?.workspaceId ?? widget.workspaceId ?? '';
    final launchSessionId = _isScheduledMessage
        ? (widget.initial?.sessionId ?? widget.sessionId)
        : (_reuseSession ? widget.initial?.sessionId : null);

    final presetId = _presetId?.trim();
    final teamId = _teamId?.trim();
    final expertKey = _expertKey?.trim();
    final workspace = _workspace;
    final projectFolderPath = _resolvedProjectFolderPath(workspace);
    final workingDirectoryPath = _resolvedWorkingDirectoryPath(workspace);

    var automation = Automation(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: name,
      action: _isScheduledMessage
          ? AutomationAction.scheduledMessage
          : AutomationAction.launchPrompt,
      workspaceId: workspaceId,
      isPersonal: _isPersonal,
      presetId: _isPersonal ? presetId : null,
      teamId: _isPersonal ? null : teamId,
      expertKey: _isPersonal && expertKey != null && expertKey.isNotEmpty
          ? expertKey
          : null,
      projectFolderPath: _isScheduledMessage ? null : projectFolderPath,
      workingDirectoryPath: _isScheduledMessage ? null : workingDirectoryPath,
      dangerouslySkipPermissions: _dangerouslySkipPermissions,
      sessionId: launchSessionId,
      targetMemberId: _isPersonal ? 'team-lead' : _targetMemberId,
      message: message,
      reuseSession: _isScheduledMessage ? false : _reuseSession,
      preset: _schedule.preset,
      customCron: _schedule.customCron,
      dayOfWeek: _schedule.dayOfWeek,
      minute: _schedule.minute,
      hourMinute: _schedule.hourMinute,
      timezone: _schedule.timezone,
      dtstartMs: widget.initial?.dtstartMs ?? nowMs,
      enabled: _enabled,
      nextRunAtMs: widget.initial?.nextRunAtMs,
      lastRunAtMs: widget.initial?.lastRunAtMs,
      maxRunCount: maxRunCount,
      runCount: widget.initial?.runCount ?? 0,
      createdAtMs: widget.initial?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
    );
    automation = AutomationLaunchSessionBinding.stripWhenReuseDisabled(
      automation,
    );

    try {
      automation.validate();
    } on ArgumentError catch (e) {
      form.setFieldError('name', e.message?.toString() ?? e.toString());
      return;
    }

    final nextRun = _enabled && !_runLimitReached
        ? _calculator.computeNextRunAtMs(automation, afterMs: nowMs)
        : null;
    final saved = automation.copyWith(
      nextRunAtMs: nextRun,
      clearNextRunAtMs: nextRun == null,
      enabled: _enabled && !_runLimitReached,
    );

    final cubit = context.read<AutomationCubit>();
    await cubit.save(saved);
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  String _reuseSessionBoundSubtitle(AppLocalizations l10n) {
    if (!_reuseSession) return l10n.automationsReuseSessionSubtitleOff;
    final bound = widget.initial?.sessionId?.trim() ?? '';
    if (bound.isEmpty) return l10n.automationsReuseSessionSubtitlePending;
    return l10n.automationsReuseSessionSubtitleBound(bound);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _isEditing
        ? (_isScheduledMessage
              ? l10n.automationsCompactTitle
              : l10n.automationsEditTitle)
        : (_isScheduledMessage
              ? l10n.automationsCompactTitle
              : l10n.automationsCreateTitle);

    return TpDialogPageShell(
      title: title,
      child: TpForm(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: AutomationEditorFormBody(
                  isScheduledMessage: _isScheduledMessage,
                  nameController: _nameCtl,
                  messageController: _messageCtl,
                  maxRunCountController: _maxRunCountCtl,
                  schedule: _schedule,
                  onScheduleChanged: (draft) =>
                      setState(() => _schedule = draft),
                  calculator: _calculator,
                  enabled: _enabled,
                  onEnabledChanged: (v) => setState(() => _enabled = v),
                  runLimitReached: _runLimitReached,
                  reuseSession: _reuseSession,
                  onReuseSessionChanged: (v) =>
                      setState(() => _reuseSession = v),
                  reuseSessionSubtitle: _reuseSessionBoundSubtitle(l10n),
                  onMaxRunCountChanged: () => setState(() {
                    if (_runLimitReached && _enabled) _enabled = false;
                  }),
                  workspace: _workspace,
                  isPersonal: _isPersonal,
                  projectFolderPath: _projectFolderPath,
                  workingDirectoryPath: _workingDirectoryPath,
                  presetId: _presetId,
                  teamId: _teamId,
                  expertKey: _expertKey,
                  dangerouslySkipPermissions: _dangerouslySkipPermissions,
                  targetMemberId: _targetMemberId,
                  onIsPersonalChanged: _onIsPersonalChanged,
                  onProjectChanged: (v) =>
                      setState(() => _projectFolderPath = v),
                  onWorktreeChanged: (v) =>
                      setState(() => _workingDirectoryPath = v),
                  onPresetChanged: (v) => setState(() => _presetId = v),
                  onTeamChanged: _onTeamChanged,
                  onExpertChanged: (v) => setState(() => _expertKey = v),
                  onPermissionsChanged: (v) =>
                      setState(() => _dangerouslySkipPermissions = v),
                  onTargetMemberChanged: (v) =>
                      setState(() => _targetMemberId = v),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TpDialogActions(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(onPressed: _save, child: Text(l10n.save)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
