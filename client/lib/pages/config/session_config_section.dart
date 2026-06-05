import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/app_shell.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/llm_config_cubit.dart';
import '../../cubits/mcp_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/connection_mode.dart';
import '../../models/windows_storage_backend.dart';
import '../../repositories/session_repository.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../services/storage/storage_resolver.dart';
import '../../services/storage/runtime_storage_context.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'session_config_constants.dart';
import 'session_llm_path_settings_row.dart';

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
      duration: kSessionPathPersistDebounce,
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
    if (!mounted) return;
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
    if (!mounted) return;
    _sshCwdPersistDebouncer.cancel();
    _persistSshCwdFromField();
  }

  Future<void> _resetSshCwd() async {
    _sshCwdPersistDebouncer.cancel();
    _sshCwdController.clear();
    await widget.cubit.setDefaultSshWorkingDirectory('');
  }

  Future<void> _reloadAfterStorageBackendChange() async {
    final storageRoots = context.read<StorageRoots>();
    final llmCubit = context.read<LlmConfigCubit>();
    final teamCubit = context.read<TeamCubit>();
    final skillCubit = context.read<SkillCubit>();
    final mcpCubit = context.read<McpCubit>();
    final chatCubit = context.read<ChatCubit>();
    final sessionRepo = context.read<SessionRepository>();
    final appProviderCubit = context.read<AppProviderCubit>();
    final pluginCubit = context.read<PluginCubit>();
    final sshProfileCubit = context.read<SshProfileCubit>();
    storageRoots.invalidate();
    await storageRoots.reinstallAndResolve();
    await reloadRemoteBackedAppData(
      storageRoots: storageRoots,
      llmConfigCubit: llmCubit,
      appProviderCubit: appProviderCubit,
      teamCubit: teamCubit,
      pluginCubit: pluginCubit,
      skillCubit: skillCubit,
      mcpCubit: mcpCubit,
      chatCubit: chatCubit,
      sessionRepo: sessionRepo,
      sshProfileCubit: sshProfileCubit,
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

    if (!mounted) return;
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
              if (kShowConnectionModeSetting)
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
                      final storageRoots = context.read<StorageRoots>();
                      final pluginCubit = context.read<PluginCubit>();
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
                        installed: pluginCubit.state.installed,
                      );
                      await teamCubit.syncSelectedTeamMcp(
                        installed: mcpCubit.state.servers,
                      );
                    },
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
              if (kShowLlmConfigPathSetting)
                const SessionLlmConfigPathSettingsRow(),
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
