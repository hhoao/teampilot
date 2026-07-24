import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/board_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../models/team_config.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/ui/app_keys.dart';
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
    this.isPersonalContext = false,
    this.team,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;
  final bool dismissDrawerOnAction;
  final bool isPersonalContext;
  final TeamProfile? team;
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
  MailboxCubit? _mailboxCubit;
  BoardCubit? _boardCubit;
  bool _uiPollAttached = false;

  RightToolsToolPreferences get _toolPreferences =>
      RightToolsToolPreferences.from(widget.preferences);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chatCubit = context.read<ChatCubit>();
    final presenceCubit = context.read<MemberPresenceCubit>();
    final shouldAttach = TickerMode.valuesOf(context).enabled;

    MailboxCubit? mailboxCubit;
    BoardCubit? boardCubit;
    try {
      mailboxCubit = context.read<MailboxCubit>();
      boardCubit = context.read<BoardCubit>();
    } on Object {
      mailboxCubit = null;
      boardCubit = null;
    }

    if (!identical(_chatCubit, chatCubit)) {
      if (_uiPollAttached) {
        _detachUiPoll();
      }
      _chatCubit = chatCubit;
      _presenceCubit = presenceCubit;
      _mailboxCubit = mailboxCubit;
      _boardCubit = boardCubit;
    }

    if (shouldAttach && !_uiPollAttached) {
      presenceCubit.attachPresenceUi(this);
      _mailboxCubit?.attachUi(widget._toolsScopeId, this);
      _boardCubit?.attachUi(widget._toolsScopeId, this);
      _uiPollAttached = true;
    } else if (!shouldAttach && _uiPollAttached) {
      _detachUiPoll();
    }
  }

  void _detachUiPoll() {
    _presenceCubit?.detachPresenceUi(this);
    _mailboxCubit?.detachUi(this);
    _boardCubit?.detachUi(this);
    _uiPollAttached = false;
  }

  @override
  void dispose() {
    if (_uiPollAttached) {
      _detachUiPoll();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.preferences.rightToolsVisible ||
        !_toolPreferences.needsLifecycleHost) {
      return const SizedBox.shrink();
    }
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
        isPersonalContext: widget.isPersonalContext,
        team: widget.team,
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
    required this.isPersonalContext,
    required this.team,
    required this.dismissDrawerOnAction,
  });

  final Key panelKey;
  final RightToolsToolPreferences toolPreferences;
  final String cwd;
  final String workspaceId;
  final String toolsScopeId;
  final bool isPersonalContext;
  final TeamProfile? team;
  final bool dismissDrawerOnAction;

  @override
  Widget build(BuildContext context) {
    final lifecycle = RightToolsLifecycle.of(context);
    final scope = lifecycle.scope;
    final tools = scope.tools;
    final fileTreeCubit = lifecycle.fileTreeCubit;

    if (scope.isReady && tools != null && fileTreeCubit != null) {
      return RightToolsWorkingTurnListener(
        onTurnEnd: lifecycle.pokeOnTurnEnd,
        child: RightToolsPresenceTeamSync(
          team: team,
          child: Container(
            key: panelKey,
            child: RightToolsToolViews(
              preferences: toolPreferences,
              cwd: cwd,
              workspaceId: workspaceId,
              toolsScopeId: toolsScopeId,
              isPersonalContext: isPersonalContext,
              team: team,
              dismissDrawerOnAction: dismissDrawerOnAction,
              fileTreeCubit: fileTreeCubit,
              workContext: tools.context,
              scope: scope,
            ),
          ),
        ),
      );
    }

    if (!scope.resolving && scope.resolveError != null && tools == null) {
      return _RightToolsResolveError(panelKey: panelKey);
    }

    return const SizedBox.shrink();
  }
}

class _RightToolsResolveError extends StatelessWidget {
  const _RightToolsResolveError({required this.panelKey});

  final Key panelKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final styles = TpTextStyles.of(context);
    return Container(
      key: panelKey,
      padding: const EdgeInsets.all(16),
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.workspaceToolsResolveFailed,
            textAlign: TextAlign.center,
            style: styles.smSemibold,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.workspaceToolsResolveFailedHint,
            textAlign: TextAlign.center,
            style: styles.smColored(theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => context.read<WorkspaceToolsScopeCubit>().retry(),
            child: Text(l10n.sessionRetryButton),
          ),
        ],
      ),
    );
  }
}
