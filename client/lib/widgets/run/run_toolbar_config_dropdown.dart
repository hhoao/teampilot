import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/workspace.dart';
import '../../services/run/launch_adapter_protocol.dart';
import '../../services/run/launch_config_store.dart';
import '../../services/run/launch_type_unavailable.dart';
import 'package:shared_ui/shared_ui.dart';
import 'run_config_editor_dialog.dart';
import 'run_configurations_dialog.dart';

/// Host file-pick result for an `isAction` dropdown entry.
typedef RunActionPicker =
    Future<Map<String, Object?>?> Function(
      LaunchAdapterConfigurationEntry action,
    );

/// Config dropdown for RunToolbar: select, Edit/Delete, Add configuration.
class RunToolbarConfigDropdown extends StatelessWidget {
  const RunToolbarConfigDropdown({
    required this.state,
    required this.showFolderLabels,
    required this.workspaceId,
    this.pickActionResult,
    super.key,
  });

  final RunState state;
  final bool showFolderLabels;
  final String workspaceId;
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

    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.runConfigurationTooltip,
      child: TpActionMenuIconAnchor(
        key: const Key('run-config-dropdown'),
        minWidth: 280,
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
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TpTextStyles.of(context).sm,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          );
        },
        buildMenuChildren: (menuContext, controller) {
          return [
            for (final entry in entries)
              TpActionMenuItem(
                icon: _entryIcon(entry),
                label: _entryText(menuContext, entry),
                enabled: _isEnabled(cubit, entry),
                tooltip: _entryTooltip(menuContext, cubit, entry),
                menuController: controller,
                trailing: _entryTrailing(
                  context,
                  controller: controller,
                  cubit: cubit,
                  entry: entry,
                  selected: _isSelected(entry, selectedKey),
                ),
                onTap: _isEnabled(cubit, entry)
                    ? () => unawaited(_onSelected(context, cubit, entry))
                    : null,
              ),
            const TpActionMenuDivider(),
            TpActionMenuItem(
              key: const Key('run-config-add-configuration'),
              icon: Icons.add_rounded,
              label: l10n.runAddConfiguration,
              menuController: controller,
              onTap: () {
                unawaited(
                  createRunConfiguration(context, workspaceId: workspaceId),
                );
              },
            ),
            TpActionMenuItem(
              key: const Key('run-config-add'),
              icon: Icons.settings_outlined,
              label: l10n.runConfigureLaunchItems,
              menuController: controller,
              onTap: () {
                unawaited(
                  showRunConfigurationsPanelDialog(
                    context,
                    workspaceId: workspaceId,
                  ),
                );
              },
            ),
          ];
        },
      ),
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
      _RecommendationEntry(:final owned) => cubit.isConfigurationAvailable(
        owned,
      ),
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

  Widget? _entryTrailing(
    BuildContext context, {
    required TpActionMenuController controller,
    required RunCubit cubit,
    required _DropdownEntry entry,
    required bool selected,
  }) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final check = selected
        ? Icon(
            Icons.check,
            size: context.tpIconSizes.md,
            color: cs.onSurface.withValues(alpha: 0.7),
          )
        : null;

    final OwnedLaunchConfiguration? editable = switch (entry) {
      _ConfigEntry(:final owned) => owned,
      _RecommendationEntry(:final owned) => owned,
      _CompoundEntry() || _ActionEntry() => null,
    };
    if (editable == null) {
      return check;
    }

    final showDelete = entry is _ConfigEntry;
    return GestureDetector(
      // Absorb row-select taps on the trailing hit targets.
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (check != null) ...[check, const SizedBox(width: 4)],
          TpIconButton(
            key: Key('run-config-edit-${editable.selectionKey}'),
            icon: Icons.edit_outlined,
            tooltip: l10n.edit,
            size: TpIconButton.kCompactSize,
            compact: true,
            onTap: () {
              controller.close();
              unawaited(
                showRunConfigEditorDialog(
                  context,
                  workspaceId: workspaceId,
                  initial: editable,
                ),
              );
            },
          ),
          if (showDelete)
            TpIconButton(
              key: Key('run-config-delete-${editable.selectionKey}'),
              icon: Icons.delete_outline,
              tooltip: l10n.runDeleteConfiguration,
              size: TpIconButton.kCompactSize,
              compact: true,
              onTap: () {
                controller.close();
                unawaited(_confirmDelete(context, cubit, editable));
              },
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RunCubit cubit,
    OwnedLaunchConfiguration owned,
  ) async {
    final l10n = context.l10n;
    final running = cubit.hasRunning(owned.selectionKey);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return TpDialog(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(
                title: l10n.runDeleteConfiguration,
                onClose: () => Navigator.of(ctx).pop(false),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.runDeleteConfigurationConfirm(
                  owned.configuration.name.isEmpty
                      ? owned.configId
                      : owned.configuration.name,
                ),
              ),
              TpDialogActions(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(
                      running
                          ? l10n.runStopAndDelete
                          : l10n.runDeleteConfiguration,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    await cubit.deleteConfiguration(owned);
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
