import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../app/app_shell.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/extension_cubit.dart';
import '../../cubits/llm_config_cubit.dart';
import '../../cubits/mcp_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../widgets/app_dialog.dart';
import '../../models/connection_mode.dart';
import '../../repositories/session_repository.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/storage/runtime_context.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'runtime_target_picker.dart';
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


  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.cubit.state;
    _syncFromState(state.preferences.defaultSshWorkingDirectory);
    final isSshMode = context.watch<ConnectionModeService>().isSshMode;

    return Expanded(
      child: SingleChildScrollView(
        child: SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RuntimeTargetPicker(),
              if (isSshMode) ...[
                SettingsLabeledStackedRow(
                  title: l10n.sshDefaultWorkingDirectoryTitle,
                  subtitle: l10n.sshDefaultWorkingDirectorySubtitle,
                  body: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sshCwdController,
                          focusNode: _sshCwdFocus,
                          decoration: InputDecoration(
                            hintText: '~/work/workspace',
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
                title: l10n.terminalLinkClickOpensInAppTitle,
                subtitle: l10n.terminalLinkClickOpensInAppDescription,
                trailing: Switch(
                  key: AppKeys.terminalLinkClickOpensInAppSwitch,
                  value: state.preferences.terminalLinkClickOpensInApp,
                  onChanged: (value) =>
                      widget.cubit.setTerminalLinkClickOpensInApp(value),
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
