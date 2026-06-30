import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/session_preferences.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/connection_mode_service.dart';
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
        const Expanded(child: _SessionControls()),
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
  const _SessionControls();

  @override
  State<_SessionControls> createState() => _SessionControlsState();
}

class _SessionControlsState extends State<_SessionControls> {
  SessionPreferencesCubit? _cubit;
  var _controllersReady = false;
  late final TextEditingController _sshCwdController;
  late final FocusNode _sshCwdFocus;
  late final Debouncer _sshCwdPersistDebouncer;
  String _lastSyncedSshCwd = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit ??= context.read<SessionPreferencesCubit>();
    if (_controllersReady) return;
    _controllersReady = true;
    _sshCwdPersistDebouncer = Debouncer(
      tag: 'session_ssh_default_working_directory',
      duration: kSessionPathPersistDebounce,
    );
    _sshCwdFocus = FocusNode()..addListener(_onSshCwdFocusChanged);
    final sshCwd = _cubit!.state.preferences.defaultSshWorkingDirectory;
    _sshCwdController = TextEditingController(text: sshCwd);
    _lastSyncedSshCwd = sshCwd;
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
    final cubit = _cubit!;
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
    await _cubit!.setDefaultSshWorkingDirectory('');
  }


  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = _cubit!;
    final isSshMode = context.select<ConnectionModeService, bool>(
      (service) => service.isSshMode,
    );

    return BlocSelector<
      SessionPreferencesCubit,
      SessionPreferencesState,
      _SessionControlsSnapshot
    >(
      selector: (state) => _SessionControlsSnapshot.from(state.preferences),
      builder: (context, snapshot) {
        _syncFromState(snapshot.defaultSshWorkingDirectory);
        return SingleChildScrollView(
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
                            decoration: const InputDecoration(
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
                          onPressed: snapshot.defaultSshWorkingDirectory.isEmpty
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
                      value: snapshot.sshUseLoginShell,
                      onChanged: (value) => cubit.setSshUseLoginShell(value),
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
                      initialValue: '${snapshot.terminalScrollbackLines}',
                      keyboardType: TextInputType.number,
                      onFieldSubmitted: (value) {
                        final parsed = int.tryParse(value.trim());
                        if (parsed != null) {
                          unawaited(cubit.setTerminalScrollbackLines(parsed));
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
                    value: snapshot.terminalLinkClickOpensInApp,
                    onChanged: (value) =>
                        cubit.setTerminalLinkClickOpensInApp(value),
                  ),
                  showDividerBelow: true,
                ),
                SettingsLabeledRow(
                  title: l10n.autoLaunchAllMembersTitle,
                  subtitle: l10n.autoLaunchAllMembersDescription,
                  trailing: Switch(
                    key: AppKeys.autoLaunchAllMembersOnConnectSwitch,
                    value: snapshot.autoLaunchAllMembersOnConnect,
                    onChanged: (value) =>
                        cubit.setAutoLaunchAllMembersOnConnect(value),
                  ),
                  showDividerBelow: true,
                ),
                SettingsLabeledRow(
                  title: l10n.scopeSessionsToSelectedTeamTitle,
                  subtitle: l10n.scopeSessionsToSelectedTeamDescription,
                  trailing: Switch(
                    key: AppKeys.scopeSessionsToSelectedTeamSwitch,
                    value: snapshot.scopeSessionsToSelectedTeam,
                    onChanged: (value) =>
                        cubit.setScopeSessionsToSelectedTeam(value),
                  ),
                  showDividerBelow: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SessionControlsSnapshot {
  const _SessionControlsSnapshot({
    required this.defaultSshWorkingDirectory,
    required this.sshUseLoginShell,
    required this.terminalScrollbackLines,
    required this.terminalLinkClickOpensInApp,
    required this.autoLaunchAllMembersOnConnect,
    required this.scopeSessionsToSelectedTeam,
  });

  final String defaultSshWorkingDirectory;
  final bool sshUseLoginShell;
  final int terminalScrollbackLines;
  final bool terminalLinkClickOpensInApp;
  final bool autoLaunchAllMembersOnConnect;
  final bool scopeSessionsToSelectedTeam;

  static _SessionControlsSnapshot from(SessionPreferences preferences) {
    return _SessionControlsSnapshot(
      defaultSshWorkingDirectory: preferences.defaultSshWorkingDirectory,
      sshUseLoginShell: preferences.sshUseLoginShell,
      terminalScrollbackLines: preferences.terminalScrollbackLines,
      terminalLinkClickOpensInApp: preferences.terminalLinkClickOpensInApp,
      autoLaunchAllMembersOnConnect:
          preferences.autoLaunchAllMembersOnConnect,
      scopeSessionsToSelectedTeam: preferences.scopeSessionsToSelectedTeam,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _SessionControlsSnapshot &&
        other.defaultSshWorkingDirectory == defaultSshWorkingDirectory &&
        other.sshUseLoginShell == sshUseLoginShell &&
        other.terminalScrollbackLines == terminalScrollbackLines &&
        other.terminalLinkClickOpensInApp == terminalLinkClickOpensInApp &&
        other.autoLaunchAllMembersOnConnect == autoLaunchAllMembersOnConnect &&
        other.scopeSessionsToSelectedTeam == scopeSessionsToSelectedTeam;
  }

  @override
  int get hashCode => Object.hash(
    defaultSshWorkingDirectory,
    sshUseLoginShell,
    terminalScrollbackLines,
    terminalLinkClickOpensInApp,
    autoLaunchAllMembersOnConnect,
    scopeSessionsToSelectedTeam,
  );
}
