import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../widgets/resizable_split_view.dart';
import '../../widgets/workspace_terminal_panel.dart';

class WorkspaceShellMainWithTerminal extends StatelessWidget {
  const WorkspaceShellMainWithTerminal({super.key, 
    required this.preferences,
    required this.child,
    required this.rightTools,
    required this.onRightToolsWidthChanged,
    this.workspaceTerminalWorkingDirectory,
    this.workspaceWorkspaceId,
  });

  final LayoutPreferences preferences;
  final Widget child;
  final Widget? rightTools;
  final ValueChanged<double>? onRightToolsWidthChanged;
  final String? workspaceTerminalWorkingDirectory;
  final String? workspaceWorkspaceId;

  @override
  Widget build(BuildContext context) {
    return WorkspaceShellBody(
      preferences: preferences,
      rightTools: rightTools,
      onRightToolsWidthChanged: onRightToolsWidthChanged,
      child: WorkspaceShellCenterColumnWithTerminal(
        workspaceTerminalWorkingDirectory: workspaceTerminalWorkingDirectory,
        workspaceWorkspaceId: workspaceWorkspaceId,
        child: child,
      ),
    );
  }
}

/// Bottom terminal under the center workbench only (not under right tools).
class WorkspaceShellCenterColumnWithTerminal extends StatelessWidget {
  const WorkspaceShellCenterColumnWithTerminal({super.key, 
    required this.child,
    this.workspaceTerminalWorkingDirectory,
    this.workspaceWorkspaceId,
  });

  final Widget child;
  final String? workspaceTerminalWorkingDirectory;
  final String? workspaceWorkspaceId;

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
        final workspaceId = workspaceWorkspaceId?.trim() ?? '';
        // Key by the registry-group identity only — NOT cwd. Keeping cwd out of
        // the key means a same-workspace cwd change keeps the same panel State, so
        // the cwd update flows through didUpdateWidget -> _syncActiveEntryCwd
        // (which updates the active entry + reconnects). Including cwd here would
        // recreate the State, whose bootstrap re-attaches existing terminals
        // without updating their cwd, stranding them at the old path.
        final terminalGroupId = workspaceId.isNotEmpty ? workspaceId : cwd;
        return ResizableSplitView(
          axis: Axis.vertical,
          primaryAtEnd: true,
          first: child,
          second: WorkspaceTerminalPanel(
            key: ValueKey('workspace-terminal-$terminalGroupId'),
            workspaceId: terminalGroupId,
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

class WorkspaceShellBody extends StatefulWidget {
  const WorkspaceShellBody({super.key,
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
  State<WorkspaceShellBody> createState() => _WorkspaceShellBodyState();
}

class _WorkspaceShellBodyState extends State<WorkspaceShellBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool _panelVisible = false;

  bool get _hasPanel => widget.rightTools != null;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: 250.ms,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.1, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _panelVisible = _hasPanel && widget.preferences.rightToolsVisible;
    if (_panelVisible) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(WorkspaceShellBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visible = _hasPanel && widget.preferences.rightToolsVisible;
    if (visible != _panelVisible) {
      _panelVisible = visible;
      if (visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When the panel is not visible and the dismiss animation has finished,
    // render only the center child — nothing else in the tree.
    if (!_panelVisible && _controller.isDismissed) {
      return widget.child;
    }

    final rightWidth = widget.preferences.rightToolsWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const minCenter = 150.0;
        final minTools = LayoutPreferences.minRightToolsWidth;
        // Build the split view unconditionally while animating so the panel
        // widget stays alive during the exit transition.
        final splitView = ResizableSplitView(
          first: widget.child,
          second: widget.rightTools!,
          initialPrimarySize: (maxW - rightWidth).clamp(
            minCenter,
            maxW - minTools,
          ),
          minPrimarySize: minCenter,
          minSecondarySize: minTools,
          maxPrimarySize: (maxW - minTools).clamp(minCenter, maxW),
          onPrimarySizeChanged: (leftWidth) {
            widget.onRightToolsWidthChanged?.call(maxW - leftWidth);
          },
        );

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: child,
              ),
            );
          },
          child: splitView,
        );
      },
    );
  }
}
