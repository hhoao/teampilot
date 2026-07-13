import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/automation_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation_tab_scope.dart';
import '../../models/automation.dart';
import '../../models/launch_profile.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../cubits/chat_cubit.dart';
import '../../services/automation/automation_launch_session_binding.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/automation/workspace_automation_profiles.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/textarea/app_textarea.dart';
import '../../widgets/cli/cli_preset_dropdown_field.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import 'automation_schedule_picker.dart';

enum AutomationEditorKind { scheduledMessage, launchPrompt }

/// Editor for session scheduled messages or workspace launch-prompt automations.
class AutomationEditorDialog extends StatefulWidget {
  const AutomationEditorDialog({
    this.initial,
    this.kind = AutomationEditorKind.launchPrompt,
    this.workspaceId,
    this.launchProfileId,
    this.sessionId,
    this.defaultName,
    this.pickLaunchProfile = false,
    super.key,
  });

  final Automation? initial;
  final AutomationEditorKind kind;
  final String? workspaceId;
  final String? launchProfileId;
  final String? sessionId;
  final String? defaultName;
  final bool pickLaunchProfile;

  static Future<Automation?> show(
    BuildContext context, {
    Automation? initial,
    AutomationEditorKind kind = AutomationEditorKind.launchPrompt,
    String? workspaceId,
    String? launchProfileId,
    String? sessionId,
    String? defaultName,
    bool pickLaunchProfile = false,
  }) {
    return showDialog<Automation>(
      context: context,
      builder: (_) => AutomationEditorDialog(
        initial: initial,
        kind: kind,
        workspaceId: workspaceId,
        launchProfileId: launchProfileId,
        sessionId: sessionId,
        defaultName: defaultName,
        pickLaunchProfile: pickLaunchProfile,
      ),
    );
  }

  @override
  State<AutomationEditorDialog> createState() => _AutomationEditorDialogState();
}

class _AutomationEditorDialogState extends State<AutomationEditorDialog> {
  final _calculator = AutomationScheduleCalculator();
  late final TextEditingController _nameCtl;
  late final TextEditingController _messageCtl;
  late final TextEditingController _maxRunCountCtl;
  late bool _reuseSession;
  late bool _enabled;
  late AutomationScheduleDraft _schedule;
  String? _errorMessage;
  String? _cliPresetId;
  String _targetMemberId = 'team-lead';
  String _selectedLaunchProfileId = '';
  var _didSeedLaunchFields = false;

  bool get _isScheduledMessage =>
      widget.kind == AutomationEditorKind.scheduledMessage;

  bool get _isEditing => widget.initial != null;

  /// True when persisted [runCount] has already hit the current max-run field.
  bool get _runLimitReached {
    final runCount = widget.initial?.runCount ?? 0;
    final maxRunRaw = _maxRunCountCtl.text.trim();
    if (maxRunRaw.isEmpty) return false;
    final maxRun = int.tryParse(maxRunRaw);
    if (maxRun == null || maxRun < 1) return false;
    return runCount >= maxRun;
  }

  String get _launchProfileId {
    if (widget.initial != null) return widget.initial!.launchProfileId;
    if (_selectedLaunchProfileId.trim().isNotEmpty) {
      return _selectedLaunchProfileId;
    }
    return widget.launchProfileId ?? '';
  }

  bool get _showsLaunchProfilePicker =>
      widget.pickLaunchProfile && !_isEditing && !_isScheduledMessage;

  bool get _isSimpleLaunch =>
      _launchProfileId == AutomationTabScope.simpleLaunchProfileId;

  TeamProfile? get _teamProfile {
    final profile = context.read<LaunchProfileCubit>().state.byId(
      _launchProfileId,
    );
    return profile is TeamProfile ? profile : null;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final workspaceId = initial?.workspaceId ?? widget.workspaceId ?? '';
    final launchProfileId =
        initial?.launchProfileId ?? widget.launchProfileId ?? '';
    _selectedLaunchProfileId = launchProfileId;

    _nameCtl = TextEditingController(
      text: initial?.name ?? widget.defaultName ?? '',
    );
    _messageCtl = TextEditingController(text: initial?.message ?? '');
    _maxRunCountCtl = TextEditingController(
      text: initial?.maxRunCount?.toString() ?? '',
    );
    _cliPresetId = initial?.cliPresetId;
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

    if (workspaceId.isEmpty && initial == null) {
      _errorMessage = 'workspaceId required';
    } else if (launchProfileId.isEmpty &&
        initial == null &&
        !widget.pickLaunchProfile) {
      _errorMessage = 'launchProfileId required';
    }
  }

  Workspace? get _workspace {
    final workspaceId = widget.initial?.workspaceId ?? widget.workspaceId ?? '';
    if (workspaceId.isEmpty) return null;
    return context.read<ChatCubit>().state.workspaces
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull;
  }

