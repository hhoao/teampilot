import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/llm_config_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/app_keys.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'session_config_constants.dart';

class SessionLlmConfigPathSettingsRow extends StatefulWidget {
  const SessionLlmConfigPathSettingsRow();

  @override
  State<SessionLlmConfigPathSettingsRow> createState() =>
      SessionLlmConfigPathSettingsRowState();
}

class SessionLlmConfigPathSettingsRowState extends State<SessionLlmConfigPathSettingsRow> {
  late final TextEditingController _textController;
  late final FocusNode _llmPathFocus;
  late final Debouncer _llmPathPersistDebouncer;
  String _lastSyncedOverride = '';

  @override
  void initState() {
    super.initState();
    _llmPathPersistDebouncer = Debouncer(
      tag: 'session_llm_config_path',
      duration: kSessionPathPersistDebounce,
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
    if (!mounted) return;
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
    if (!mounted) return;
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
              icon: const Icon(Icons.folder_open_outlined, size: AppIconSizes.md),
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
