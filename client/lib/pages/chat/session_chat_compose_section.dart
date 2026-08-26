import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/chat/model/session_connect_request.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/member_presence_cubit.dart';
import '../../cubits/prompt_delivery_status_cubit.dart';
import '../../cubits/plugin_cubit.dart';
import '../../cubits/skill_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/config_bundle.dart';
import '../../models/landing_launch_context.dart';
import '../../models/launch_security_policy.dart';
import '../../models/member_presence.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/native_command_capability.dart';
import '../../services/cli/registry/capabilities/skill_capability.dart';
import '../../services/cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/compose/compose_at_file_refs.dart';
import '../../services/compose/compose_clip.dart';
import '../../services/compose/compose_file_attach.dart';
import '../../services/compose/compose_file_drop_ingestor.dart';
import '../../services/compose/compose_landing_bundle.dart';
import '../../services/compose/compose_voice_input.dart';
import '../../services/expert_hub/expert_member_resolver.dart';
import '../../services/follow_up/follow_up_queue.dart';
import '../../services/session/history_seat_key.dart';
import '../../services/session/session_continue_overrides_apply.dart';
import '../../services/session/session_history_pagination.dart';
import '../../services/terminal/pending_user_message.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../utils/team/team_member_naming.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../widgets/compose/compose_chrome.dart';
import '../../widgets/compose/compose_model_preset_chip.dart';
import '../../widgets/compose/simple_custom_launch_dialog.dart';
import '../../widgets/compose/workspace_compose_card.dart';
import '../../widgets/follow_up/follow_up_queue_strip.dart';
import '../home_workspace/workspace/workspace_landing_team_settings_dialog.dart';
import 'agent_permission_attention_banner.dart';
import 'compose_stop_visibility.dart';
import 'history_continue_delivery.dart';
import 'history_mailbox_queued_strip.dart';
import 'prompt_delivery_recovery_strip.dart';
import 'session_chat_voice_controller.dart';

/// Self-contained compose section that reads its own cubits via
/// [context.select], eliminating the need for the parent to pass computed
/// values.
class SessionChatComposeSection extends StatelessWidget {
  const SessionChatComposeSection({
    required this.session,
    required this.workspace,
    required this.selectedMemberId,
    required this.shellMemberId,
    required this.composeController,
    required this.composeFocusNode,
    this.composeClip,
    required this.voiceController,
    required this.isSubmitting,
    required this.isEnhancing,
    required this.workspaceRoot,
    required this.workspaceBundle,
    required this.askCardVisible,
    required this.launchError,
    required this.onRemapDeadTarget,
    required this.onRetry,
    required this.sessionConnectInProgress,
    required this.isMailboxUnread,
    required this.mailboxQueued,
    required this.mailboxQueuedSeats,
    required this.mailboxQueuedClearToken,
    required this.onMailboxConsumed,
    required this.onAttach,
    required this.onEnhance,
    required this.onPasteImage,
    required this.onComposeChanged,
    required this.routeActive,
    required this.onSubmit,
    super.key,
  });

  final AppSession session;
  final Workspace workspace;
  final String selectedMemberId;
  final String shellMemberId;
  final TextEditingController composeController;
  final FocusNode composeFocusNode;

  /// Optional paste-collapse buffer. The visible controller holds only the
  /// follow-up text while collapsed; canSubmit and the submitted message
  /// account for the block.
  final ComposeClip? composeClip;
  final SessionVoiceController voiceController;
  final bool isSubmitting;
  final bool isEnhancing;
  final String workspaceRoot;
  final ConfigBundle workspaceBundle;
  final bool askCardVisible;
  final String? launchError;
  final VoidCallback? onRemapDeadTarget;
  final VoidCallback? onRetry;
  final bool sessionConnectInProgress;
  final bool Function(String mailId)? isMailboxUnread;
  final StreamController<PendingUserMessage> mailboxQueued;
  final Map<String, String> mailboxQueuedSeats;
  final int mailboxQueuedClearToken;
  final void Function(String mailId) onMailboxConsumed;
  final VoidCallback onAttach;
  final VoidCallback onEnhance;
  final Future<bool> Function() onPasteImage;
  final VoidCallback onComposeChanged;
  final bool routeActive;
  final Future<HistoryContinueSubmitResult> Function(String message) onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;

