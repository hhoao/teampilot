import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../models/member_presence.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../pages/chat/agent_permission_attention_banner.dart';
import '../../pages/chat/compose_stop_visibility.dart';
import '../../pages/chat/session_follow_up_compose_submit.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/turn_interrupt_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/follow_up/follow_up_queue.dart';
import '../../services/session/history_seat_key.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team/team_member_naming.dart';
import 'follow_up_queue_strip.dart';

/// Finder key for the terminal follow-up compose bar.
const Key kTerminalFollowUpComposeKey = ValueKey('terminal-follow-up-compose');

bool shouldShowTerminalFollowUpCompose({
  required bool memberWorking,
  required FollowUpQueue queue,
}) =>
    memberWorking || queue.items.isNotEmpty;

/// Compact follow-up strip + field docked above the terminal bottom.
class TerminalFollowUpCompose extends StatefulWidget {
  const TerminalFollowUpCompose({
    required this.session,
    required this.selectedMemberId,
    required this.memberWorking,
    required this.supportsTurnInterrupt,
    required this.permissionWaiting,
    this.team,
    super.key,
  });

  final AppSession session;
  final String selectedMemberId;
  final TeamProfile? team;
  final bool memberWorking;
  final bool supportsTurnInterrupt;
  final bool permissionWaiting;

  @override
  State<TerminalFollowUpCompose> createState() =>
      _TerminalFollowUpComposeState();
}