  List<LaunchProfile> get _launchProfileChoices {
    final workspace = _workspace;
    if (workspace == null) return const [];
    return launchProfilesForWorkspaceAutomations(
      workspace: workspace,
      profiles: context.read<LaunchProfileCubit>().state,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_showsLaunchProfilePicker && _selectedLaunchProfileId.trim().isEmpty) {
      final workspace = _workspace;
      if (workspace != null) {
        _selectedLaunchProfileId = defaultLaunchProfileIdForWorkspace(
          workspace: workspace,
          profiles: context.read<LaunchProfileCubit>().state,
        );
      }
    }
    if (_didSeedLaunchFields || _isScheduledMessage) return;
    _didSeedLaunchFields = true;
    _seedLaunchPromptDefaults();
  }

  void _onLaunchProfileChanged(String profileId) {
    setState(() {
      _selectedLaunchProfileId = profileId;
      _cliPresetId = null;
      _targetMemberId = 'team-lead';
      _didSeedLaunchFields = false;
    });
    _didSeedLaunchFields = true;
    _seedLaunchPromptDefaults();
  }

  void _seedLaunchPromptDefaults() {
    final initial = widget.initial;
    if (_cliPresetId != null && _cliPresetId!.trim().isNotEmpty) return;

    if (initial?.cliPresetId != null &&
        initial!.cliPresetId!.trim().isNotEmpty) {
      setState(() => _cliPresetId = initial.cliPresetId);
      return;
    }

    if (_isSimpleLaunch) {
      final presets = context.read<CliPresetsCubit>().state.presets;
      if (initial?.cli != null) {
        final match = presets.where((p) => p.cli == initial!.cli).firstOrNull;
        if (match != null) {
          setState(() => _cliPresetId = match.id);
          return;
        }
      }
      if (presets.isNotEmpty) {
        setState(() => _cliPresetId = presets.first.id);
      }
      return;
    }

    final team = _teamProfile;
    if (team == null) return;
    final memberId = initial?.targetMemberId.trim() ?? '';
    if (memberId.isNotEmpty &&
        team.members.any((m) => m.id == memberId && m.isValid)) {
      setState(() => _targetMemberId = memberId);
      return;
    }
    final lead = team.members.where((m) => m.id == 'team-lead').firstOrNull;
    if (lead != null && lead.isValid) {
      setState(() => _targetMemberId = lead.id);
      return;
    }
    final first = team.members.where((m) => m.isValid).firstOrNull;
    if (first != null) {
      setState(() => _targetMemberId = first.id);
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _messageCtl.dispose();
    _maxRunCountCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _nameCtl.text.trim();
    final message = _messageCtl.text.trim();
    if (name.isEmpty || message.isEmpty) {
      setState(() => _errorMessage = l10n.automationsValidationRequired);
      return;
    }

    if (!_isScheduledMessage && _isSimpleLaunch) {
      final presetId = _cliPresetId?.trim() ?? '';
      if (presetId.isEmpty) {
        setState(() => _errorMessage = l10n.workspaceCliPresetsEmptyHint);
        return;
      }
    }

    if (_schedule.preset == AutomationSchedulePreset.custom) {
      final cron = _schedule.customCron?.trim() ?? '';
      if (!_calculator.isValidCron(cron)) {
        setState(() => _errorMessage = l10n.automationsInvalidCron);
        return;
      }
    }

    try {
      parseHourMinute(_schedule.hourMinute);
    } on Object {
      setState(() => _errorMessage = l10n.automationsInvalidTime);
      return;
    }

    final maxRunRaw = _maxRunCountCtl.text.trim();
    int? maxRunCount;
    if (maxRunRaw.isNotEmpty) {
      final parsed = int.tryParse(maxRunRaw);
      if (parsed == null || parsed < 1) {
        setState(() => _errorMessage = l10n.automationsInvalidMaxRunCount);
        return;
      }
      maxRunCount = parsed;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final workspaceId = widget.initial?.workspaceId ?? widget.workspaceId ?? '';
    final launchProfileId = _launchProfileId.trim();
    if (launchProfileId.isEmpty) {
      setState(() => _errorMessage = l10n.automationsValidationRequired);
      return;
    }
    final launchSessionId = _isScheduledMessage
        ? (widget.initial?.sessionId ?? widget.sessionId)
        : (_reuseSession ? widget.initial?.sessionId : null);

    final presetId = _cliPresetId?.trim();
    var automation = Automation(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: name,
      action: _isScheduledMessage
          ? AutomationAction.scheduledMessage
          : AutomationAction.launchPrompt,
      workspaceId: workspaceId,
      launchProfileId: launchProfileId,
      sessionId: launchSessionId,
      targetMemberId: _isSimpleLaunch ? 'team-lead' : _targetMemberId,
      message: message,
      cli: null,
      cliPresetId: _isSimpleLaunch ? presetId : null,
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
      setState(() => _errorMessage = e.message);
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

  List<TeamMemberConfig> get _teamMemberItems {
    final members = _teamProfile?.members ?? const [];
    return members.where((m) => m.isValid).toList(growable: false);
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
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final title = _isEditing
        ? (_isScheduledMessage
              ? l10n.automationsCompactTitle
              : l10n.automationsEditTitle)
        : (_isScheduledMessage
              ? l10n.automationsCompactTitle
              : l10n.automationsCreateTitle);

    return AppDialog(
      maxWidth: _isScheduledMessage ? 480 : 560,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: AppDialogPinnedLayout(
        header: AppDialogHeader(title: title),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: styles.smColored(cs.error),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameCtl,
            decoration: InputDecoration(labelText: l10n.automationsName),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final bodyStyle =
                  Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
              return AppTextarea(
                controller: _messageCtl,
                decoration: InputDecoration(labelText: l10n.automationsMessage),
                minHeight: appTextareaHeightForLines(bodyStyle, lines: 2),
                maxHeight: appTextareaHeightForLines(bodyStyle, lines: 5),
              );
            },
          ),
          if (_showsLaunchProfilePicker) ...[
            Text(
              l10n.automationsLaunchProfile,
              style: styles.smSemibold,
            ),
            const SizedBox(height: 8),
            if (_launchProfileChoices.isEmpty)
              Text(
                l10n.automationsValidationRequired,
                style: styles.smColored(cs.error),
              )
            else
              AppDropdownField<String>(
                items: _launchProfileChoices.map((profile) => profile.id).toList(),
                initialItem:
                    _launchProfileChoices.any(
                      (profile) => profile.id == _selectedLaunchProfileId,
                    )
                    ? _selectedLaunchProfileId
                    : _launchProfileChoices.first.id,
                decoration: AppDropdownDecorations.themed(context),
                itemLabel: (profileId) {
                  final profile = _launchProfileChoices
                      .where((candidate) => candidate.id == profileId)
                      .firstOrNull;
                  return profile?.display ?? profileId;
                },
                onChanged: (value) {
                  if (value == null) return;
                  _onLaunchProfileChanged(value);
                },
              ),
            const SizedBox(height: 16),
          ],
          if (!_isScheduledMessage) ...[
            const SizedBox(height: 16),
            if (_isSimpleLaunch) ...[
              CliPresetDropdownField(
                label: l10n.presetPickerTitle,
                selectedPresetId: _cliPresetId,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _cliPresetId = value);
                },
              ),
            ] else ...[
              Text(
                l10n.automationsTargetMember,
                style: styles.smSemibold,
              ),
              const SizedBox(height: 8),
              if (_teamMemberItems.isEmpty)
                Text(
                  l10n.automationsValidationRequired,
                  style: styles.smColored(cs.error),
                )
              else
                AppDropdownField<String>(
                  items: _teamMemberItems.map((m) => m.id).toList(),
                  initialItem:
                      _teamMemberItems.any((m) => m.id == _targetMemberId)
                      ? _targetMemberId
                      : _teamMemberItems.first.id,
                  decoration: AppDropdownDecorations.themed(context),
                  itemLabel: (memberId) {
                    final member = _teamMemberItems
                        .where((m) => m.id == memberId)
                        .firstOrNull;
                    return member?.name ?? memberId;
                  },
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _targetMemberId = value);
                  },
                ),
            ],
            const SizedBox(height: 16),
            _EditorSwitchRow(
              title: l10n.automationsReuseSession,
              subtitle: _reuseSessionBoundSubtitle(l10n),
              value: _reuseSession,
              onChanged: (v) => setState(() => _reuseSession = v),
            ),
          ],
          const SizedBox(height: 16),
          AutomationSchedulePicker(
            draft: _schedule,
            calculator: _calculator,
            onChanged: (draft) => setState(() => _schedule = draft),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxRunCountCtl,
            decoration: InputDecoration(
              labelText: l10n.automationsMaxRunCount,
              hintText: l10n.automationsMaxRunCountHint,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {
              if (_runLimitReached && _enabled) _enabled = false;
            }),
          ),
          const SizedBox(height: 12),
          _EditorSwitchRow(
            title: l10n.automationsEnabled,
            value: _runLimitReached ? false : _enabled,
            onChanged: _runLimitReached
                ? null
                : (v) => setState(() => _enabled = v),
          ),
          ],
        ),
        footer: AppDialogActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(onPressed: _save, child: Text(l10n.save)),
          ],
        ),
      ),
    );
  }
}

/// Switch row without [SwitchListTile] ink/hover — cleaner inside dialogs.
class _EditorSwitchRow extends StatelessWidget {
  const _EditorSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    return Row(
      crossAxisAlignment: hasSubtitle
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: styles.mdMedium,
              ),
              if (hasSubtitle) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: styles.xsColored(cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
