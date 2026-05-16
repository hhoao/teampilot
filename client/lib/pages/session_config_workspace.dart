import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/llm_config_cubit.dart';
import '../cubits/session_preferences_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../widgets/app_outline_text_field.dart';
import '../widgets/settings/workspace_settings_widgets.dart';

const _kSessionPathPersistDebounce = Duration(milliseconds: 400);

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
  late final FocusNode _cliPathFocus;
  late final Debouncer _cliPathPersistDebouncer;
  String _lastSyncedPath = '';

  @override
  void initState() {
    super.initState();
    _cliPathPersistDebouncer = Debouncer(
      tag: 'session_cli_executable_path',
      duration: _kSessionPathPersistDebounce,
    );
    _cliPathFocus = FocusNode()..addListener(_onCliPathFocusChanged);
    _pathController = TextEditingController(
      text: widget.cubit.state.preferences.cliExecutablePath,
    );
    _lastSyncedPath = widget.cubit.state.preferences.cliExecutablePath;
  }

  @override
  void dispose() {
    _cliPathPersistDebouncer.dispose();
    _cliPathFocus.removeListener(_onCliPathFocusChanged);
    _cliPathFocus.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _syncFromState(String stored) {
    if (stored != _lastSyncedPath) {
      _cliPathPersistDebouncer.cancel();
      _lastSyncedPath = stored;
      _pathController.value = TextEditingValue(
        text: stored,
        selection: TextSelection.collapsed(offset: stored.length),
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

  void _onCliPathFocusChanged() {
    if (!_cliPathFocus.hasFocus) {
      _flushCliExecutablePathPersist();
    }
  }

  void _scheduleDebouncedCliPathPersist() {
    _cliPathPersistDebouncer(() {
      if (mounted) {
        _persistCliExecutablePathFromField();
      }
    });
  }

  void _flushCliExecutablePathPersist() {
    _cliPathPersistDebouncer.cancel();
    _persistCliExecutablePathFromField();
  }

  Future<void> _reset() async {
    _cliPathPersistDebouncer.cancel();
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
              SettingsLabeledStackedRow(
                title: l10n.cliExecutablePathLabel,
                subtitle: l10n.cliExecutablePathDescription,
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
                showDividerBelow: true,
              ),
              const _LlmConfigPathSettingsRow(),
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

    return SettingsLabeledStackedRow(
      title: l10n.llmConfigPathLabel,
      subtitle: l10n.llmConfigPathSessionCardDescription,
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
          const SizedBox(width: 6),
          OutlinedButton.icon(
            key: AppKeys.llmConfigPathOverrideBrowseButton,
            onPressed: state.isLoading ? null : _pickFile,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(l10n.cliExecutablePathBrowse),
          ),
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
