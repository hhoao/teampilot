import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../../services/run/launch_adapter_protocol.dart';
import '../../services/run/launch_config_store.dart';
import '../../services/run/launch_type_unavailable.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/menu/sidebar_action_menu.dart';

/// Host file-pick result for an `isAction` dropdown entry.
typedef RunActionPicker =
    Future<Map<String, Object?>?> Function(
      LaunchAdapterConfigurationEntry action,
    );

/// Opens a `launch.json` path in the editor (or creates it).
typedef RunOpenLaunchJson = Future<void> Function(String path);

/// IDEA-style title-bar Run chrome: Build · config · Run · Debug · More.
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

  /// IntelliJ-like run/debug accent (works on light and dark chrome).
  static const Color _actionGreen = Color(0xFF59A869);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RunCubit, RunState>(
      builder: (context, state) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BuildGlyph(),
            _ConfigDropdown(
              state: state,
              showFolderLabels: showFolderLabels,
              pickActionResult: pickActionResult,
            ),
            const SizedBox(width: 2),
            _RunOrStopGlyph(state: state),
            const _DebugGlyph(),
            _MoreMenu(
              workspaceId: workspaceId,
              state: state,
              openLaunchJson: openLaunchJson,
            ),
          ],
        );
      },
    );
  }
}

sealed class _DropdownEntry {
  const _DropdownEntry();
}

final class _ConfigEntry extends _DropdownEntry {
  const _ConfigEntry(this.owned);
  final OwnedLaunchConfiguration owned;
}

final class _CompoundEntry extends _DropdownEntry {
  const _CompoundEntry(this.owned);
  final OwnedLaunchCompound owned;
}

final class _ActionEntry extends _DropdownEntry {
  const _ActionEntry(this.action);
  final LaunchAdapterConfigurationEntry action;
}

