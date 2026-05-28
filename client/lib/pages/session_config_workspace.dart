import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app/app_shell.dart';
import '../cubits/app_provider_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../repositories/session_repository.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/flashskyai_storage_roots.dart';
import '../cubits/mcp_cubit.dart';
import '../cubits/plugin_cubit.dart';
import '../cubits/skill_cubit.dart';
import '../cubits/team_cubit.dart';
import '../models/connection_mode.dart';
import '../models/team_config.dart';
import '../models/windows_storage_backend.dart';
import '../l10n/l10n_extensions.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../services/cli/cli_installer_service.dart';
import '../services/app/connection_mode_service.dart';
import '../services/storage/runtime_storage_context.dart';
import '../services/ssh/ssh_client_factory.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../widgets/cli_install_progress_panel.dart';
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
  late final TextEditingController _sshCwdController;
  late final FocusNode _sshCwdFocus;
  late final Debouncer _sshCwdPersistDebouncer;
  String _lastSyncedSshCwd = '';

  @override
  void initState() {
    super.initState();
    _sshCwdPersistDebouncer = Debouncer(
      tag: 'session_ssh_default_working_directory',
      duration: _kSessionPathPersistDebounce,
    );
    _sshCwdFocus = FocusNode()..addListener(_onSshCwdFocusChanged);
    _sshCwdController = TextEditingController(
      text: widget.cubit.state.preferences.defaultSshWorkingDirectory,
    );
    _lastSyncedSshCwd =
        widget.cubit.state.preferences.defaultSshWorkingDirectory;
  }

  @override
  void dispose() {
    _sshCwdPersistDebouncer.dispose();
    _sshCwdFocus.removeListener(_onSshCwdFocusChanged);
    _sshCwdFocus.dispose();
    _sshCwdController.dispose();
    super.dispose();
  }

  void _syncFromState(String sshCwd) {
    if (sshCwd != _lastSyncedSshCwd) {
      _sshCwdPersistDebouncer.cancel();
      _lastSyncedSshCwd = sshCwd;
      _sshCwdController.value = TextEditingValue(
        text: sshCwd,
        selection: TextSelection.collapsed(offset: sshCwd.length),
      );
    }
  }

  Future<void> _persistSshCwdFromField() async {
    if (!mounted) return;
    final cubit = widget.cubit;
    final trimmed = _sshCwdController.text.trim();
    final stored = cubit.state.preferences.defaultSshWorkingDirectory.trim();
    if (trimmed == stored) return;
    await cubit.setDefaultSshWorkingDirectory(_sshCwdController.text);
  }

  void _onSshCwdFocusChanged() {
    if (!_sshCwdFocus.hasFocus) {
      _flushSshCwdPersist();
    }
  }

  void _scheduleDebouncedSshCwdPersist() {
    _sshCwdPersistDebouncer(() {
      if (mounted) {
        _persistSshCwdFromField();
      }
    });
  }

  void _flushSshCwdPersist() {
    _sshCwdPersistDebouncer.cancel();
    _persistSshCwdFromField();
  }

  Future<void> _resetSshCwd() async {
    _sshCwdPersistDebouncer.cancel();
    _sshCwdController.clear();
    await widget.cubit.setDefaultSshWorkingDirectory('');
  }

  Future<void> _reloadAfterStorageBackendChange() async {
    final storageRoots = context.read<FlashskyaiStorageRoots>();
    final llmCubit = context.read<LlmConfigCubit>();
    final teamCubit = context.read<TeamCubit>();
    final skillCubit = context.read<SkillCubit>();
    final mcpCubit = context.read<McpCubit>();
    final chatCubit = context.read<ChatCubit>();
    final sessionRepo = context.read<SessionRepository>();
    storageRoots.invalidate();
    await storageRoots.reinstallAndResolve();
    await reloadRemoteBackedAppData(
      storageRoots: storageRoots,
      llmConfigCubit: llmCubit,
      appProviderCubit: context.read<AppProviderCubit>(),
      teamCubit: teamCubit,
      pluginCubit: context.read<PluginCubit>(),
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      sshProfileCubit: context.read<SshProfileCubit>(),
    );
  }

  Future<void> _onWindowsStorageBackendChanged(
    WindowsStorageBackend selected,
  ) async {
    final l10n = context.l10n;
    final current = widget.cubit.state.preferences.windowsStorageBackend;
    if (selected == current) return;

    if (selected == WindowsStorageBackend.wsl) {
      final distro = RuntimeStorageContext.parseWslDistro(
        widget.cubit.resolveExecutable(),
      );
      final available = await RuntimeStorageContext.probeWslAvailable(
        distro: distro,
      );
      if (!available) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.windowsStorageBackendWslUnavailable)),
        );
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.windowsStorageBackendSwitchConfirmTitle),
        content: Text(l10n.windowsStorageBackendSwitchConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.windowsStorageBackendSwitchConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await widget.cubit.setWindowsStorageBackend(selected);
    if (!mounted) return;
    await _reloadAfterStorageBackendChange();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.cubit.state;
    _syncFromState(state.preferences.defaultSshWorkingDirectory);
    final isSshMode = widget.cubit.isSshMode;

    return Expanded(
      child: SingleChildScrollView(
        child: SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Platform.isWindows) ...[
                SettingsLabeledStackedRow(
                  title: l10n.windowsStorageBackendTitle,
                  subtitle: l10n.windowsStorageBackendDescription,
                  body: SegmentedButton<WindowsStorageBackend>(
                    segments: [
                      ButtonSegment(
                        value: WindowsStorageBackend.native,
                        label: Text(l10n.windowsStorageBackendNative),
                        icon: const Icon(Icons.folder_outlined),
                      ),
                      ButtonSegment(
                        value: WindowsStorageBackend.wsl,
                        label: Text(l10n.windowsStorageBackendWsl),
                        icon: const Icon(Icons.terminal),
                      ),
                    ],
                    selected: {state.preferences.windowsStorageBackend},
                    onSelectionChanged: (selected) =>
                        _onWindowsStorageBackendChanged(selected.first),
                  ),
                  showDividerBelow: true,
                ),
              ],
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
                      final mcpCubit = context.read<McpCubit>();
                      final chatCubit = context.read<ChatCubit>();
                      final sessionRepo = context.read<SessionRepository>();
                      final storageRoots = context
                          .read<FlashskyaiStorageRoots>();
                      await widget.cubit.setConnectionMode(selected.first);
                      if (!context.mounted) return;
                      storageRoots.invalidate();
                      await storageRoots.resolve();
                      await Future.wait([
                        llmCubit.load(),
                        teamCubit.load(),
                        skillCubit.loadAll(),
                        mcpCubit.loadAll(),
                        chatCubit.loadProjectData(sessionRepo),
                      ]);
                      await teamCubit.syncSelectedTeamSkills(
                        installed: skillCubit.state.installed,
                      );
                      await teamCubit.syncSelectedTeamPlugins(
                        installed: context.read<PluginCubit>().state.installed,
                      );
                      await teamCubit.syncSelectedTeamMcp(
                        installed: mcpCubit.state.servers,
                      );
                    },
                  ),
                  showDividerBelow: true,
                ),
              _CliExecutablePathSettingsRow(
                cubit: widget.cubit,
                cli: TeamCli.flashskyai,
                title: l10n.cliExecutablePathLabel,
                subtitle: isSshMode
                    ? l10n.cliExecutablePathDescriptionSsh
                    : l10n.cliExecutablePathDescription,
                fieldKey: AppKeys.cliExecutablePathField,
                browseKey: AppKeys.cliExecutablePathBrowseButton,
                resetKey: AppKeys.cliExecutablePathResetButton,
                debouncerTag: 'session_cli_executable_path',
                showDividerBelow: true,
              ),
              _CliExecutablePathSettingsRow(
                cubit: widget.cubit,
                cli: TeamCli.claude,
                title: l10n.claudeCliExecutablePathLabel,
                subtitle: isSshMode
                    ? l10n.claudeCliExecutablePathDescriptionSsh
                    : l10n.claudeCliExecutablePathDescription,
                fieldKey: AppKeys.claudeCliExecutablePathField,
                browseKey: AppKeys.claudeCliExecutablePathBrowseButton,
                resetKey: AppKeys.claudeCliExecutablePathResetButton,
                debouncerTag: 'session_claude_cli_executable_path',
                installKey: AppKeys.claudeCliInstallButton,
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
                        child: TextField(
                          controller: _sshCwdController,
                          focusNode: _sshCwdFocus,
                          decoration: InputDecoration(
                            hintText: '~/work/project',
                            hintMaxLines: 1,
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                          ),
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
                    onChanged: (value) =>
                        widget.cubit.setSshUseLoginShell(value),
                  ),
                  showDividerBelow: true,
                ),
              ],
              if (_kShowLlmConfigPathSetting) const _LlmConfigPathSettingsRow(),
              SettingsLabeledRow(
                title: l10n.terminalScrollbackLinesTitle,
                subtitle: l10n.terminalScrollbackLinesDescription,
                trailing: SizedBox(
                  width: 120,
                  child: TextFormField(
                    initialValue:
                        '${state.preferences.terminalScrollbackLines}',
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (value) {
                      final parsed = int.tryParse(value.trim());
                      if (parsed != null) {
                        unawaited(
                          widget.cubit.setTerminalScrollbackLines(parsed),
                        );
                      }
                    },
                  ),
                ),
                showDividerBelow: true,
              ),
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

