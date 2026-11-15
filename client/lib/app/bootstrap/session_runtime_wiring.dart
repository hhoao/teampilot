import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import '../../cubits/ai_history_cubit.dart';
import '../../cubits/board_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../cubits/notification_cubit.dart';
import '../../cubits/session_remote_activity_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../pages/home_workspace/home_workspace_route.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/attention/attention_cursor_store.dart';
import '../../services/attention/attention_event.dart';
import '../../services/attention/attention_inbox.dart';
import '../../services/attention/attention_log.dart';
import '../../services/chat/conversation/history/ai_history_loader.dart';
import '../../services/chat/conversation/history/session_history_context_builder.dart';
import '../../services/chat/session/session_lifecycle_service.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/notification/session_idle_notification_service.dart';
import '../../services/search/workspace_search_indexes.dart';
import '../../services/session_protocol/session_authority.dart';
import '../../services/session_sync/chat_session_activity_source.dart';
import '../../services/session_sync/chat_session_control_port.dart';
import '../../services/session_sync/session_content_invalidation_bus.dart';
import '../../services/session_sync/session_content_stream_bus.dart';
import '../../services/session_sync/session_protocol_controller.dart';
import '../../services/shared_state/shared_state_identity.dart';
import '../../services/storage/home_storage.dart';
import '../../utils/logging/logger.dart';
import '../../utils/session/workspace_tab_session_scope.dart';

/// The per-session runtime: mailbox/board cubits, the shared AI history store,
/// the session authority and its remote-activity projections.
///
/// The subscriptions are returned so the shell keeps owning them, together with
/// the attention inbox, for its bootstrap teardown
/// (`cancelShellSubscriptions`).
typedef SessionRuntimeWiring = ({
  SessionRemoteActivityCubit sessionRemoteActivityCubit,
  SessionAuthority sessionAuthority,
  ChatSessionActivitySource activitySource,
  SessionProtocolController protocolController,
  AttentionInbox attentionInbox,
  StreamSubscription<AttentionEvent> attentionSub,
  AiHistoryCubit aiHistoryCubit,
  MailboxCubit mailboxCubit,
  BoardCubit boardCubit,
  StreamSubscription<SessionRemoteActivityState> sessionRemoteRefreshSub,
  StreamSubscription<SessionContentInvalidation> contentInvalidationSub,
  StreamSubscription<SessionContentStreamChunk> contentStreamSub,
});