final class _RecommendationEntry extends _DropdownEntry {
  const _RecommendationEntry(this.owned);
  final OwnedLaunchConfiguration owned;
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
      for (final compound in state.compounds) _CompoundEntry(compound),
      for (final recommendation in state.recommendations)
        _RecommendationEntry(recommendation),
      for (final action in state.actions)
        if (action.isAction) _ActionEntry(action),
    ];

    final selected = state.selectedConfiguration;
    final selectedCompound = state.selectedCompound;
    final label = selectedCompound != null
        ? _compoundLabel(
            context,
            selectedCompound,
            showFolderLabels: showFolderLabels,
          )
        : selected == null
        ? l10n.runSelectConfiguration
        : _entryLabel(
            context,
            selected,
            showFolderLabels: showFolderLabels,
            isSuggested: state.isRecommendation(selected),
          );

    final selectedKey =
        selectedCompound?.selectionKey ?? selected?.selectionKey;

    final specs = <SidebarActionMenuSpec>[
      for (final entry in entries)
        SidebarActionMenuSpec.item(
          value: entry,
          icon: _entryIcon(entry),
          label: _entryText(context, entry),
          enabled: _isEnabled(cubit, entry),
          selected: _isSelected(entry, selectedKey),
          tooltip: _entryTooltip(context, cubit, entry),
        ),
    ];

    final cs = Theme.of(context).colorScheme;
    return SidebarActionMenuButton(
      key: const Key('run-config-dropdown'),
      tooltip: l10n.runConfigurationTooltip,
      minWidth: 240,
      specs: specs,
      onSelected: (value) {
        if (value is _DropdownEntry) {
          unawaited(_onSelected(context, cubit, value));
        }
      },
      triggerBuilder: (context, controller) {
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.web_asset_outlined, color: cs.primary),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _entryIcon(_DropdownEntry entry) {
    return switch (entry) {
      _ConfigEntry() => Icons.play_arrow_outlined,
      _CompoundEntry() => Icons.account_tree_outlined,
      _RecommendationEntry() => Icons.auto_awesome_outlined,
      _ActionEntry() => Icons.add_circle_outline,
    };
  }

  String _entryText(BuildContext context, _DropdownEntry entry) {
    return switch (entry) {
      _ConfigEntry(:final owned) => _entryLabel(
        context,
        owned,
        showFolderLabels: showFolderLabels,
        isSuggested: false,
      ),
      _CompoundEntry(:final owned) => _compoundLabel(
        context,
        owned,
        showFolderLabels: showFolderLabels,
      ),
      _RecommendationEntry(:final owned) => _entryLabel(
        context,
        owned,
        showFolderLabels: showFolderLabels,
        isSuggested: true,
      ),
      _ActionEntry(:final action) => action.name,
    };
  }

  String? _entryTooltip(
    BuildContext context,
    RunCubit cubit,
    _DropdownEntry entry,
  ) {
    final (type, reasonCode) = switch (entry) {
      _ConfigEntry(:final owned) => (
        owned.configuration.type,
        cubit.unavailableReason(owned),
      ),
      _CompoundEntry() => ('', null),
      _RecommendationEntry(:final owned) => (
        owned.configuration.type,
        cubit.unavailableReason(owned),
      ),
      _ActionEntry(:final action) => (
        action.type,
        cubit.actionUnavailableReason(action),
      ),
    };
    final reason = localizeLaunchTypeUnavailable(
      context.l10n,
      reasonCode,
      type: type,
    );
    if (reason == null || reason.isEmpty) return null;
    return reason;
  }

  bool _isEnabled(RunCubit cubit, _DropdownEntry entry) {
    return switch (entry) {
      _ConfigEntry(:final owned) => cubit.isConfigurationAvailable(owned),
      _CompoundEntry() => true,
      _RecommendationEntry(:final owned) =>
        cubit.isConfigurationAvailable(owned),
      _ActionEntry(:final action) => cubit.isActionAvailable(action),
    };
  }

  bool _isSelected(_DropdownEntry entry, String? selectedKey) {
    if (selectedKey == null) return false;
    return switch (entry) {
      _ConfigEntry(:final owned) => owned.selectionKey == selectedKey,
      _CompoundEntry(:final owned) => owned.selectionKey == selectedKey,
      _RecommendationEntry(:final owned) => owned.selectionKey == selectedKey,
      _ActionEntry() => false,
    };
  }

  Future<void> _onSelected(
    BuildContext context,
    RunCubit cubit,
    _DropdownEntry entry,
  ) async {
    switch (entry) {
      case _ConfigEntry(:final owned):
      case _RecommendationEntry(:final owned):
        await cubit.select(owned.selectionKey);
      case _CompoundEntry(:final owned):
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

class _ToolbarGlyph extends StatelessWidget {
  const _ToolbarGlyph({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
    this.enabled = true,
    this.keyId,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final bool enabled;
  final Key? keyId;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      key: keyId,
      icon: icon,
      tooltip: tooltip,
      color: color,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

class _RunOrStopGlyph extends StatelessWidget {
  const _RunOrStopGlyph({required this.state});

  final RunState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RunCubit>();
    final compound = state.selectedCompound;
    final selected = state.selectedConfiguration;
    final hasSelection = compound != null || selected != null;

    final runningIds = compound != null
        ? cubit.runningSessionIdsForCompound(compound.compoundId)
        : const <String>[];
    final runningSelected =
        selected != null && cubit.hasRunning(selected.selectionKey);

    if (runningIds.isNotEmpty || runningSelected) {
      return _ToolbarGlyph(
        keyId: const Key('run-toolbar-stop'),
        icon: Icons.stop_rounded,
        tooltip: l10n.runStop,
        color: RunToolbar._actionGreen,
        onTap: () {
          if (compound != null && runningIds.isNotEmpty) {
            unawaited(cubit.stopCompound(runningIds));
            return;
          }
          final session = selected == null
              ? null
              : cubit.runningSessionFor(selected.selectionKey);
          if (session != null) {
            unawaited(cubit.stopSession(session.id));
          }
        },
      );
    }

    return _ToolbarGlyph(
      keyId: const Key('run-toolbar-run'),
      icon: Icons.play_arrow,
      tooltip: l10n.runAction,
      color: RunToolbar._actionGreen,
      enabled: hasSelection,
      onTap: hasSelection ? () => unawaited(_onRun(context)) : null,
    );
  }

  Future<void> _onRun(BuildContext context) async {
    final cubit = context.read<RunCubit>();
    final compound = cubit.state.selectedCompound;
    if (compound != null) {
      await cubit.runCompound(compound);
      return;
    }

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

class _BuildGlyph extends StatelessWidget {
  const _BuildGlyph();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _ToolbarGlyph(
      keyId: const Key('run-toolbar-build'),
      icon: Icons.build_outlined,
      tooltip: l10n.runBuildUnavailable,
      enabled: false,
    );
  }
}

class _DebugGlyph extends StatelessWidget {
  const _DebugGlyph();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _ToolbarGlyph(
      keyId: const Key('run-toolbar-debug'),
      icon: Icons.bug_report_outlined,
      tooltip: l10n.runDebugUnavailable,
      color: RunToolbar._actionGreen,
      enabled: false,
    );
  }
}

enum _MoreAction {
  openLaunchJson,
  refreshDiscover,
  acceptRecommendation,
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.workspaceId,
    required this.state,
    this.openLaunchJson,
  });

  final String workspaceId;
  final RunState state;
  final RunOpenLaunchJson? openLaunchJson;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RunCubit>();
    final selected = state.selectedConfiguration;
    final canAccept = selected != null && state.isRecommendation(selected);
    final choiceOptions = state.options
        .where(
          (o) => o.type == LaunchOptionType.choice && o.choices.isNotEmpty,
        )
        .toList();

    final specs = <SidebarActionMenuSpec>[
      SidebarActionMenuSpec.item(
        value: _MoreAction.openLaunchJson,
        icon: Icons.description_outlined,
        label: l10n.runOpenLaunchJson,
      ),
      SidebarActionMenuSpec.item(
        value: _MoreAction.refreshDiscover,
        icon: Icons.refresh,
        label: l10n.runRefreshDiscover,
      ),
      if (canAccept)
        SidebarActionMenuSpec.item(
          value: _MoreAction.acceptRecommendation,
          icon: Icons.check_circle_outline,
          label: l10n.runAcceptRecommendation,
        ),
      for (final option in choiceOptions) ...[
        const SidebarActionMenuSpec.divider(),
        SidebarActionMenuSpec.item(
          icon: Icons.tune,
          label: option.label,
          enabled: false,
        ),
        for (final choice in option.choices)
          SidebarActionMenuSpec.item(
            value: MapEntry(option.id, choice.value),
            icon: Icons.circle_outlined,
            label: choice.label,
            selected:
                (state.optionValues[option.id] ?? option.value)?.toString() ==
                choice.value,
          ),
      ],
    ];

    final cs = Theme.of(context).colorScheme;
    return SidebarActionMenuButton(
      key: const Key('run-toolbar-more'),
      tooltip: l10n.runMoreActions,
      specs: specs,
      onSelected: (value) {
        if (value is _MoreAction) {
          unawaited(_onAction(context, value));
          return;
        }
        if (value is MapEntry<String, String>) {
          cubit.setOption(value.key, value.value);
        }
      },
      triggerBuilder: (context, controller) {
        return AppIconButton(
          icon: Icons.more_vert,
          backgroundColor: cs.onSurface.withValues(alpha: 0.06),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }

  Future<void> _onAction(BuildContext context, _MoreAction action) async {
    final cubit = context.read<RunCubit>();
    switch (action) {
      case _MoreAction.openLaunchJson:
        await _openLaunchJson(context);
      case _MoreAction.refreshDiscover:
        await cubit.refreshDiscover();
      case _MoreAction.acceptRecommendation:
        final selected = cubit.state.selectedConfiguration;
        if (selected != null) {
          await cubit.acceptRecommendation(selected);
        }
    }
  }

  Future<void> _openLaunchJson(BuildContext context) async {
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

String _compoundLabel(
  BuildContext context,
  OwnedLaunchCompound owned, {
  required bool showFolderLabels,
}) {
  final base = context.l10n.runCompoundConfiguration(owned.compound.name);
  if (!showFolderLabels) return base;
  final folder = Workspace.directoryName(owned.owner.path);
  return '$base ($folder)';
}

String _entryLabel(
  BuildContext context,
  OwnedLaunchConfiguration owned, {
  required bool showFolderLabels,
  required bool isSuggested,
}) {
  final base = _configLabel(owned, showFolderLabels: showFolderLabels);
  if (!isSuggested) return base;
  return context.l10n.runSuggestedConfiguration(base);
}

String _configLabel(
  OwnedLaunchConfiguration owned, {
  required bool showFolderLabels,
}) {
  if (!showFolderLabels) return owned.configuration.name;
  final folder = Workspace.directoryName(owned.owner.path);
  return '${owned.configuration.name} ($folder)';
}
