import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../repositories/session_repository.dart';
import '../services/flashskyai_storage_roots.dart';
import '../cubits/skill_cubit.dart';
import '../cubits/team_cubit.dart';
import '../models/connection_mode.dart';
import '../l10n/l10n_extensions.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../widgets/app_outline_text_field.dart';
import '../widgets/settings/workspace_settings_widgets.dart';

const _kSessionPathPersistDebounce = Duration(milliseconds: 400);

/// Temporary: hide runtime mode until multi-mode UX is ready.
const _kShowConnectionModeSetting = false;

/// Team sessions use [AppStorage.commonFlashskyaiLlmConfigFile] from the
/// app-level provider catalog; per-session LLM path override is legacy only.
const _kShowLlmConfigPathSetting = false;

class SessionConfigWorkspace extends StatelessWidget {
  const SessionConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.watch<SessionPreferencesCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          _SessionHeading(
            title: l10n.session,
            subtitle: l10n.sessionPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        _SessionControls(cubit: cubit),
      ],
    );
  }
}

class _SessionHeading extends StatelessWidget {
  const _SessionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _SessionControls extends StatefulWidget {
  const _SessionControls({required this.cubit});

  final SessionPreferencesCubit cubit;

  @override
  State<_SessionControls> createState() => _SessionControlsState();
}

class _SessionControlsState extends State<_SessionControls> {
  late final TextEditingController _pathController;
  late final TextEditingController _sshCwdController;
  late final FocusNode _cliPathFocus;
  late final FocusNode _sshCwdFocus;
  late final Debouncer _cliPathPersistDebouncer;
  late final Debouncer _sshCwdPersistDebouncer;
  String _lastSyncedPath = '';
  String _lastSyncedSshCwd = '';

  @override
  void initState() {
    super.initState();
    _cliPathPersistDebouncer = Debouncer(
      tag: 'session_cli_executable_path',
      duration: _kSessionPathPersistDebounce,
    );
    _cliPathFocus = FocusNode()..addListener(_onCliPathFocusChanged);
    _sshCwdPersistDebouncer = Debouncer(
      tag: 'session_ssh_default_working_directory',
      duration: _kSessionPathPersistDebounce,
    );
    _sshCwdFocus = FocusNode()..addListener(_onSshCwdFocusChanged);
    _pathController = TextEditingController(
      text: widget.cubit.state.preferences.cliExecutablePath,
    );
    _sshCwdController = TextEditingController(
      text: widget.cubit.state.preferences.defaultSshWorkingDirectory,
    );
    _lastSyncedPath = widget.cubit.state.preferences.cliExecutablePath;
    _lastSyncedSshCwd =
        widget.cubit.state.preferences.defaultSshWorkingDirectory;
  }

  @override
  void dispose() {
    _cliPathPersistDebouncer.dispose();
    _sshCwdPersistDebouncer.dispose();
    _cliPathFocus.removeListener(_onCliPathFocusChanged);
    _sshCwdFocus.removeListener(_onSshCwdFocusChanged);
    _cliPathFocus.dispose();
    _sshCwdFocus.dispose();
    _pathController.dispose();
    _sshCwdController.dispose();
    super.dispose();
  }

  void _syncFromState(String stored, String sshCwd) {
    if (stored != _lastSyncedPath) {
      _cliPathPersistDebouncer.cancel();
      _lastSyncedPath = stored;
      _pathController.value = TextEditingValue(
        text: stored,
        selection: TextSelection.collapsed(offset: stored.length),
      );
    }
    if (sshCwd != _lastSyncedSshCwd) {
      _sshCwdPersistDebouncer.cancel();
      _lastSyncedSshCwd = sshCwd;
      _sshCwdController.value = TextEditingValue(
        text: sshCwd,
        selection: TextSelection.collapsed(offset: sshCwd.length),
      );
    }
  }

  Future<void> _pickFile() async {
    final cubit = widget.cubit;
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single.path;
    if (picked == null) return;
    if (!mounted) return;
    _cliPathPersistDebouncer.cancel();
    _pathController.text = picked;
    await cubit.setCliExecutablePath(picked);
  }

