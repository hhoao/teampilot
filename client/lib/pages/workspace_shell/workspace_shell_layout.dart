import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../widgets/resizable_split_view.dart';
import '../../widgets/workspace_terminal_panel.dart';

class WorkspaceShellMainWithTerminal extends StatelessWidget {
  const WorkspaceShellMainWithTerminal({
    required this.preferences,
    required this.child,
    required this.rightTools,
    required this.onRightToolsWidthChanged,
    required this.childAnimationKey,
    this.workspaceTerminalWorkingDirectory,
    this.workspaceProjectId,
  });

  final LayoutPreferences preferences;
  final Widget child;
  final Widget? rightTools;
  final ValueChanged<double>? onRightToolsWidthChanged;
  final Key? childAnimationKey;
  final String? workspaceTerminalWorkingDirectory;
  final String? workspaceProjectId;

  @override
  Widget build(BuildContext context) {
    final animatedChild = childAnimationKey == null
        ? child
        : WorkspaceShellFadeSlideIn(key: childAnimationKey, child: child);

    return WorkspaceShellBody(
      preferences: preferences,
      rightTools: rightTools,
      onRightToolsWidthChanged: onRightToolsWidthChanged,
      child: WorkspaceShellCenterColumnWithTerminal(
        workspaceTerminalWorkingDirectory: workspaceTerminalWorkingDirectory,
        workspaceProjectId: workspaceProjectId,
        child: animatedChild,
      ),
    );
  }
}

/// Bottom terminal under the center workbench only (not under right tools).
class WorkspaceShellCenterColumnWithTerminal extends StatelessWidget {
  const WorkspaceShellCenterColumnWithTerminal({
    required this.child,
    this.workspaceTerminalWorkingDirectory,
    this.workspaceProjectId,
  });

  final Widget child;
  final String? workspaceTerminalWorkingDirectory;
  final String? workspaceProjectId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LayoutCubit, LayoutState>(
      buildWhen: (previous, next) =>
          previous.preferences.workspaceTerminalVisible !=
              next.preferences.workspaceTerminalVisible ||
          previous.preferences.workspaceTerminalHeight !=
              next.preferences.workspaceTerminalHeight,
      builder: (context, layoutState) {
        final prefs = layoutState.preferences;
        if (!prefs.workspaceTerminalVisible) {
          return child;
        }
        final scoped = workspaceTerminalWorkingDirectory?.trim() ?? '';
        final cwd = scoped.isNotEmpty
            ? scoped
            : context.watch<ChatCubit>().activeTabWorkingDirectory;
        final terminalHeight = prefs.workspaceTerminalHeight.clamp(
          LayoutPreferences.minWorkspaceTerminalHeight,
          LayoutPreferences.maxWorkspaceTerminalHeight,
        );
        final projectId = workspaceProjectId?.trim() ?? '';
        return ResizableSplitView(
          axis: Axis.vertical,
          primaryAtEnd: true,
          first: child,
          second: WorkspaceTerminalPanel(
            key: ValueKey('workspace-terminal-$projectId-$cwd'),
            projectId: projectId.isNotEmpty ? projectId : cwd,
            workingDirectory: cwd,
          ),
          initialPrimarySize: terminalHeight,
          minPrimarySize: LayoutPreferences.minWorkspaceTerminalHeight,
          minSecondarySize: LayoutPreferences.minWorkbenchMainWidth,
          maxPrimarySize: LayoutPreferences.maxWorkspaceTerminalHeight,
          onPrimarySizeChanged: (height) {
            context.read<LayoutCubit>().setWorkspaceTerminalHeight(height);
          },
        );
      },
    );
  }
}

class WorkspaceShellBody extends StatelessWidget {
  const WorkspaceShellBody({
    required this.preferences,
    required this.child,
    required this.rightTools,
    required this.onRightToolsWidthChanged,
  });

  final LayoutPreferences preferences;
  final Widget child;
  final Widget? rightTools;
  final ValueChanged<double>? onRightToolsWidthChanged;

  @override
  Widget build(BuildContext context) {
    if (rightTools == null || !preferences.rightToolsVisible) {
      return child;
    }
    if (preferences.toolPlacement == ToolPanelPlacement.bottom) {
      final toolsHeight = preferences.bottomToolsHeight.clamp(
        LayoutPreferences.minBottomToolsHeight,
        LayoutPreferences.maxBottomToolsHeight,
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          const dividerHeight = 2.0;
          final maxH = constraints.maxHeight;
          final minTop =
              (maxH - LayoutPreferences.maxBottomToolsHeight - dividerHeight)
                  .clamp(0.0, maxH);
          final maxTop =
              (maxH - LayoutPreferences.minBottomToolsHeight - dividerHeight)
                  .clamp(0.0, maxH);
          final initialTop = (maxH - toolsHeight - dividerHeight).clamp(
            minTop <= maxTop ? minTop : maxTop,
            maxTop >= minTop ? maxTop : minTop,
          );
          return ResizableSplitView(
            axis: Axis.vertical,
            first: child,
            second: rightTools!,
            initialPrimarySize: initialTop,
            minPrimarySize: minTop,
            minSecondarySize: LayoutPreferences.minBottomToolsHeight,
            maxPrimarySize: maxTop,
            dividerThickness: dividerHeight,
            onPrimarySizeChanged: (topHeight) {
              final bottomHeight = maxH - topHeight - dividerHeight;
              context.read<LayoutCubit>().setBottomToolsHeight(bottomHeight);
            },
          );
        },
      );
    }
    final rightWidth = preferences.rightToolsWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const minCenter = 150.0;
        final minTools = LayoutPreferences.minRightToolsWidth;
        return ResizableSplitView(
          first: child,
          second: rightTools!,
          initialPrimarySize: (maxW - rightWidth).clamp(
            minCenter,
            maxW - minTools,
          ),
          minPrimarySize: minCenter,
          minSecondarySize: minTools,
          maxPrimarySize: (maxW - minTools).clamp(minCenter, maxW),
          onPrimarySizeChanged: (leftWidth) {
            onRightToolsWidthChanged?.call(maxW - leftWidth);
          },
        );
      },
    );
  }
}

class WorkspaceShellFadeSlideIn extends StatelessWidget {
  const WorkspaceShellFadeSlideIn({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        final opacity = Curves.easeOut.transform(value);
        return Opacity(
          opacity: opacity,
          child: FractionalTranslation(
            translation: Offset(0.025 * (1 - value), 0),
            child: child,
          ),
        );
      },
    );
  }
}