    // -- Read cubits via context.select ----------------------------------
    final skills = context.select<SkillCubit, List<Skill>>(
      (c) => c.state.installed,
    );
    final plugins = context.select<PluginCubit, List<Plugin>>(
      (c) => c.state.installed,
    );
    final presets = context.select<CliPresetsCubit, List<CliPreset>>(
      (c) => c.state.presets,
    );
    final team = _readLiveTeam(context);
    final hubState = _readExpertHubState(context);

    final permissionWaiting = context.select<AgentAttentionCubit, bool>(
      (c) => AgentPermissionAttentionBanner.isSelectedSeatWaiting(
        attention: c,
        session: session,
        selectedMemberId: selectedMemberId,
      ),
    );

    final registry =
        CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();

    // Rebuild when the session's workspace bar active changes (session switch)
    // or session working changes (seat-level stop).
    context.select<WorkbenchCubit, WorkbenchTabId?>(
      (w) => w.centerActiveId(session.workspaceId),
    );
    context.select<ChatCubit, Set<String>>((c) => c.state.workingSessionIds);
    context.select<MemberPresenceCubit, Map<String, MemberPresence>>(
      (c) => c.state.presence,
    );
    final chat = context.read<ChatCubit>();
    final memberWorking = chat.isMemberWorking(
      session.sessionId,
      shellMemberId,
    );
    final composeTextEmpty =
        composeController.text.trim().isEmpty &&
        !(composeClip?.collapsed ?? false);
    final lockedCli = _lockedCli(
      session: session,
      team: team,
      presets: presets,
      selectedMemberId: selectedMemberId,
    );
    final supportsTurnInterrupt =
        registry
            .capability<TerminalBehaviorCapability>(lockedCli)
            ?.supportsTurnInterrupt ??
        false;
    final showComposeStop = shouldShowComposeStop(
      memberWorking: memberWorking,
      supportsTurnInterrupt: supportsTurnInterrupt,
      composeTextEmpty: composeTextEmpty,
    );
    final skillSyntax = registry.capability<SkillCapability>(lockedCli);
    final nativeCommands =
        registry.capability<NativeCommandCapability>(lockedCli)?.commands ??
        const <NativeCommand>[];

    // -- Derived values --------------------------------------------------
    final canSubmit = !permissionWaiting && !composeTextEmpty && !isSubmitting;
    final sameCliPresets = presetsForCli(presets, lockedCli);
    final selectedPresetId = _selectedPresetId(
      session: session,
      team: team,
      selectedMemberId: selectedMemberId,
    );
    final selectedPreset = selectedPresetId == null
        ? null
        : sameCliPresets.where((p) => p.id == selectedPresetId).firstOrNull;
    final modelLabel = session.isSimple
        ? simpleLaunchChipLabel(
            presetName: selectedPreset?.name,
            cli: lockedCli,
            provider: session.provider,
            model: session.model,
            emptyLabel: l10n.workspaceChatLandingUsePreset,
          )
        : (selectedPreset?.name.trim().isNotEmpty == true
              ? selectedPreset!.name.trim()
              : l10n.workspaceChatLandingUsePreset);
    final identityLabel = _identityLabel(
      session: session,
      team: team,
      hubState: hubState,
      expertFallback: l10n.expertHubNoneSelected,
    );
    final workspaceForSettings = _workspaceForSettings(context);
    final showTeamSettings = !session.isSimple && team != null;
    final liveTeam = team;
    final teamSettingsAttention =
        showTeamSettings &&
        liveTeam != null &&
        landingTeamSettingsNeedsAttention(
          workspace: workspaceForSettings,
          team: liveTeam,
        );

    final followUpSeatKey = _followUpSeatKey(session.sessionId, shellMemberId);
    final mailboxSeatKey = _mailboxSeatKey(session.sessionId, selectedMemberId);

    final dropTarget = _buildDropTarget(workspaceRoot, composeController);