  Future<void> _persistCliExecutablePathFromField() async {
    if (!mounted) return;
    final cubit = widget.cubit;
    final trimmed = _pathController.text.trim();
    final stored = cubit.state.preferences.cliExecutablePath.trim();
    if (trimmed == stored) return;
    await cubit.setCliExecutablePath(_pathController.text);
  }

  Future<void> _persistSshCwdFromField() async {
    if (!mounted) return;
    final cubit = widget.cubit;
    final trimmed = _sshCwdController.text.trim();
    final stored = cubit.state.preferences.defaultSshWorkingDirectory.trim();
    if (trimmed == stored) return;
    await cubit.setDefaultSshWorkingDirectory(_sshCwdController.text);
  }

  void _onCliPathFocusChanged() {
    if (!_cliPathFocus.hasFocus) {
      _flushCliExecutablePathPersist();
    }
  }

  void _onSshCwdFocusChanged() {
    if (!_sshCwdFocus.hasFocus) {
      _flushSshCwdPersist();
    }
  }

  void _scheduleDebouncedCliPathPersist() {
    _cliPathPersistDebouncer(() {
      if (mounted) {
        _persistCliExecutablePathFromField();
      }
    });
  }

  void _scheduleDebouncedSshCwdPersist() {
    _sshCwdPersistDebouncer(() {
      if (mounted) {
        _persistSshCwdFromField();
      }
    });
  }

  void _flushCliExecutablePathPersist() {
    _cliPathPersistDebouncer.cancel();
    _persistCliExecutablePathFromField();
  }

  void _flushSshCwdPersist() {
    _sshCwdPersistDebouncer.cancel();
    _persistSshCwdFromField();
  }

  Future<void> _reset() async {
    _cliPathPersistDebouncer.cancel();
    _pathController.clear();
    await widget.cubit.setCliExecutablePath('');
  }