class _CliExecutablePathSettingsRow extends StatefulWidget {
  const _CliExecutablePathSettingsRow({
    required this.cubit,
    required this.cli,
    required this.title,
    required this.subtitle,
    required this.fieldKey,
    required this.browseKey,
    required this.resetKey,
    required this.debouncerTag,
    required this.showDividerBelow,
    this.installKey,
  });

  final SessionPreferencesCubit cubit;
  final TeamCli cli;
  final String title;
  final String subtitle;
  final Key fieldKey;
  final Key browseKey;
  final Key resetKey;
  final String debouncerTag;
  final bool showDividerBelow;
  final Key? installKey;

  @override
  State<_CliExecutablePathSettingsRow> createState() =>
      _CliExecutablePathSettingsRowState();
}

class _CliExecutablePathSettingsRowState
    extends State<_CliExecutablePathSettingsRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final Debouncer _persistDebouncer;
  String _lastSyncedPath = '';
  bool _isInstalling = false;
  CliInstallPhase? _installPhase;
  final List<String> _installLog = [];

  @override
  void initState() {
    super.initState();
    _persistDebouncer = Debouncer(
      tag: widget.debouncerTag,
      duration: _kSessionPathPersistDebounce,
    );
    _focusNode = FocusNode()..addListener(_onFocusChanged);
    final initial = _storedPath();
    _controller = TextEditingController(text: initial);
    _lastSyncedPath = initial;
  }

  @override
  void dispose() {
    _persistDebouncer.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _storedPath() {
    final prefs = widget.cubit.state.preferences;
    if (widget.cli == TeamCli.flashskyai) {
      return prefs.cliExecutablePath;
    }
    return prefs.cliExecutablePaths[widget.cli.value] ?? '';
  }

  void _syncFromState(String stored) {
    if (stored == _lastSyncedPath) return;
    _persistDebouncer.cancel();
    _lastSyncedPath = stored;
    _controller.value = TextEditingValue(
      text: stored,
      selection: TextSelection.collapsed(offset: stored.length),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single.path;
    if (picked == null) return;
    if (!mounted) return;
    _persistDebouncer.cancel();
    _controller.text = picked;
    await widget.cubit.setCliExecutablePathFor(widget.cli, picked);
  }

  Future<void> _persistFromField() async {
    if (!mounted) return;
    final trimmed = _controller.text.trim();
    final stored = _storedPath().trim();
    if (trimmed == stored) return;
    await widget.cubit.setCliExecutablePathFor(widget.cli, _controller.text);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _flushPersist();
    }
  }

  void _scheduleDebouncedPersist() {
    _persistDebouncer(() {
      if (mounted) {
        _persistFromField();
      }
    });
  }

  void _flushPersist() {
    _persistDebouncer.cancel();
    _persistFromField();
  }

  Future<void> _reset() async {
    _persistDebouncer.cancel();
    _controller.clear();
    await widget.cubit.setCliExecutablePathFor(widget.cli, '');
  }

  Future<void> _installCli() async {
    if (_isInstalling) return;
    setState(() {
      _isInstalling = true;
      _installPhase = CliInstallPhase.checkingNpm;
      _installLog.clear();
    });
    try {
      final connectionMode = context.read<ConnectionModeService>();
      final sshProfile = context.read<SshProfileCubit>().state.selectedProfile;
      final installer = CliInstallerService(
        sshClientFactory: context.read<SshClientFactory>(),
      );
      final result = await installer.install(
        cli: widget.cli,
        mode: connectionMode.isSshMode
            ? CliInstallMode.ssh
            : CliInstallMode.local,
        sshProfile: sshProfile,
        onProgress: _onInstallProgress,
      );
      if (!mounted) return;
      final path = result.executablePath?.trim() ?? '';
      if (result.success && path.isNotEmpty) {
        _persistDebouncer.cancel();
        _controller.text = path;
        await widget.cubit.setCliExecutablePathFor(widget.cli, path);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _installPhase = null;
        });
      }
    }
  }

  void _onInstallProgress(CliInstallProgress progress) {
    if (!mounted) return;
    setState(() {
      _installPhase = progress.phase;
      final detail = progress.detail?.trim();
      if (detail != null && detail.isNotEmpty) {
        _installLog.add(detail);
        if (_installLog.length > 80) {
          _installLog.removeRange(0, _installLog.length - 80);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stored = _storedPath();
    _syncFromState(stored);

    final isSshMode = widget.cubit.isSshMode;
    final effective = widget.cubit.resolveExecutable(widget.cli);
    final isFallback = stored.trim().isEmpty;
    final fieldEmpty = _controller.text.trim().isEmpty;
    final hint = fieldEmpty ? '${l10n.cliExecutablePathUsing}$effective' : null;

    return SettingsLabeledStackedRow(
      title: widget.title,
      subtitle: widget.subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: widget.fieldKey,
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintMaxLines: 1,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                  onChanged: (_) => _scheduleDebouncedPersist(),
                  onSubmitted: (_) => _flushPersist(),
                ),
              ),
              const SizedBox(width: 6),
              if (widget.installKey != null) ...[
                OutlinedButton.icon(
                  key: widget.installKey,
                  onPressed: _isInstalling ? null : _installCli,
                  icon: _isInstalling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined, size: 16),
                  label: Text(
                    _isInstalling
                        ? l10n.cliInstallInstalling
                        : l10n.cliInstallButton,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              OutlinedButton.icon(
                key: widget.browseKey,
                onPressed: isSshMode ? null : _pickFile,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(l10n.cliExecutablePathBrowse),
              ),
              const SizedBox(width: 6),
              TextButton(
                key: widget.resetKey,
                onPressed: isFallback ? null : _reset,
                child: Text(l10n.cliExecutablePathReset),
              ),
            ],
          ),
          if (_isInstalling && _installPhase != null) ...[
            const SizedBox(height: 12),
            CliInstallProgressPanel(
              phase: _installPhase!,
              logLines: _installLog,
            ),
          ],
        ],
      ),
      showDividerBelow: widget.showDividerBelow,
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
            child: TextField(
              key: AppKeys.llmConfigPathOverrideField,
              controller: _textController,
              focusNode: _llmPathFocus,
              enabled: !state.isLoading,
              decoration: InputDecoration(
                hintText: llmHint,
                hintMaxLines: 1,
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
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