    final slashBundle = _slashBundle(
      workspaceRoot: workspaceRoot,
      workspaceBundle: workspaceBundle,
      session: session,
      team: team,
      hubState: hubState,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = resolveSessionHistoryColumnWidth(
          constraints.maxWidth,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.md,
                0,
                spacing.md,
                spacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AgentPermissionAttentionBanner(
                    session: session,
                    selectedMemberId: selectedMemberId,
                  ),
                  StreamBuilder<FollowUpQueue>(
                    stream: chat.followUpQueue.watch(followUpSeatKey),
                    initialData: chat.followUpQueue.queueFor(followUpSeatKey),
                    builder: (context, snapshot) {
                      final queue = snapshot.data ?? const FollowUpQueue();
                      return FollowUpQueueStrip(
                        queue: queue,
                        onDelete: (id) =>
                            chat.followUpQueue.remove(followUpSeatKey, id),
                        onEdit: (id, content) => chat.followUpQueue.edit(
                          followUpSeatKey,
                          id,
                          content,
                        ),
                        onMoveUp: (id) =>
                            chat.followUpQueue.moveUp(followUpSeatKey, id),
                        onResume: () => unawaited(
                          chat.resumeFollowUpQueue(
                            session.sessionId,
                            shellMemberId,
                          ),
                        ),
                      );
                    },
                  ),
                  if (isMailboxUnread != null)
                    HistoryMailboxQueuedStrip(
                      key: ValueKey('mailbox-queued-$mailboxQueuedClearToken'),
                      submissions: mailboxQueued.stream,
                      isUnread: isMailboxUnread!,
                      clearToken: mailboxQueuedClearToken,
                      onConsumed: (msg) {
                        final seatKey = mailboxQueuedSeats[msg.id];
                        if (seatKey != null && seatKey != mailboxSeatKey) {
                          return;
                        }
                        onMailboxConsumed(msg.id);
                      },
                    ),
                  if (!askCardVisible)
                    Builder(
                      builder: (context) {
                        final cubit = _promptDeliveryStatusCubit(context);
                        if (cubit == null) return const SizedBox.shrink();
                        return PromptDeliveryRecoveryMount(
                          recovery: _promptDeliveryRecovery(
                            context,
                            sessionId: session.sessionId,
                            memberId: shellMemberId,
                          ),
                          onRetry: () => unawaited(
                            cubit.retry(
                              sessionId: session.sessionId,
                              memberId: shellMemberId,
                            ),
                          ),
                          onRefresh: () =>
                              cubit.refreshSession(session.sessionId),
                        );
                      },
                    ),
                  if (!askCardVisible)
                    ListenableBuilder(
                      listenable: voiceController,
                      builder: (context, _) {
                        return WorkspaceComposeCard(
                          controller: composeController,
                          focusNode: composeFocusNode,
                          clip: composeClip,
                          hint: memberWorking
                              ? l10n.sessionFollowUpAddPlaceholder
                              : l10n.sessionHistoryComposeHint,
                          canSubmit: canSubmit,
                          isSubmitting: isSubmitting,
                          onSubmit: () => unawaited(
                            onSubmit(
                              composeClip?.composeMessage(
                                    composeController.text.trim(),
                                  ) ??
                                  composeController.text.trim(),
                            ),
                          ),
                          onChanged: (_) => onComposeChanged(),
                          chrome: BoundComposeChrome(
                            composeEnabled: !permissionWaiting,
                            launchError: launchError,
                            onRemapDeadTarget: onRemapDeadTarget,
                            onRetry: onRetry,
                            sessionConnectInProgress: sessionConnectInProgress,
                            floating: true,
                            identityLabel: identityLabel,
                            identityIcon: session.isSimple
                                ? Icons.psychology_outlined
                                : Icons.groups_outlined,
                            sameCliPresets: sameCliPresets,
                            selectedPresetId: selectedPresetId,
                            modelPresetLabel: modelLabel,
                            emptyPresetHintLabel:
                                l10n.workspaceCliPresetsEmptyHint,
                            onPresetSelected: (presetId) => unawaited(
                              _onPresetSelected(
                                context: context,
                                presetId: presetId,
                                session: session,
                                team: team,
                                sameCliPresets: sameCliPresets,
                                lockedCli: lockedCli,
                                selectedMemberId: selectedMemberId,
                              ),
                            ),
                            customLabel: session.isSimple
                                ? l10n.workspaceChatLandingCustomLaunch
                                : null,
                            customSelected:
                                session.isSimple &&
                                session.presetId.trim().isEmpty,
                            onCustom: session.isSimple
                                ? () => unawaited(
                                    _openContinueCustomLaunchDialog(
                                      context: context,
                                      session: session,
                                    ),
                                  )
                                : null,
                            launchSecurityPolicy: _effectiveSecurityPolicy(
                              session: session,
                              team: team,
                              selectedMemberId: selectedMemberId,
                            ),
                            defaultPermissionsLabel:
                                l10n.workspaceChatLandingDefaultPermissions,
                            fullAccessPermissionsLabel:
                                l10n.workspaceChatLandingFullAccessPermissions,
                            askReadOnlyPermissionsLabel:
                                l10n.workspaceChatLandingAskReadOnlyPermissions,
                            autoApproveWorkspaceWritePermissionsLabel: l10n
                                .workspaceChatLandingAutoApproveWorkspaceWritePermissions,
                            customPermissionsLabel:
                                l10n.workspaceChatLandingCustomPermissions,
                            onPermissionSelected: (value) => unawaited(
                              _onPermissionSelected(
                                context: context,
                                value: value,
                                session: session,
                                team: team,
                                selectedMemberId: selectedMemberId,
                              ),
                            ),
                            teamSettingsTooltip: showTeamSettings
                                ? l10n.teamSettings
                                : null,
                            onTeamSettings: showTeamSettings && liveTeam != null
                                ? () => unawaited(
                                    _openTeamSettings(
                                      context: context,
                                      team: liveTeam,
                                      workspaceId: session.workspaceId,
                                    ),
                                  )
                                : null,
                            showTeamSettingsAttention: teamSettingsAttention,
                            showStop: showComposeStop,
                            onStop: showComposeStop
                                ? () => unawaited(
                                    _handleComposeStop(
                                      context: context,
                                      sessionId: session.sessionId,
                                      shellMemberId: shellMemberId,
                                    ),
                                  )
                                : null,
                          ),
                          dropTarget: dropTarget,
                          deferFieldMount: false,
                          attachTooltip: l10n.workspaceChatLandingAttach,
                          enhanceTooltip: l10n.workspaceChatLandingEnhance,
                          voiceTooltip: l10n.workspaceChatLandingVoice,
                          voiceCancelTooltip:
                              l10n.workspaceChatLandingVoiceCancel,
                          voiceStopTooltip: l10n.workspaceChatLandingVoiceStop,
                          isEnhancing: isEnhancing,
                          isVoiceListening: voiceController.isListening,
                          voiceElapsed: voiceController.elapsed,
                          voiceSoundLevel: voiceController.soundLevel,
                          onAttach: onAttach,
                          onEnhance: onEnhance,
                          onVoice: () {
                            if (isSubmitting || isEnhancing) return;
                            unawaited(
                              voiceController
                                  .toggle(Localizations.localeOf(context))
                                  .then((ok) {
                                    if (!context.mounted) return;
                                    if (ok) {
                                      composeFocusNode.requestFocus();
                                      return;
                                    }
                                    final input = voiceController.input;
                                    if (input == null) return;
                                    AppToast.show(
                                      context,
                                      message: composeVoiceInitFailureMessage(
                                        context.l10n,
                                        input,
                                      ),
                                      variant: TpToastVariant.warning,
                                    );
                                  }),
                            );
                          },
                          onVoiceCancel: () =>
                              unawaited(voiceController.cancel()),
                          onVoiceStop: () => unawaited(voiceController.stop()),
                          onPasteImage: onPasteImage,
                          workspaceRoot: workspaceRoot,
                          skills: skills,
                          plugins: plugins,
                          slashBundle: slashBundle,
                          skillSyntax: skillSyntax,
                          nativeCommands: nativeCommands,
                          onOpenAtFile: (path) {
                            unawaited(
                              context.read<WorkbenchEditorOpener>().openFile(
                                session.workspaceId,
                                path,
                                preview: true,
                                fs: filesystemForComposeAtFileOpen(path),
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // -- Helpers (instance methods) -------------------------------------------

  String _followUpSeatKey(String sessionId, String memberId) =>
      followUpSeatKey(sessionId, memberId);

  String _mailboxSeatKey(String sessionId, String selMemberId) =>
      historySeatKey(sessionId: sessionId, selectedMemberId: selMemberId);

  ComposeFileDropIngestor _buildDropTarget(
    String root,
    TextEditingController controller,
  ) {
    return ComposeFileDropIngestor(
      workspaceRoot: root,
      onInsertReferences: (references) {
        insertComposeReferences(controller, references);
      },
    );
  }

  // -- Live team (scoped to session's team profile) ------------------------

  TeamProfile? _readLiveTeam(BuildContext context) {
    if (session.isSimple) return null;
    final teamId = session.sessionTeam.trim();
    if (teamId.isEmpty) return null;
    return context.select<LaunchProfileCubit, TeamProfile?>((c) {
      final profile = c.byId(teamId);
      return profile is TeamProfile ? profile : null;
    });
  }

  ExpertHubState? _readExpertHubState(BuildContext context) {
    try {
      return context.select<ExpertHubCubit, ExpertHubState>((c) => c.state);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Recovery snapshot for the compose seat. Null when the status cubit is
  /// not in scope (standalone test harnesses) or the seat has nothing to
  /// recover — never a build-time IO.
  PromptDeliveryRecovery? _promptDeliveryRecovery(
    BuildContext context, {
    required String sessionId,
    required String memberId,
  }) {
    try {
      return context
          .select<PromptDeliveryStatusCubit, PromptDeliveryRecovery?>(
        (c) => c.state.recoveryFor(sessionId, memberId),
      );
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// The status cubit when in scope; null in standalone harnesses that do not
  /// provide it, so the recovery surface degrades to nothing rather than
  /// throwing during compose build.
  PromptDeliveryStatusCubit? _promptDeliveryStatusCubit(BuildContext context) {
    try {
      return context.read<PromptDeliveryStatusCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  // -- Locked CLI ----------------------------------------------------------

  static CliTool _lockedCli({
    required AppSession session,
    required TeamProfile? team,
    required List<CliPreset> presets,
    required String selectedMemberId,
  }) {
    if (session.isSimple) return session.cli ?? CliTool.claude;
    if (team == null) return CliTool.claude;
    final memberId = _effectiveMemberId(session, selectedMemberId, team);
    final member = _selectedMember(team, memberId);
    return SessionMemberCliResolver.resolve(
      persistedSession: session,
      team: team,
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

  static String _effectiveMemberId(
    AppSession session,
    String selectedMemberId,
    TeamProfile? team,
  ) {
    if (session.isSimple || team == null) return '';
    final mid = selectedMemberId.trim();
    if (mid.isNotEmpty) return mid;
    return team.members.where(TeamMemberNaming.isTeamLead).firstOrNull?.id ??
        team.members.firstOrNull?.id ??
        '';
  }

  static TeamMemberConfig? _selectedMember(TeamProfile? team, String memberId) {
    if (team == null) return null;
    final mid = memberId;
    if (mid.isEmpty) return null;
    return team.members.where((m) => m.id == mid).firstOrNull;
  }

  // -- Effective security policy -------------------------------------------

  static LaunchSecurityPolicy _effectiveSecurityPolicy({
    required AppSession session,
    required TeamProfile? team,
    required String selectedMemberId,
  }) {
    final overrides = session.continueOverrides;
    if (session.isSimple) {
      return resolveContinueSecurityPolicy(
        launchDefault: LaunchSecurityPolicy.fullAccess,
        sessionLevel: overrides.launchSecurityPolicy,
        memberLevel: null,
      );
    }
    final memberId = _effectiveMemberId(session, selectedMemberId, team);
    final member = _selectedMember(team, memberId);
    final memberOverride = overrides.memberOverrides[memberId];
    return resolveContinueSecurityPolicy(
      sessionLevel: overrides.launchSecurityPolicy,
      memberLevel: memberOverride?.launchSecurityPolicy,
      launchDefault:
          member?.launchSecurityPolicy ?? LaunchSecurityPolicy.fullAccess,
    );
  }

  // -- Selected preset id --------------------------------------------------

  static String? _selectedPresetId({
    required AppSession session,
    required TeamProfile? team,
    required String selectedMemberId,
  }) {
    if (session.isSimple) {
      final id = session.presetId.trim();
      return id.isEmpty ? null : id;
    }
    final memberId = _effectiveMemberId(session, selectedMemberId, team);
    final fromOverride = session
        .continueOverrides
        .memberOverrides[memberId]
        ?.presetId
        ?.trim();
    if (fromOverride != null && fromOverride.isNotEmpty) return fromOverride;
    final member = _selectedMember(team, memberId);
    if (member == null) return null;
    if (member.inheritsTeamPreset) {
      final teamPreset = team?.activePresetId?.trim() ?? '';
      return teamPreset.isEmpty ? null : teamPreset;
    }
    if (member.hasExplicitPreset) {
      final id = member.activePresetId?.trim() ?? '';
      return id.isEmpty ? null : id;
    }
    return null;
  }

  // -- Identity label ------------------------------------------------------

  static String? _identityLabel({
    required AppSession session,
    required TeamProfile? team,
    required ExpertHubState? hubState,
    required String expertFallback,
  }) {
    if (!session.isSimple) {
      final name = team?.name.trim() ?? '';
      return name.isEmpty ? null : name;
    }
    final key = session.expertKey.trim();
    if (key.isEmpty) return null;
    return ExpertMemberResolver.labelForKey(
      key: key,
      fallbackLabel: expertFallback,
      hubState: hubState,
    );
  }

  // -- Workspace for settings ----------------------------------------------

  Workspace _workspaceForSettings(BuildContext context) {
    return context
            .read<ChatCubit>()
            .state
            .workspaces
            .where((w) => w.workspaceId == workspace.workspaceId)
            .firstOrNull ??
        workspace;
  }

  // -- Actions (read cubits from context) ----------------------------------

  static Future<void> _onPresetSelected({
    required BuildContext context,
    required String presetId,
    required AppSession session,
    required TeamProfile? team,
    required List<CliPreset> sameCliPresets,
    required CliTool lockedCli,
    required String selectedMemberId,
  }) async {
    final chatCubit = context.read<ChatCubit>();
    final live = _cubitSession(chatCubit, session.sessionId) ?? session;
    final preset = sameCliPresets.where((p) => p.id == presetId).firstOrNull;
    if (preset == null) return;
    final memberId = live.isSimple
        ? null
        : _effectiveMemberId(live, selectedMemberId, team);
    if (!live.isSimple && (memberId == null || memberId.isEmpty)) return;
    try {
      final ok = await chatCubit.setSessionContinuePreset(
        sessionId: live.sessionId,
        preset: preset,
        memberId: memberId,
        lockedCli: lockedCli,
      );
      if (!ok && context.mounted) {
        _toastContinueSaveFailed(context);
        return;
      }
      if (context.mounted) {
        await _offerRestartAfterIdentitySwitch(
          context,
          session: live,
          memberId: memberId,
        );
      }
    } on Object {
      if (context.mounted) _toastContinueSaveFailed(context);
    }
  }

  static Future<void> _onPermissionSelected({
    required BuildContext context,
    required LaunchSecurityPolicy value,
    required AppSession session,
    required TeamProfile? team,
    required String selectedMemberId,
  }) async {
    final chatCubit = context.read<ChatCubit>();
    final live = _cubitSession(chatCubit, session.sessionId) ?? session;
    final memberId = live.isSimple
        ? null
        : _effectiveMemberId(live, selectedMemberId, team);
    if (!live.isSimple && (memberId == null || memberId.isEmpty)) return;
    try {
      final ok = await chatCubit.setSessionContinueSecurityPolicy(
        sessionId: live.sessionId,
        launchSecurityPolicy: value,
        memberId: memberId,
      );
      if (!ok && context.mounted) _toastContinueSaveFailed(context);
    } on Object {
      if (context.mounted) _toastContinueSaveFailed(context);
    }
  }

  static Future<void> _openContinueCustomLaunchDialog({
    required BuildContext context,
    required AppSession session,
  }) async {
    final result = await showSimpleCustomLaunchDialog(
      context,
      lockCli: true,
      initialCli: session.cli ?? CliTool.claude,
      initialProvider: session.provider,
      initialModel: session.model,
      initialEffort: session.effort,
    );
    if (!context.mounted || result == null) return;
    final chatCubit = context.read<ChatCubit>();
    final live = _cubitSession(chatCubit, session.sessionId);
    if (live == null) {
      if (context.mounted) _toastContinueSaveFailed(context);
      return;
    }
    try {
      final ok = await chatCubit.setSessionContinueCustom(
        sessionId: live.sessionId,
        provider: result.provider,
        model: result.model,
        effort: result.effort,
      );
      if (!ok && context.mounted) {
        _toastContinueSaveFailed(context);
        return;
      }
      if (context.mounted) {
        await _offerRestartAfterIdentitySwitch(
          context,
          session: live,
          memberId: null,
        );
      }
    } on Object {
      if (context.mounted) _toastContinueSaveFailed(context);
    }
  }

  /// After a successful provider/model switch, the running terminal keeps the
  /// old materialized config. Offer an immediate restart so the switch lands;
  /// team members restart only their own PTY, Simple restarts the session.
  static Future<void> _offerRestartAfterIdentitySwitch(
    BuildContext context, {
    required AppSession session,
    required String? memberId,
  }) async {
    final chatCubit = context.read<ChatCubit>();
    final sessionId = session.sessionId;
    final running = session.isSimple
        ? chatCubit.isSessionRunning(sessionId)
        : (memberId?.isNotEmpty == true &&
            chatCubit.isMemberRunning(
              sessionId: sessionId,
              memberId: memberId!,
            ));
    if (!running) return;
    final restartNow =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => TpDialog(
            maxWidth: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpDialogHeader(
                  title: dialogContext.l10n.continueSwitchRestartTitle,
                  onClose: () => Navigator.pop(dialogContext, false),
                ),
                const SizedBox(height: 16),
                Text(dialogContext.l10n.continueSwitchRestartBody),
                TpDialogActions(
                  children: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, false),
                      child: Text(dialogContext.l10n.continueSwitchRestartLater),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(dialogContext.l10n.continueSwitchRestartNow),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!restartNow || !context.mounted) return;
    if (session.isSimple) {
      final repo = context.read<SessionRepository>();
      await chatCubit.restartWorkspaceSession(
        PersonalSessionConnect(workspaceId: session.workspaceId),
        repo: repo,
      );
      return;
    }
    if (memberId == null || memberId.isEmpty) return;
    chatCubit.discardMemberTerminal(sessionId, memberId);
    await chatCubit.ensureMemberTerminalForView(sessionId, memberId);
  }

  static Future<void> _openTeamSettings({
    required BuildContext context,
    required TeamProfile team,
    required String workspaceId,
  }) async {
    final chatCubit = context.read<ChatCubit>();
    final ws = chatCubit.state.workspaces
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull;
    if (ws == null) return;
    if (!context.mounted) return;
    await showLandingTeamSettingsDialog(context, workspace: ws, team: team);
  }

  static Future<void> _handleComposeStop({
    required BuildContext context,
    required String sessionId,
    required String shellMemberId,
  }) async {
    final chat = context.read<ChatCubit>();
    await chat.interruptSelectedMemberTurn(
      sessionId: sessionId,
      memberId: shellMemberId,
    );
    chat.pauseFollowUpQueue(sessionId, shellMemberId);
  }

  static AppSession? _cubitSession(ChatCubit cubit, String sessionId) {
    for (final s in cubit.state.sessions) {
      if (s.sessionId == sessionId) return s;
    }
    return null;
  }

  static void _toastContinueSaveFailed(BuildContext context) {
    AppToast.show(
      context,
      message: context.l10n.sessionHistoryContinueSaveFailed,
      variant: TpToastVariant.warning,
    );
  }

  static ConfigBundle _slashBundle({
    required String workspaceRoot,
    required ConfigBundle workspaceBundle,
    required AppSession session,
    required TeamProfile? team,
    required ExpertHubState? hubState,
  }) {
    final isPersonal = session.sessionTeam.trim().isEmpty;
    final draft = LandingLaunchContext(
      isPersonal: isPersonal,
      presetId: isPersonal
          ? (session.presetId.trim().isEmpty ? null : session.presetId)
          : null,
      teamId: isPersonal ? null : session.sessionTeam,
      expertKey: session.expertKey.trim().isEmpty ? null : session.expertKey,
      workingDirectoryPath: workspaceRoot,
      cli: isPersonal ? session.cli : null,
      provider: isPersonal ? session.provider : null,
      model: isPersonal ? session.model : null,
      effort: isPersonal ? session.effort : null,
    );
    return slashBundleForLanding(
      draft: draft,
      team: team,
      workspace: workspaceBundle,
      hubState: hubState,
    );
  }
}