class _TerminalFollowUpComposeState extends State<TerminalFollowUpCompose> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  var _submitting = false;

  String get _shellMemberId => shellMemberIdForHistory(
    sessionId: widget.session.sessionId,
    selectedMemberId: widget.selectedMemberId,
  );

  String get _followUpSeatKey =>
      followUpSeatKey(widget.session.sessionId, _shellMemberId);

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _notifyFollowUpMemberWorking(ChatCubit chat) {
    chat.notifyFollowUpMemberWorking(
      widget.session.sessionId,
      _shellMemberId,
      working: chat.isMemberWorking(widget.session.sessionId, _shellMemberId),
    );
  }

  Future<void> _handleComposeStop(ChatCubit chat) async {
    await chat.interruptSelectedMemberTurn(
      sessionId: widget.session.sessionId,
      memberId: _shellMemberId,
    );
    chat.pauseFollowUpQueue(widget.session.sessionId, _shellMemberId);
  }

  Future<void> _handleSubmit(ChatCubit chat) async {
    if (_submitting || widget.permissionWaiting) return;
    final text = _controller.text.trim();
    final action = resolveHistoryComposeSubmitAction(
      permissionWaiting: widget.permissionWaiting,
      memberWorking: widget.memberWorking,
      trimmedText: text,
      supportsTurnInterrupt: widget.supportsTurnInterrupt,
    );

    var delivered = false;
    dispatchHistoryComposeSubmit(
      action: action,
      text: text,
      onEnqueue: (queued) {
        chat.followUpQueue.enqueue(_followUpSeatKey, queued);
        _controller.clear();
        _notifyFollowUpMemberWorking(chat);
        if (mounted) setState(() {});
      },
      onDeliver: (_) => delivered = true,
    );
    if (!delivered) return;

    setState(() => _submitting = true);
    try {
      await chat.submitSessionOperatorMessage(
        sessionId: widget.session.sessionId,
        memberId: _shellMemberId,
        message: text,
        preserveWorkbenchView: true,
      );
      if (!mounted) return;
      _controller.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.read<ChatCubit>();

    return StreamBuilder<FollowUpQueue>(
      stream: chat.followUpQueue.watch(_followUpSeatKey),
      initialData: chat.followUpQueue.queueFor(_followUpSeatKey),
      builder: (context, snapshot) {
        final queue = snapshot.data ?? const FollowUpQueue();
        if (!shouldShowTerminalFollowUpCompose(
          memberWorking: widget.memberWorking,
          queue: queue,
        )) {
          return const SizedBox.shrink();
        }

        final spacing = context.tpSpacing;
        final cs = Theme.of(context).colorScheme;
        final l10n = context.l10n;
        final composeTextEmpty = _controller.text.trim().isEmpty;
        final showStop = shouldShowComposeStop(
          memberWorking: widget.memberWorking,
          supportsTurnInterrupt: widget.supportsTurnInterrupt,
          composeTextEmpty: composeTextEmpty,
        );
        final canSubmit =
            !widget.permissionWaiting &&
            composeTextEmpty == false &&
            !_submitting;

        return Material(
          key: kTerminalFollowUpComposeKey,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.94),
          child: Padding(
            padding: EdgeInsets.fromLTRB(spacing.md, spacing.sm, spacing.md, spacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FollowUpQueueStrip(
                  queue: queue,
                  onDelete: (id) => chat.followUpQueue.remove(_followUpSeatKey, id),
                  onEdit: (id, content) =>
                      chat.followUpQueue.edit(_followUpSeatKey, id, content),
                  onMoveUp: (id) =>
                      chat.followUpQueue.moveUp(_followUpSeatKey, id),
                  onResume: () => unawaited(
                    chat.resumeFollowUpQueue(
                      widget.session.sessionId,
                      _shellMemberId,
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !widget.permissionWaiting,
                        minLines: 1,
                        maxLines: 4,
                        style: TpTextStyles.of(context).md,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.memberWorking
                              ? l10n.sessionFollowUpAddPlaceholder
                              : l10n.sessionHistoryComposeHint,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: canSubmit
                            ? (_) => unawaited(_handleSubmit(chat))
                            : null,
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    if (showStop)
                      _TerminalFollowUpStopButton(
                        tooltip: l10n.sessionHistoryComposeStop,
                        onStop: () => unawaited(_handleComposeStop(chat)),
                      )
                    else
                      _TerminalFollowUpSendButton(
                        canSubmit: canSubmit,
                        isSubmitting: _submitting,
                        onSubmit: () => unawaited(_handleSubmit(chat)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TerminalFollowUpComposeHost extends StatelessWidget {
  const TerminalFollowUpComposeHost({
    required this.session,
    required this.selectedMemberId,
    this.team,
    super.key,
  });

  final AppSession session;
  final String selectedMemberId;
  final TeamProfile? team;

  String _effectiveMemberId(TeamProfile? teamProfile) {
    if (session.isSimple || teamProfile == null) return '';
    final mid = selectedMemberId.trim();
    if (mid.isNotEmpty) return mid;
    return teamProfile.members
            .where(TeamMemberNaming.isTeamLead)
            .firstOrNull
            ?.id ??
        teamProfile.members.firstOrNull?.id ??
        '';
  }

  TeamMemberConfig? _selectedMember(TeamProfile? teamProfile) {
    if (teamProfile == null) return null;
    final mid = _effectiveMemberId(teamProfile);
    if (mid.isEmpty) return null;
    return teamProfile.members.where((m) => m.id == mid).firstOrNull;
  }

  CliTool _lockedCli(List<CliPreset> presets) {
    if (session.isSimple) return session.cli ?? CliTool.claude;
    final teamProfile = team;
    if (teamProfile == null) return CliTool.claude;
    final memberId = _effectiveMemberId(teamProfile);
    final member = _selectedMember(teamProfile);
    return SessionMemberCliResolver.resolve(
      persistedSession: session,
      team: teamProfile,
      memberId: memberId.isNotEmpty ? memberId : (member?.id ?? ''),
      globalPresets: presets,
      cliForMember: (t, id, {List<CliPreset> globalPresets = const []}) {
        final m = (member != null && member.id == id)
            ? member
            : () {
                for (final x in t.members) {
                  if (x.id == id) return x;
                }
                return null;
              }();
        if (m != null) {
          return memberLaunchCli(
            team: t,
            member: m,
            globalPresets: globalPresets,
          );
        }
        return t.cli;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    context.select<ChatCubit, (String?, Set<String>)>(
      (c) => (c.state.activeSessionId, c.state.workingSessionIds),
    );
    context.select<MemberPresenceCubit, Map<String, MemberPresence>>(
      (c) => c.state.presence,
    );

    final chat = context.read<ChatCubit>();
    final shellMemberId = shellMemberIdForHistory(
      sessionId: session.sessionId,
      selectedMemberId: selectedMemberId,
    );
    final memberWorking =
        chat.isMemberWorking(session.sessionId, shellMemberId);
    final permissionWaiting = AgentPermissionAttentionBanner.isSelectedSeatWaiting(
      attention: context.read<AgentAttentionCubit>(),
      session: session,
      selectedMemberId: selectedMemberId,
    );
    final presets = context.read<CliPresetsCubit>().state.presets;
    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    final lockedCli = _lockedCli(presets);
    final supportsTurnInterrupt =
        registry
            .capability<TurnInterruptCapability>(lockedCli)
            ?.supportsTurnInterrupt ??
        false;

    return MultiBlocListener(
      listeners: [
        BlocListener<ChatCubit, ChatState>(
          listenWhen: (previous, current) =>
              previous.workingSessionIds != current.workingSessionIds,
          listener: (context, _) {
            final cubit = context.read<ChatCubit>();
            cubit.notifyFollowUpMemberWorking(
              session.sessionId,
              shellMemberId,
              working: cubit.isMemberWorking(session.sessionId, shellMemberId),
            );
          },
        ),
        BlocListener<MemberPresenceCubit, MemberPresenceState>(
          listenWhen: (previous, current) =>
              previous.presence != current.presence,
          listener: (context, _) {
            final cubit = context.read<ChatCubit>();
            cubit.notifyFollowUpMemberWorking(
              session.sessionId,
              shellMemberId,
              working: cubit.isMemberWorking(session.sessionId, shellMemberId),
            );
          },
        ),
      ],
      child: TerminalFollowUpCompose(
        session: session,
        selectedMemberId: selectedMemberId,
        team: team,
        memberWorking: memberWorking,
        supportsTurnInterrupt: supportsTurnInterrupt,
        permissionWaiting: permissionWaiting,
      ),
    );
  }
}

class _TerminalFollowUpSendButton extends StatelessWidget {
  const _TerminalFollowUpSendButton({
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icons = context.tpIconSizes;
    const size = 36.0;

    return Semantics(
        button: true,
        enabled: canSubmit && !isSubmitting,
        child: Material(
          color: canSubmit ? cs.primary : cs.surfaceContainerHighest,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canSubmit && !isSubmitting
                ? throttledOnPressed('terminal_follow_up_send', onSubmit)
                : null,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: isSubmitting
                    ? SizedBox(
                        width: icons.sm,
                        height: icons.sm,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : Icon(
                        Icons.arrow_upward_rounded,
                        color: canSubmit ? cs.onPrimary : cs.onSurfaceVariant,
                        size: icons.md,
                      ),
              ),
            ),
          ),
        ),
    );
  }
}

class _TerminalFollowUpStopButton extends StatelessWidget {
  const _TerminalFollowUpStopButton({
    required this.tooltip,
    required this.onStop,
  });

  final String tooltip;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icons = context.tpIconSizes;
    const size = 36.0;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: cs.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: throttledOnPressed('terminal_follow_up_stop', onStop),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Icon(
                  Icons.stop_rounded,
                  color: cs.onPrimary,
                  size: icons.md,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
