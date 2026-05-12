import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_preferences_cubit.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_workspace_settings_theme.dart';
import '../utils/app_keys.dart';
import '../widgets/settings/workspace_settings_widgets.dart';

class SessionConfigWorkspace extends StatelessWidget {
  const SessionConfigWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.watch<SessionPreferencesCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SessionHeading(
          title: l10n.session,
          subtitle: l10n.sessionPageSubtitle,
        ),
        const SizedBox(height: 16),
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
    final tokens = AppWorkspaceSettingsTokens.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: tokens.workspaceHeadingTitleStyle(onSurface)),
        SizedBox(height: tokens.workspaceHeadingTitleSubtitleGap),
        Text(subtitle, style: tokens.workspaceHeadingSubtitleStyle(onSurface)),
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
  String _lastSyncedPath = '';

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(
      text: widget.cubit.state.preferences.cliExecutablePath,
    );
    _lastSyncedPath = widget.cubit.state.preferences.cliExecutablePath;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _syncFromState(String stored) {
    if (stored != _lastSyncedPath) {
      _lastSyncedPath = stored;
      _pathController.value = TextEditingValue(
        text: stored,
        selection: TextSelection.collapsed(offset: stored.length),
      );
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    final picked = result?.files.single.path;
    if (picked == null) return;
    _pathController.text = picked;
    await widget.cubit.setCliExecutablePath(picked);
  }

  Future<void> _apply() async {
    await widget.cubit.setCliExecutablePath(_pathController.text);
  }

  Future<void> _reset() async {
    _pathController.clear();
    await widget.cubit.setCliExecutablePath('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.cubit.state;
    _syncFromState(state.preferences.cliExecutablePath);
    final effective = widget.cubit.resolveExecutable();
    final isFallback = state.preferences.cliExecutablePath.trim().isEmpty;
    final helper = isFallback
        ? l10n.cliExecutablePathUsingFallback
        : '${l10n.cliExecutablePathUsing}$effective';

    return Expanded(
      child: SingleChildScrollView(
        child: SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsLabeledRow(
                title: l10n.cliExecutablePathLabel,
                subtitle: l10n.cliExecutablePathDescription,
                trailing: SizedBox(
                  width: 480,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: AppKeys.cliExecutablePathField,
                          controller: _pathController,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (_) => _apply(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        key: AppKeys.cliExecutablePathBrowseButton,
                        onPressed: _pickFile,
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
                ),
                showDividerBelow: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  helper,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
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
                showDividerBelow: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
