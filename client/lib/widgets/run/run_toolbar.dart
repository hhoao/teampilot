import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/run_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/run/launch_adapter_protocol.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import 'run_config_editor_dialog.dart';
import 'run_toolbar_config_dropdown.dart';

export 'run_toolbar_config_dropdown.dart' show RunActionPicker;

/// IDEA-style title-bar Run chrome: config · options · Run · kinds-gated Debug/Build.
class RunToolbar extends StatelessWidget {
  const RunToolbar({
    required this.workspaceId,
    this.showFolderLabels = false,
    this.pickActionResult,
    super.key,
  });

  final String workspaceId;
  final bool showFolderLabels;

  /// Host UI for `isAction` items. When null, action selection is a no-op.
  final RunActionPicker? pickActionResult;

  /// IntelliJ-like run/debug accent (works on light and dark chrome).
  static const Color _actionGreen = Color(0xFF59A869);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RunCubit, RunState>(
      builder: (context, state) {
        final cubit = context.read<RunCubit>();
        final kinds = _kindsForSelection(cubit, state);
        final choiceOptions = state.options
            .where(
              (o) =>
                  o.type == LaunchOptionType.choice && o.choices.isNotEmpty,
            )
            .toList();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RunToolbarConfigDropdown(
              state: state,
              showFolderLabels: showFolderLabels,
              workspaceId: workspaceId,
              pickActionResult: pickActionResult,
            ),
            for (final option in choiceOptions) ...[
              const SizedBox(width: 2),
              _ChoiceOptionSelector(option: option, state: state),
            ],
            const SizedBox(width: 2),
            _RunOrStopGlyph(state: state, workspaceId: workspaceId),
            if (kinds.contains('debug')) const _DebugGlyph(),
            if (kinds.contains('build')) const _BuildGlyph(),
          ],
        );
      },
    );
  }
}

/// Launch-type kinds for the selected configuration (empty when none selected).
List<String> _kindsForSelection(RunCubit cubit, RunState state) {
  final selected = state.selectedConfiguration;
  if (selected == null) return const [];
  return cubit.kindsForType(selected.configuration.type);
}

class _ChoiceOptionSelector extends StatelessWidget {
  const _ChoiceOptionSelector({
    required this.option,
    required this.state,
  });

  final LaunchOption option;
  final RunState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RunCubit>();
    final current =
        (state.optionValues[option.id] ?? option.value)?.toString();
    final selectedLabel = option.choices
        .where((choice) => choice.value == current)
        .map((choice) => choice.label)
        .firstOrNull;
    final label = selectedLabel ?? option.label;

    final specs = <SidebarActionMenuSpec>[
      for (final choice in option.choices)
        SidebarActionMenuSpec.item(
          value: choice.value,
          icon: Icons.circle_outlined,
          label: choice.label,
          selected: choice.value == current,
        ),
    ];

    final cs = Theme.of(context).colorScheme;
    return SidebarActionMenuButton(
      key: Key('run-toolbar-option-${option.id}'),
      tooltip: option.label,
      minWidth: 120,
      specs: specs,
      onSelected: (value) {
        if (value is String) {
          cubit.setOption(option.id, value);
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.of(context).bodyColored(cs.onSurface),
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
  const _RunOrStopGlyph({
    required this.state,
    required this.workspaceId,
  });

  final RunState state;
  final String workspaceId;

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
    if (!context.mounted) return;
    await _offerEditOnSchemaFailure(context, cubit);
  }

  Future<void> _offerEditOnSchemaFailure(
    BuildContext context,
    RunCubit cubit,
  ) async {
    final error = cubit.state.errorMessage;
    final selected = cubit.state.selectedConfiguration;
    if (error == null || selected == null || !cubit.selectedHasSchemaErrors) {
      return;
    }

    final l10n = context.l10n;
    final edit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: l10n.runEditConfigurations,
              onClose: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(height: 12),
            Text(error),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.runEditConfigurations),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || edit != true) return;
    await showRunConfigEditorDialog(
      context,
      workspaceId: workspaceId,
      initial: selected,
    );
  }
}

enum _RerunChoice { restart, newInstance }

/// Shown only when selected type kinds include `build` (execution deferred).
class _BuildGlyph extends StatelessWidget {
  const _BuildGlyph();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _ToolbarGlyph(
      keyId: const Key('run-toolbar-build'),
      icon: Icons.build_outlined,
      tooltip: l10n.runBuild,
      onTap: () {},
    );
  }
}

/// Shown only when selected type kinds include `debug` (execution deferred).
class _DebugGlyph extends StatelessWidget {
  const _DebugGlyph();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _ToolbarGlyph(
      keyId: const Key('run-toolbar-debug'),
      icon: Icons.bug_report_outlined,
      tooltip: l10n.runDebug,
      color: RunToolbar._actionGreen,
      onTap: () {},
    );
  }
}