  Future<void> _resetSshCwd() async {
    _sshCwdPersistDebouncer.cancel();
    _sshCwdController.clear();
    await widget.cubit.setDefaultSshWorkingDirectory('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.cubit.state;
    _syncFromState(
      state.preferences.cliExecutablePath,
      state.preferences.defaultSshWorkingDirectory,
    );
    final isSshMode = widget.cubit.isSshMode;
    final effective = widget.cubit.resolveExecutable();
    final isFallback = state.preferences.cliExecutablePath.trim().isEmpty;
    final cliFieldEmpty = _pathController.text.trim().isEmpty;
    final cliHint = cliFieldEmpty
        ? '${l10n.cliExecutablePathUsing}$effective'
        : null;

    return Expanded(
      child: SingleChildScrollView(
        child: SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_kShowConnectionModeSetting)
                SettingsLabeledStackedRow(
                  title: l10n.connectionModeLabel,
                  subtitle: l10n.connectionModeDescription,
                  body: SegmentedButton<ConnectionMode>(
                    segments: [
                      ButtonSegment(
                        value: ConnectionMode.localPty,
                        label: Text(l10n.connectionModeLocal),
                        icon: const Icon(Icons.computer_outlined),
                      ),
                      ButtonSegment(
                        value: ConnectionMode.ssh,
                        label: Text(l10n.connectionModeSsh),
                        icon: const Icon(Icons.dns_outlined),
                      ),
                    ],
                    selected: {state.preferences.connectionMode},
                    onSelectionChanged: (selected) async {
                      final llmCubit = context.read<LlmConfigCubit>();
                      final teamCubit = context.read<TeamCubit>();
                      final skillCubit = context.read<SkillCubit>();
                      final chatCubit = context.read<ChatCubit>();
                      final sessionRepo = context.read<SessionRepository>();
                      final storageRoots =
                          context.read<FlashskyaiStorageRoots>();
                      await widget.cubit.setConnectionMode(selected.first);
                      if (!context.mounted) return;
                      storageRoots.invalidate();
                      await storageRoots.resolve();
                      await Future.wait([
                        llmCubit.load(),
                        teamCubit.load(),
                        skillCubit.loadAll(),
                        chatCubit.loadProjectData(sessionRepo),
                      ]);
                      await teamCubit.syncSelectedTeamSkills(
                        installed: skillCubit.state.installed,
                      );
                    },
                  ),
                  showDividerBelow: true,
                ),
              SettingsLabeledStackedRow(
                title: l10n.cliExecutablePathLabel,
                subtitle: isSshMode
                    ? l10n.cliExecutablePathDescriptionSsh
                    : l10n.cliExecutablePathDescription,
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: AppOutlineTextField(
                        key: AppKeys.cliExecutablePathField,
                        controller: _pathController,
                        focusNode: _cliPathFocus,
                        hintText: cliHint,
                        hintMaxLines: 3,
                        onChanged: (_) => _scheduleDebouncedCliPathPersist(),
                        onSubmitted: (_) => _flushCliExecutablePathPersist(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      key: AppKeys.cliExecutablePathBrowseButton,
                      onPressed: isSshMode ? null : _pickFile,
                      icon: const Icon(Icons.folder_open_outlined, size: 16),
                      label: Text(l10n.cliExecutablePathBrowse),
                    ),
                    const SizedBox(width: 6),
                    TextButton(
                      key: AppKeys.cliExecutablePathResetButton,
                      onPressed: isFallback ? null : _reset,
                      child: Text(l10n.cliExecutablePathReset),
                    ),
                  ],
                ),
                showDividerBelow: true,
              ),
              if (isSshMode) ...[
                SettingsLabeledStackedRow(
                  title: 'SSH 默认工作目录',
                  subtitle: 'SSH 启动没有项目路径时使用的远端工作目录；留空则不切换目录。',
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: AppOutlineTextField(
                          controller: _sshCwdController,
                          focusNode: _sshCwdFocus,
                          hintText: '~/work/project',
                          hintMaxLines: 2,
                          onChanged: (_) => _scheduleDebouncedSshCwdPersist(),
                          onSubmitted: (_) => _flushSshCwdPersist(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed:
                            state.preferences.defaultSshWorkingDirectory.isEmpty
                            ? null
                            : _resetSshCwd,
                        child: Text(l10n.cliExecutablePathReset),
                      ),
                    ],
                  ),
                  showDividerBelow: true,
                ),
                SettingsLabeledRow(
                  title: 'SSH 使用 bash 登录环境',
                  subtitle:
                      '通过 bash -lc 启动远端 flashskyai，以便读取远端 shell 配置中的 PATH。',
                  trailing: Switch(
                    value: state.preferences.sshUseLoginShell,
                    onChanged: (value) => widget.cubit.setSshUseLoginShell(value),
                  ),
                  showDividerBelow: true,
                ),
              ],
              if (_kShowLlmConfigPathSetting) const _LlmConfigPathSettingsRow(),
              SettingsLabeledRow(
                title: l10n.autoLaunchAllMembersTitle,
                subtitle: l10n.autoLaunchAllMembersDescription,
                trailing: Switch(
                  key: AppKeys.autoLaunchAllMembersOnConnectSwitch,
                  value: state.preferences.autoLaunchAllMembersOnConnect,
                  onChanged: (value) =>
                      widget.cubit.setAutoLaunchAllMembersOnConnect(value),
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledRow(
                title: l10n.scopeSessionsToSelectedTeamTitle,
                subtitle: l10n.scopeSessionsToSelectedTeamDescription,
                trailing: Switch(
                  key: AppKeys.scopeSessionsToSelectedTeamSwitch,
                  value: state.preferences.scopeSessionsToSelectedTeam,
                  onChanged: (value) =>
                      widget.cubit.setScopeSessionsToSelectedTeam(value),
                ),
                showDividerBelow: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LlmConfigPathSettingsRow extends StatefulWidget {
  const _LlmConfigPathSettingsRow();

  @override
  State<_LlmConfigPathSettingsRow> createState() =>
      _LlmConfigPathSettingsRowState();
}

class _LlmConfigPathSettingsRowState extends State<_LlmConfigPathSettingsRow> {
  late final TextEditingController _textController;
  late final FocusNode _llmPathFocus;
  late final Debouncer _llmPathPersistDebouncer;
  String _lastSyncedOverride = '';

  @override
  void initState() {
    super.initState();
    _llmPathPersistDebouncer = Debouncer(
      tag: 'session_llm_config_path',
      duration: _kSessionPathPersistDebounce,
    );
    _llmPathFocus = FocusNode()..addListener(_onLlmPathFocusChanged);
    final initial = context.read<LlmConfigCubit>().state.configPathOverride;
    _textController = TextEditingController(text: initial);
    _lastSyncedOverride = initial;
  }

  @override
  void dispose() {
    _llmPathPersistDebouncer.dispose();
    _llmPathFocus.removeListener(_onLlmPathFocusChanged);
    _llmPathFocus.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _syncFromState(String overrideText) {
    if (overrideText != _lastSyncedOverride) {
      _llmPathPersistDebouncer.cancel();
      _lastSyncedOverride = overrideText;
      _textController.value = TextEditingValue(
        text: overrideText,
        selection: TextSelection.collapsed(offset: overrideText.length),
      );
    }
  }

  Future<void> _pickFile() async {
    final state = context.read<LlmConfigCubit>().state;
    if (state.storageIsRemote) return;

    final l10n = context.l10n;
    final cubit = context.read<LlmConfigCubit>();
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.llmConfigPathPickerTitle,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final picked = result?.files.single.path;
    if (picked == null) return;
    if (!mounted) return;
    _llmPathPersistDebouncer.cancel();
    _textController.text = picked;
    await cubit.setConfigPath(picked);
  }

  Future<void> _persistLlmConfigPathFromField() async {
    if (!mounted) return;
    final cubit = context.read<LlmConfigCubit>();
    if (cubit.state.isLoading) return;
    final trimmed = _textController.text.trim();
    final stored = cubit.state.configPathOverride.trim();
    if (trimmed == stored) return;
    await cubit.setConfigPath(trimmed.isEmpty ? null : trimmed);
  }

  void _onLlmPathFocusChanged() {
    if (!_llmPathFocus.hasFocus) {
      _flushLlmConfigPathPersist();
    }
  }

  void _scheduleDebouncedLlmPathPersist() {
    _llmPathPersistDebouncer(() {
      if (mounted) {
        _persistLlmConfigPathFromField();
      }
    });
  }

  void _flushLlmConfigPathPersist() {
    _llmPathPersistDebouncer.cancel();
    _persistLlmConfigPathFromField();
  }

  Future<void> _reset() async {
    _llmPathPersistDebouncer.cancel();
    _textController.clear();
    await context.read<LlmConfigCubit>().setConfigPath(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<LlmConfigCubit>().state;
    _syncFromState(state.configPathOverride);

    final resolved = state.effectiveConfigPath.trim();
    final llmFieldEmpty = _textController.text.trim().isEmpty;
    final llmEffectiveDisplay = resolved.isEmpty
        ? l10n.llmConfigEffectivePathUnresolved
        : resolved;
    final llmHint = llmFieldEmpty
        ? '${l10n.cliExecutablePathUsing}$llmEffectiveDisplay'
        : null;

    final isRemote = state.storageIsRemote;

    return SettingsLabeledStackedRow(
      title: l10n.llmConfigPathLabel,
      subtitle: isRemote
          ? l10n.llmConfigPathSessionCardDescriptionSsh
          : l10n.llmConfigPathSessionCardDescription,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AppOutlineTextField(
              key: AppKeys.llmConfigPathOverrideField,
              controller: _textController,
              focusNode: _llmPathFocus,
              hintText: llmHint,
              hintMaxLines: 3,
              enabled: !state.isLoading,
              onChanged: state.isLoading
                  ? null
                  : (_) => _scheduleDebouncedLlmPathPersist(),
              onSubmitted: state.isLoading
                  ? null
                  : (_) => _flushLlmConfigPathPersist(),
            ),
          ),
          if (!isRemote) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              key: AppKeys.llmConfigPathOverrideBrowseButton,
              onPressed: state.isLoading ? null : _pickFile,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: Text(l10n.cliExecutablePathBrowse),
            ),
          ],
          const SizedBox(width: 6),
          TextButton(
            key: AppKeys.llmConfigPathOverrideResetButton,
            onPressed: state.isLoading || !state.isUsingCustomPath
                ? null
                : _reset,
            child: Text(l10n.cliExecutablePathReset),
          ),
        ],
      ),
      showDividerBelow: true,
    );
  }
}
