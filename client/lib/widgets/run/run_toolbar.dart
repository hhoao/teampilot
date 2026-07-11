import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../services/run/launch_adapter_protocol.dart';
import '../../services/run/launch_type_unavailable.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../theme/app_control_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/hover_text_tooltip.dart';

/// Host file-pick result for an `isAction` dropdown entry.
typedef RunActionPicker =
    Future<Map<String, Object?>?> Function(
      LaunchAdapterConfigurationEntry action,
    );

/// Opens a `launch.json` path in the editor (or creates it).
typedef RunOpenLaunchJson = Future<void> Function(String path);

/// Top-bar Run controls: config dropdown, inline options, Run/Stop, open JSON.
class RunToolbar extends StatelessWidget {
  const RunToolbar({
    required this.workspaceId,
    this.showFolderLabels = false,
    this.pickActionResult,
    this.openLaunchJson,
    super.key,
  });

  final String workspaceId;
  final bool showFolderLabels;

  /// Host UI for `isAction` items. When null, action selection is a no-op.
  final RunActionPicker? pickActionResult;

  /// Injected for tests; defaults to [WorkbenchEditorOpener.openFile].
  final RunOpenLaunchJson? openLaunchJson;

  @override
  Widget build(BuildContext context) {
    final control = context.appControl;
    return BlocBuilder<RunCubit, RunState>(
      builder: (context, state) {
        return SizedBox(
          height: control.height + 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                _ConfigDropdown(
                  state: state,
                  showFolderLabels: showFolderLabels,
                  pickActionResult: pickActionResult,
                ),
                const SizedBox(width: 8),
                ..._inlineOptions(context, state),
                const Spacer(),
                _OpenLaunchJsonButton(
                  workspaceId: workspaceId,
                  openLaunchJson: openLaunchJson,
                ),
                const SizedBox(width: 4),
                _StopButton(state: state),
                const SizedBox(width: 4),
                _RunButton(state: state),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _inlineOptions(BuildContext context, RunState state) {
    final cubit = context.read<RunCubit>();
    final widgets = <Widget>[];
    for (final option in state.options) {
      if (option.type != LaunchOptionType.choice || option.choices.isEmpty) {
        continue;
      }
      final current = state.optionValues[option.id] ?? option.value;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _OptionChoiceDropdown(
            option: option,
            value: current?.toString(),
            onChanged: (value) => cubit.setOption(option.id, value),
          ),
        ),
      );
    }
    return widgets;
  }
}

sealed class _DropdownEntry {
  const _DropdownEntry();
}

final class _ConfigEntry extends _DropdownEntry {
  const _ConfigEntry(this.owned);
  final OwnedLaunchConfiguration owned;
}

final class _ActionEntry extends _DropdownEntry {
  const _ActionEntry(this.action);
  final LaunchAdapterConfigurationEntry action;
}

class _ConfigDropdown extends StatelessWidget {
  const _ConfigDropdown({
    required this.state,
    required this.showFolderLabels,
    this.pickActionResult,
  });

  final RunState state;
  final bool showFolderLabels;
  final RunActionPicker? pickActionResult;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RunCubit>();
    final entries = <_DropdownEntry>[
      for (final config in state.configurations) _ConfigEntry(config),
      for (final action in state.actions)
        if (action.isAction) _ActionEntry(action),
    ];

    final selected = state.selectedConfiguration;
    final label = selected == null
        ? l10n.runSelectConfiguration
        : _configLabel(selected, showFolderLabels: showFolderLabels);

    final cs = Theme.of(context).colorScheme;
    final control = context.appControl;
    return PopupMenuButton<_DropdownEntry>(
      key: const Key('run-config-dropdown'),
      tooltip: l10n.runConfigurationTooltip,
      onSelected: (entry) => unawaited(_onSelected(context, cubit, entry)),
      itemBuilder: (context) {
        return [
          for (final entry in entries)
            PopupMenuItem<_DropdownEntry>(
              value: entry,
              enabled: _isEnabled(cubit, entry),
              child: _itemChild(context, cubit, entry),
            ),
        ];
      },
      child: Container(
        height: control.height,
        constraints: const BoxConstraints(minWidth: 160),
        padding: EdgeInsets.symmetric(horizontal: control.horizontalPadding),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  bool _isEnabled(RunCubit cubit, _DropdownEntry entry) {
    return switch (entry) {
      _ConfigEntry(:final owned) => cubit.isConfigurationAvailable(owned),
      _ActionEntry(:final action) => cubit.isActionAvailable(action),
    };
  }

  Widget _itemChild(
    BuildContext context,
    RunCubit cubit,
    _DropdownEntry entry,
  ) {
    final (text, type, reasonCode) = switch (entry) {
      _ConfigEntry(:final owned) => (
        _configLabel(owned, showFolderLabels: showFolderLabels),
        owned.configuration.type,
        cubit.unavailableReason(owned),
      ),
      _ActionEntry(:final action) => (
        action.name,
        action.type,
        cubit.actionUnavailableReason(action),
      ),
    };
    final child = Text(text);
    final reason = localizeLaunchTypeUnavailable(
      context.l10n,
      reasonCode,
      type: type,
    );
    if (reason == null || reason.isEmpty) return child;
    return HoverTextTooltip(message: reason, child: child);
  }

  Future<void> _onSelected(
    BuildContext context,
    RunCubit cubit,
    _DropdownEntry entry,
  ) async {
    switch (entry) {
      case _ConfigEntry(:final owned):
        await cubit.select(owned.selectionKey);
      case _ActionEntry(:final action):
        final picker = pickActionResult;
        if (picker == null) return;
        final result = await picker(action);
        if (result == null) return;
        await cubit.configureAction(
          actionId: action.id,
          type: action.type,
          result: result,
        );
    }
  }
}

class _OptionChoiceDropdown extends StatelessWidget {
  const _OptionChoiceDropdown({
    required this.option,
    required this.value,
    required this.onChanged,
  });

  final LaunchOption option;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final control = context.appControl;
    return SizedBox(
      height: control.height,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value != null &&
                  option.choices.any((c) => c.value == value)
              ? value
              : null,
          hint: Text(option.label),
          items: [
            for (final choice in option.choices)
              DropdownMenuItem(
                value: choice.value,
                child: Text(choice.label),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({required this.state});

  final RunState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = state.selectedConfiguration != null;
    return SizedBox(
      height: context.appControl.height,
      child: FilledButton.icon(
        onPressed: enabled
            ? () => unawaited(_onRun(context))
            : null,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: Text(l10n.runAction),
      ),
    );
  }

  Future<void> _onRun(BuildContext context) async {
    final cubit = context.read<RunCubit>();
    final selected = cubit.state.selectedConfiguration;
    if (selected == null) return;
    final l10n = context.l10n;

    if (cubit.hasRunning(selected.selectionKey)) {
      final choice = await showDialog<_RerunChoice>(
        context: context,
        builder: (dialogContext) => AppDialog(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(
                title: l10n.runAlreadyRunningTitle,
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
              const SizedBox(height: 12),
              Text(l10n.runAlreadyRunningMessage),
              AppDialogActions(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_RerunChoice.newInstance),
                    child: Text(l10n.runNewInstance),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_RerunChoice.restart),
                    child: Text(l10n.runRestart),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      if (!context.mounted || choice == null) return;
      if (choice == _RerunChoice.restart) {
        final session = cubit.runningSessionFor(selected.selectionKey);
        if (session != null) {
          await cubit.restartSession(session.id);
          return;
        }
      }
    }
    await cubit.runSelected();
  }
}

enum _RerunChoice { restart, newInstance }

class _StopButton extends StatelessWidget {
  const _StopButton({required this.state});

  final RunState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RunCubit>();
    final selected = state.selectedConfiguration;
    final running = selected != null && cubit.hasRunning(selected.selectionKey);
    return SizedBox(
      height: context.appControl.height,
      child: OutlinedButton.icon(
        onPressed: running
            ? () {
                final session = cubit.runningSessionFor(selected.selectionKey);
                if (session != null) {
                  unawaited(cubit.stopSession(session.id));
                }
              }
            : null,
        icon: const Icon(Icons.stop, size: 18),
        label: Text(l10n.runStop),
      ),
    );
  }
}

class _OpenLaunchJsonButton extends StatelessWidget {
  const _OpenLaunchJsonButton({
    required this.workspaceId,
    this.openLaunchJson,
  });

  final String workspaceId;
  final RunOpenLaunchJson? openLaunchJson;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      height: context.appControl.height,
      width: context.appControl.height,
      child: IconButton(
        tooltip: l10n.runOpenLaunchJson,
        onPressed: () => unawaited(_open(context)),
        icon: const Icon(Icons.settings_outlined, size: 18),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final cubit = context.read<RunCubit>();
    var path = await cubit.openLaunchJson();
    if (path == null || path.isEmpty) {
      if (cubit.folders.length > 1) {
        if (!context.mounted) return;
        final folder = await _pickFolder(context, cubit.folders);
        if (folder == null) return;
        path = await cubit.openLaunchJson(folder: folder);
      }
    }
    if (path == null || path.isEmpty) return;

    final opener = openLaunchJson;
    if (opener != null) {
      await opener(path);
      return;
    }
    if (!context.mounted) return;
    await context.read<WorkbenchEditorOpener>().openFile(workspaceId, path);
  }

  Future<WorkspaceFolder?> _pickFolder(
    BuildContext context,
    List<WorkspaceFolder> folders,
  ) {
    final l10n = context.l10n;
    return showDialog<WorkspaceFolder>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: l10n.runOpenLaunchJson,
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
            const SizedBox(height: 8),
            for (final folder in folders)
              ListTile(
                title: Text(Workspace.directoryName(folder.path)),
                subtitle: Text(folder.path, maxLines: 1),
                onTap: () => Navigator.of(dialogContext).pop(folder),
              ),
          ],
        ),
      ),
    );
  }
}

String _configLabel(
  OwnedLaunchConfiguration owned, {
  required bool showFolderLabels,
}) {
  if (!showFolderLabels) return owned.configuration.name;
  final folder = Workspace.directoryName(owned.owner.path);
  return '${owned.configuration.name} ($folder)';
}
