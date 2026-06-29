import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../utils/app_keys.dart';
import 'right_tools_lifecycle.dart';
import 'right_tools_tool_preferences.dart';
import 'right_tools_tool_views.dart';

class RightToolsPanel extends StatefulWidget {
  const RightToolsPanel({
    required this.cwd,
    required this.workspaceId,
    this.toolsScopeId,
    this.additionalPaths = const [],
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    this.dismissDrawerOnAction = false,
    this.isPersonalWorkspace = false,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;
  final bool dismissDrawerOnAction;
  final bool isPersonalWorkspace;
  final String cwd;
  final List<String> additionalPaths;
  final String workspaceId;
  final String? toolsScopeId;

  String get _toolsScopeId => toolsScopeId ?? workspaceId;

  @override
  State<RightToolsPanel> createState() => _RightToolsPanelState();
}

class _RightToolsPanelState extends State<RightToolsPanel> {
  ChatCubit? _chatCubit;
  MemberPresenceCubit? _presenceCubit;
  bool _presenceAttached = false;

  RightToolsToolPreferences get _toolPreferences =>
      RightToolsToolPreferences.from(widget.preferences);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatCubit = context.read<ChatCubit>();
    final presenceCubit = context.read<MemberPresenceCubit>();
    final shouldAttach = TickerMode.valuesOf(context).enabled;

    if (!identical(_chatCubit, chatCubit)) {
      if (_presenceAttached) {
        _presenceCubit?.detachPresenceUi(this);
        _presenceAttached = false;
      }
      _chatCubit = chatCubit;
      _presenceCubit = presenceCubit;
    }

    if (shouldAttach && !_presenceAttached) {
      presenceCubit.attachPresenceUi(this);
      _presenceAttached = true;
    } else if (!shouldAttach && _presenceAttached) {
      presenceCubit.detachPresenceUi(this);
      _presenceAttached = false;
    }
  }

  @override
  void dispose() {
    if (_presenceAttached) {
      _presenceCubit?.detachPresenceUi(this);
      _presenceAttached = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RightToolsLifecycleHost(
      cwd: widget.cwd,
      additionalPaths: widget.additionalPaths,
      workspaceId: widget.workspaceId,
      preferences: _toolPreferences,
      child: _RightToolsPanelBody(
        panelKey: widget.panelKey,
        toolPreferences: _toolPreferences,
        cwd: widget.cwd,
        workspaceId: widget.workspaceId,
        toolsScopeId: widget._toolsScopeId,
        isPersonalWorkspace: widget.isPersonalWorkspace,
        dismissDrawerOnAction: widget.dismissDrawerOnAction,
      ),
    );
  }
}

class _RightToolsPanelBody extends StatelessWidget {
  const _RightToolsPanelBody({
    required this.panelKey,
    required this.toolPreferences,
    required this.cwd,
    required this.workspaceId,
    required this.toolsScopeId,
    required this.isPersonalWorkspace,
    required this.dismissDrawerOnAction,
  });

  final Key panelKey;
  final RightToolsToolPreferences toolPreferences;
  final String cwd;
  final String workspaceId;
  final String toolsScopeId;
  final bool isPersonalWorkspace;
  final bool dismissDrawerOnAction;

  @override
  Widget build(BuildContext context) {
    final lifecycle = RightToolsLifecycle.of(context);
    final scope = lifecycle.scope;
    final tools = scope.tools;
    final fileTreeCubit = lifecycle.fileTreeCubit;

    if (!scope.isReady || tools == null || fileTreeCubit == null) {
      return const SizedBox.shrink();
    }

    return RightToolsWorkingTurnListener(
      onTurnEnd: lifecycle.pokeOnTurnEnd,
      child: RightToolsPresenceTeamSync(
        isPersonalWorkspace: isPersonalWorkspace,
        child: Container(
          key: panelKey,
          child: RightToolsToolViews(
            preferences: toolPreferences,
            cwd: cwd,
            workspaceId: workspaceId,
            toolsScopeId: toolsScopeId,
            isPersonalWorkspace: isPersonalWorkspace,
            dismissDrawerOnAction: dismissDrawerOnAction,
            fileTreeCubit: fileTreeCubit,
            workContext: tools.context,
            scope: scope,
          ),
        ),
      ),
    );
  }
}