/// Builds the mailbox/board cubits, the [AiHistoryLoader]/[AiHistoryCubit]
/// pair, the session authority and the session protocol controller.
///
/// [chat], [cliPresets], [lifecycle] and [connectionMode] are getters because
/// the shell owns them as `late final` dependencies; each resolves once at
/// entry. [onHistoryLoaderCreated] publishes the new loader to the shell's
/// late-bound `aiHistoryLoaderRef` at the same point the assignment used to
/// run inline (runtime-context eviction clears its cache).
///
/// [deviceStorage] pins the attention log and its cursor store to the
/// device-local app-data root, so an SSH home never owns this device's
/// notification state.
Future<SessionRuntimeWiring> wireSessionRuntime({
  required HomeStorage deviceStorage,
  required ChatCubit Function() chat,
  required CliPresetsCubit Function() cliPresets,
  required SessionLifecycleService Function() lifecycle,
  required ConnectionModeService Function() connectionMode,
  required CliToolRegistry cliToolRegistry,
  required WorkbenchCubit workbench,
  required WorkspaceSearchIndexes workspaceSearchIndexes,
  required NotificationCubit notificationCubit,
  required bool Function() notifyOnSessionIdle,
  required bool Function(Object error) isExpectedFailure,
  required Future<bool> Function(Object error) waitForRecovery,
  required void Function(AiHistoryLoader loader) onHistoryLoaderCreated,
}) async {
  // Shell-local names so the construction below stays identical to the call it
  // was moved out of.
  final chatCubit = chat();
  final cliPresetsCubit = cliPresets();
  final sessionLifecycleService = lifecycle();
  final connectionModeService = connectionMode();
  final workbenchCubit = workbench;

  final mailboxCubit = MailboxCubit(
    busForScope: (scope) => scopedTeamBus(workbenchCubit, chatCubit, scope),
  );

  final boardCubit = BoardCubit(
    busForScope: (scope) => scopedTeamBus(workbenchCubit, chatCubit, scope),
  );

  final aiHistoryLoader = AiHistoryLoader(
    contextBuilder: const SessionHistoryContextBuilder(),
    resolveWorkContext: (launchCtx, {String? memberId}) =>
        sessionLifecycleService.launchWorkContext(
          launchCtx,
          memberId: memberId,
        ),
    registry: cliToolRegistry,
    globalPresets: () => cliPresetsCubit.state.presets,
  );
  onHistoryLoaderCreated(aiHistoryLoader);
  workspaceSearchIndexes.cachedHistoryMessages =
      ({required sessionId, required memberId, required token}) =>
          aiHistoryLoader.messagesIfCached(
            sessionId: sessionId,
            memberId: memberId,
            token: token,
          );
  // Pods own a per-session HistoryStore once the loader exists (ChatCubit is
  // constructed earlier); SessionChatView binds seats through the pod.
  chatCubit.historyLoader = aiHistoryLoader;
  final aiHistoryCubit = AiHistoryCubit(
    loader: aiHistoryLoader,
    loadMailboxRecords: (sessionId, memberId) async {
      final bus = chatCubit.tabStore.getOpenTabBySessionId(sessionId)?.teamBus;
      if (bus == null) return const [];
      return bus.memberMailRecords(memberId);
    },
  );
  final sessionRemoteActivityCubit = SessionRemoteActivityCubit();
  final authorityEpoch = DateTime.now().millisecondsSinceEpoch;
  AttentionLog? attentionLog;
  AttentionInbox? attentionInbox;
  StreamSubscription<AttentionEvent>? attentionSub;
  SessionAuthority? sessionAuthority;
  var attentionResourcesReady = false;
  try {
    final logPath = deviceStorage.paths.attentionLogJsonForEpoch(authorityEpoch);
    try {
      attentionLog = await AttentionLog.open(
        authorityId: SharedStateIdentity.deviceId,
        epoch: authorityEpoch,
        fs: deviceStorage.fs,
        path: logPath,
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[attention] log open failed; falling back to in-memory log '
        'epoch=$authorityEpoch path=$logPath',
        error: error,
        stackTrace: stackTrace,
      );
      attentionLog = AttentionLog(
        authorityId: SharedStateIdentity.deviceId,
        epoch: authorityEpoch,
      );
    }
    final attentionCursorStore = AttentionCursorStore(
      fs: deviceStorage.fs,
      path: deviceStorage.paths.attentionCursorsJson,
    );
    var cursorLoaded = false;
    for (var attempt = 0; attempt < 3 && !cursorLoaded; attempt++) {
      cursorLoaded = await attentionCursorStore.load();
      if (!cursorLoaded && attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (!cursorLoaded) {
      throw StateError(
        'attention cursor store unavailable; refusing to start live-only '
        'without a durable cursor '
        'path=${deviceStorage.paths.attentionCursorsJson}',
      );
    }
    attentionInbox = AttentionInbox(store: attentionCursorStore);
    sessionAuthority = SessionAuthority(
      authorityId: SharedStateIdentity.deviceId,
      controlPort: ChatSessionControlPort(chatCubit),
      epoch: authorityEpoch,
      attentionLog: attentionLog,
    );
  final sessionActivitySource = ChatSessionActivitySource(chatCubit);
  final contentInvalidationSub = SessionContentInvalidationBus.stream.listen((
    event,
  ) {
    if (!connectionModeService.isLocalMode) return;
    sessionAuthority?.publishContentInvalidated(
      sessionId: event.sessionId,
      memberId: event.memberId,
    );
  });
  final contentStreamSub = SessionContentStreamBus.stream.listen((chunk) {
    if (!connectionModeService.isLocalMode) return;
    sessionAuthority?.publishContentDelta(
      sessionId: chunk.sessionId,
      memberId: chunk.memberId,
      kind: 'acp.messages',
      payload: chunk.payload,
      partial: !chunk.replace,
    );
  });
  final sessionRemoteRefreshSub = sessionRemoteActivityCubit.stream.listen((
    state,
  ) {
    if (!connectionModeService.isSshMode) return;
    final known = {
      for (final session in chatCubit.state.sessions) session.sessionId,
    };
    for (final snapshot in state.sessions.values) {
      final workspaceId = snapshot.workspaceId;
      if (workspaceId.isEmpty) continue;
      chatCubit.upsertRemoteSessionHint(
        sessionId: snapshot.sessionId,
        workspaceId: workspaceId,
      );
      if (known.contains(snapshot.sessionId)) continue;
      unawaited(chatCubit.refreshSessionsForWorkspace(workspaceId));
    }
  });
  final remoteIdleNotifications = SessionIdleNotificationService(
    recorder: notificationCubit,
  );
  // Dedupe belongs to the inbox: it persists seen event ids on this device and
  // only emits events this process has not consumed yet.
  Future<void> notifyRemoteAttention(AttentionEvent attention) async {
    final session = chatCubit.state.sessions
        .where((item) => item.sessionId == attention.sessionId)
        .firstOrNull;
    final title = attention.title.trim().isNotEmpty
        ? attention.title.trim()
        : (session?.display.trim().isNotEmpty ?? false)
        ? session!.display.trim()
        : attention.sessionId;
    final locale = PlatformDispatcher.instance.locale;
    final l10n = lookupAppLocalizations(
      basicLocaleListResolution([locale], appLocalizationsSupportedLocales),
    );
    final workspaceId = attention.workspaceId.isNotEmpty
        ? attention.workspaceId
        : session?.workspaceId ?? '';
    final payload = HomeWorkspaceRoute.sessionLocation(
      workspaceId: workspaceId,
      sessionId: attention.sessionId,
    );
    await remoteIdleNotifications.notifyRemoteSessionIdle(
      title: title,
      message: attention.message.isNotEmpty
          ? attention.message
          : l10n.session.idleNotificationSubtitle,
      badge: l10n.session.idleNotificationTitle,
      payload: payload,
      systemNotificationEnabled: notifyOnSessionIdle(),
    );
  }

  attentionSub = attentionInbox.fresh.listen((event) {
    if (event.kind != AttentionKind.idle) return;
    unawaited(notifyRemoteAttention(event));
  });

  final sessionProtocolController = SessionProtocolController(
    deviceId: SharedStateIdentity.deviceId,
    remoteCubit: sessionRemoteActivityCubit,
    authority: sessionAuthority,
    attentionInbox: attentionInbox,
    isExpectedFailure: isExpectedFailure,
    waitForRecovery: waitForRecovery,
    onContentInvalidated: (invalidation) {
      SessionContentInvalidationBus.publish(
        sessionId: invalidation.sessionId,
        memberId: invalidation.memberId,
      );
      chatCubit.onSessionHistoryStale?.call(invalidation.sessionId);
    },
    onContentDelta: (delta) {
      if (delta.kind != 'acp.messages') return;
      SessionContentStreamBus.publish(
        sessionId: delta.sessionId,
        memberId: delta.memberId,
        payload: delta.payload,
        replace: !delta.partial,
      );
    },
    onSessionList: (delta) {
      if (!connectionModeService.isSshMode) return;
      chatCubit.applyRemoteSessionList(
        workspaceId: delta.workspaceId,
        upserted: delta.upserted,
        removed: delta.removed,
      );
    },
  );

  // Edits run on the runtime owner: when this process is a connected client,
  // the desktop that owns the seat executes them and streams the phases back.
  chatCubit.seatEditTransportFor =
      ({required String sessionId, required String memberId}) =>
          sessionProtocolController.editTransportFor(
            sessionId: sessionId,
            memberId: memberId,
          );

  attentionResourcesReady = true;
  return (
    sessionRemoteActivityCubit: sessionRemoteActivityCubit,
    sessionAuthority: sessionAuthority,
    activitySource: sessionActivitySource,
    protocolController: sessionProtocolController,
    attentionInbox: attentionInbox,
    attentionSub: attentionSub,
    aiHistoryCubit: aiHistoryCubit,
    mailboxCubit: mailboxCubit,
    boardCubit: boardCubit,
    sessionRemoteRefreshSub: sessionRemoteRefreshSub,
    contentInvalidationSub: contentInvalidationSub,
    contentStreamSub: contentStreamSub,
  );
  } finally {
    if (!attentionResourcesReady) {
      await attentionSub?.cancel();
      await attentionInbox?.dispose();
      await sessionAuthority?.dispose();
    }
  }
}
