import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;

import '../../models/launch_security_policy.dart';
import '../../utils/logging/logger_utils.dart';
import '../agent_status/agent_permission_request.dart';
import '../agent_status/seat_hold_gate.dart';
import 'acp_agent_translator.dart';
import 'acp_client_extensions.dart';
import 'acp_connection.dart';
import 'acp_host_mcp_permission.dart';

/// The sender of a streamed message chunk.
enum AcpRole { assistant, user }

/// Why a prompt turn ended.
enum AcpStopKind {
  /// The agent finished its reply normally.
  endTurn,

  /// The agent stopped before finishing (refused or aborted mid-turn).
  aborted,

  /// The turn ended because a token or turn budget was exhausted.
  maxTokens,

  /// The user cancelled the turn.
  cancelled,

  /// The turn failed with a surfaced (translated) error.
  error,
}

/// Lifecycle status of a tool call.
enum AcpToolCallStatus { pending, inProgress, completed, failed }

/// Relative importance of a plan entry.
enum AcpPlanEntryPriority { high, medium, low }

/// Lifecycle state of a plan entry.
enum AcpPlanEntryStatus { pending, inProgress, completed }

/// One entry in an agent-reported execution plan.
class AcpPlanEntry {
  const AcpPlanEntry({
    required this.content,
    required this.priority,
    required this.status,
  });

  final String content;
  final AcpPlanEntryPriority priority;
  final AcpPlanEntryStatus status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpPlanEntry &&
          content == other.content &&
          priority == other.priority &&
          status == other.status;

  @override
  int get hashCode => Object.hash(content, priority, status);
}

/// A turn event mapped from ACP `session/update` notifications.
///
/// `base` (not `sealed`) so Cursor extension updates in
/// [acp_client_extensions] can subclass without living in this file.
base class AcpSessionUpdate {
  const AcpSessionUpdate();
}

/// A streamed chunk of a user/assistant message.
final class AcpMessageChunk extends AcpSessionUpdate {
  const AcpMessageChunk({
    required this.role,
    required this.content,
    required this.isThought,
  });

  final AcpRole role;

  /// The text payload (non-text content blocks are skipped).
  final String content;

  /// Whether this is the agent's internal reasoning rather than its reply.
  final bool isThought;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpMessageChunk &&
          role == other.role &&
          content == other.content &&
          isThought == other.isThought;

  @override
  int get hashCode => Object.hash(role, content, isThought);
}

/// A tool call initiation or status/content update.
final class AcpToolCallUpdate extends AcpSessionUpdate {
  const AcpToolCallUpdate({
    required this.toolCallId,
    this.title,
    this.status,
    this.background = false,
  });

  final String toolCallId;

  /// The tool call's title when the agent reported one.
  final String? title;

  /// The reported status (omitted fields keep the previous status).
  final AcpToolCallStatus? status;

  /// Whether the agent launched this shell/tool call in the background.
  ///
  /// ACP v1 has no out-of-turn update stream, so background work started here
  /// can outlive the prompt turn without any further `session/update` frames.
  /// The chat layer uses this flag to start history reconciliation.
  final bool background;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpToolCallUpdate &&
          toolCallId == other.toolCallId &&
          title == other.title &&
          status == other.status &&
          background == other.background;

  @override
  int get hashCode => Object.hash(toolCallId, title, status, background);
}

/// The agent's execution plan (each update replaces the previous plan).
final class AcpPlan extends AcpSessionUpdate {
  const AcpPlan({required this.entries});

  final List<AcpPlanEntry> entries;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpPlan && _sameEntries(entries, other.entries);

  @override
  int get hashCode => Object.hashAll(entries);

  static bool _sameEntries(List<AcpPlanEntry> a, List<AcpPlanEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The terminal event of a prompt turn.
final class AcpStop extends AcpSessionUpdate {
  const AcpStop({required this.kind, this.message});

  final AcpStopKind kind;

  /// Translated error text, set only for [AcpStopKind.error].
  final String? message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpStop && kind == other.kind && message == other.message;

  @override
  int get hashCode => Object.hash(kind, message);
}

/// Auth status from the agent (`_auth/status_update` or an unknown
/// `session/update` with the same payload). Reporting-only: `kind: none`
/// is a CLI probe, not a confirmed logout, so the chat cubit does not
/// insert a system row from it.
final class AcpAuthNotice extends AcpSessionUpdate {
  const AcpAuthNotice({required this.loggedIn, this.message});

  final bool loggedIn;
  final String? message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAuthNotice &&
          loggedIn == other.loggedIn &&
          message == other.message;

  @override
  int get hashCode => Object.hash(loggedIn, message);
}

/// One model the agent advertises for the open session.
///
/// ACP exposes model selection as a `session/set_config_option` entry whose
/// category is `model`; [id] is the wire value, [name] is the agent's label.
class AcpModelOption {
  const AcpModelOption({
    required this.id,
    required this.name,
    this.description,
  });

  final String id;
  final String name;
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpModelOption &&
          id == other.id &&
          name == other.name &&
          description == other.description;

  @override
  int get hashCode => Object.hash(id, name, description);
}

/// The agent-advertised model selector for the open ACP session.
///
/// Null when the agent does not negotiate a `model` config option (many
/// agents still only accept the launch-time provider/model configuration).
class AcpModelState {
  const AcpModelState({
    required this.configId,
    required this.currentId,
    required this.options,
  });

  /// Config option id used by `session/set_config_option`.
  final String configId;

  /// Currently selected option value.
  final String currentId;

  /// Selectable models, in the agent's order.
  final List<AcpModelOption> options;

  AcpModelOption? get currentOption {
    for (final option in options) {
      if (option.id == currentId) return option;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpModelState &&
          configId == other.configId &&
          currentId == other.currentId &&
          _sameOptions(options, other.options);

  @override
  int get hashCode => Object.hash(configId, currentId, Object.hashAll(options));

  static bool _sameOptions(List<AcpModelOption> a, List<AcpModelOption> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The agent changed its config options (including the model selector).
final class AcpModelStateUpdate extends AcpSessionUpdate {
  const AcpModelStateUpdate({required this.state});

  /// The new model state, or null when the agent no longer advertises one.
  final AcpModelState? state;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpModelStateUpdate && state == other.state;

  @override
  int get hashCode => state?.hashCode ?? 0;
}

/// Parses Claude-adapter auth notices from a JSON-RPC params map.
///
/// Wire shapes observed:
/// - method `_auth/status_update` with `{authStatus: {kind, label}}`
///   (`kind` is `none` / `account` / `api_key` / `gateway` / `external`)
/// - method `_auth/status_update` with `{kind, message}`
/// - `session/update` whose inner `sessionUpdate` is `_auth/status_update`
AcpAuthNotice? parseAcpAuthNotice(
  Map<String, Object?> params, {
  String? method,
}) {
  final nested = params['update'];
  final map = nested is Map ? Map<String, Object?>.from(nested) : params;
  final sessionUpdate = map['sessionUpdate'] as String? ?? method ?? '';
  final statusRaw = map['authStatus'] ?? map['status'];
  final status = statusRaw is Map ? Map<String, Object?>.from(statusRaw) : map;
  final kind = (status['kind'] as String? ?? map['kind'] as String? ?? '')
      .toLowerCase();
  final message =
      (status['label'] as String? ??
              status['message'] as String? ??
              map['label'] as String? ??
              map['message'] as String?)
          ?.trim();
  final looksAuth =
      method == '_auth/status_update' ||
      sessionUpdate.contains('auth') ||
      map.containsKey('authStatus') ||
      (message != null && message.toLowerCase().contains('not logged in'));
  if (!looksAuth) return null;
  const loggedInKinds = {
    'account',
    'api_key',
    'gateway',
    'external',
    'logged_in',
    'authenticated',
    'ok',
  };
  return AcpAuthNotice(
    loggedIn: loggedInKinds.contains(kind),
    message: (message == null || message.isEmpty) ? null : message,
  );
}

/// One prompt turn of an ACP agent session.
///
/// Wraps the acpd client connection bound to a `session/new` id: maps
/// `session/update` notifications onto the [AcpSessionUpdate] union, holds
/// `session/request_permission` requests in a single-slot seat gate until
/// [answerPermission] (or a timeout) resolves them, and resolves [prompt]
/// once the turn's stop reason is emitted on [updates].
///
/// After [cancel] the session keeps accepting and emitting tool-call updates
/// until the stop reason arrives (ACP requires draining trailing updates).
class AcpAgentSession {
  AcpAgentSession({
    required AcpAgentConnection connection,
    required this.sessionId,
    required this.cwd,
    this.mcpServers = const [],
    this.meta = const {},
    this.permissionTimeout = defaultPermissionTimeout,
    this.permissionPolicy = LaunchSecurityPolicy.fullAccess,
    List<acpd.SessionConfigOption> configOptions = const [],
    bool suppressBootstrapUpdates = false,
  }) : _connection = connection,
       _client = connection.acpdClient,
       _configOptions = List.unmodifiable(configOptions),
       _suppressBootstrap = suppressBootstrapUpdates {
    _updateRegistration = _client.connection.onNotification(
      'session/update',
      _onSessionUpdate,
    );
    _permissionRegistration = _client.connection.onRequest(
      'session/request_permission',
      _onRequestPermission,
    );
    _extensionRegistrations.addAll(
      registerCursorClientExtensions(
        rpc: _client.connection,
        blockingMethods: connection.translator.blockingClientMethods,
        notificationMethods: connection.translator.notificationClientMethods,
        isDisposed: () => _disposed,
        emitRequest: _emitClientRequest,
        wait: _waitHold,
        emitUpdate: _emit,
      ),
    );
  }

  /// How long a surfaced permission card waits before auto-rejecting.
  ///
  /// Mirrors the app's hook-gate default: effectively "until the user acts".
  static const Duration defaultPermissionTimeout = Duration(hours: 24);

  /// Synthetic seat member id for the permission hold (seat key is
  /// `sessionId/acp`; ACP sessions have exactly one member — the agent).
  static const _permissionMemberId = 'acp';

  final AcpAgentConnection _connection;
  final acpd.ClientConnection _client;

  /// The connection this session runs on (exit watcher on the runtime side).
  AcpAgentConnection get connection => _connection;

  /// The ACP session identifier from `session/new`.
  final String sessionId;

  /// Directory the session was opened with; `session/load` requires it again
  /// when history reconciliation replays the session.
  final String cwd;

  /// MCP servers the session was opened with; `session/load` requires them
  /// again so a replay re-attaches the same servers.
  final List<acpd.McpServer> mcpServers;

  /// Protocol metadata the session was opened with.
  final Map<String, Object?> meta;

  /// How long the permission hold waits before answering the agent with the
  /// cancelled default outcome.
  final Duration permissionTimeout;

  /// Client-side ACP permission policy for this session.
  ///
  /// [LaunchSecurityPolicy.fullAccess] auto-allows grantable options.
  /// [LaunchSecurityPolicy.ask] auto-allows only teammate-bus (host MCP)
  /// and surfaces a card for everything else.
  LaunchSecurityPolicy permissionPolicy;

  /// Assigns [policy] for subsequent permission requests. Does not rewrite
  /// an in-flight card.
  void setPermissionPolicy(LaunchSecurityPolicy policy) {
    permissionPolicy = policy;
  }

  /// Session configuration options reported by `session/new`, `session/load`,
  /// or `session/resume`, kept current by [AcpModelStateUpdate] notifications.
  List<acpd.SessionConfigOption> _configOptions;

  /// The agent's model selector, or null when it does not advertise one.
  AcpModelState? get modelState => _modelStateFrom(_configOptions);

  /// Switches the open session to [modelId] via `session/set_config_option`.
  ///
  /// The agent's response is authoritative for the new option list (it may
  /// also narrow the available models). Throws [ArgumentError] when [modelId]
  /// is not currently advertised and [StateError] when no model option exists.
  Future<void> setModel(
    String modelId, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_disposed) {
      throw StateError('Cannot switch model on a disposed ACP session.');
    }
    final state = modelState;
    if (state == null) {
      throw StateError('The ACP agent does not advertise a model option.');
    }
    if (!state.options.any((option) => option.id == modelId)) {
      throw ArgumentError.value(
        modelId,
        'modelId',
        'is not an advertised model for this session',
      );
    }
    final response = await _client.client.setSessionConfigOption(
      acpd.SetValueIdConfigOption(
        sessionId: sessionId,
        configId: state.configId,
        value: modelId,
      ),
      timeout: timeout,
    );
    _applyConfigOptions(response.configOptions);
  }

  void _applyConfigOptions(List<acpd.SessionConfigOption> configOptions) {
    final previous = _modelStateFrom(_configOptions);
    _configOptions = List.unmodifiable(configOptions);
    final next = _modelStateFrom(_configOptions);
    if (previous != next) _emit(AcpModelStateUpdate(state: next));
  }

  static AcpModelState? _modelStateFrom(
    List<acpd.SessionConfigOption> configOptions,
  ) {
    for (final option in configOptions) {
      if (option is! acpd.SessionConfigSelectOptionValue) continue;
      final category = option.category?.toJson();
      if (category != 'model' && option.id.toLowerCase() != 'model') {
        continue;
      }
      final choices = _flattenSelectOptions(option.options)
          .map(
            (choice) => AcpModelOption(
              id: choice.value,
              name: choice.name,
              description: choice.description,
            ),
          )
          .toList(growable: false);
      if (choices.isEmpty) return null;
      return AcpModelState(
        configId: option.id,
        currentId: option.currentValue,
        options: choices,
      );
    }
    return null;
  }

  static List<acpd.SessionConfigSelectOption> _flattenSelectOptions(
    acpd.SessionConfigSelectOptions? options,
  ) {
    return switch (options) {
      acpd.SessionConfigUngroupedOptions(:final options) => options,
      acpd.SessionConfigGroupedOptions(:final groups) => [
        for (final group in groups) ...group.options,
      ],
      null => const [],
    };
  }

  final _updates = StreamController<AcpSessionUpdate>.broadcast();
  final _permissionRequests =
      StreamController<AgentPermissionRequest>.broadcast();
  final _clientRequests = StreamController<AcpPendingClientRequest>.broadcast();
  final _gate = SeatHoldGate<AcpHoldReply>(
    staleReply: () => const AcpCancelledHoldReply(),
  );
  final _extensionRegistrations = <acpd.HandlerRegistration>[];

  acpd.HandlerRegistration? _updateRegistration;
  acpd.HandlerRegistration? _permissionRegistration;

  /// Whether a user cancel has been issued for the current turn; flips the
  /// translator into abort-suppressing mode.
  bool _suppressAbort = false;

  /// Whether a prompt turn is currently in flight (sequential-turns guard).
  bool _promptInFlight = false;

  /// When true, `session/update` notifications are dropped until the first
  /// [prompt]. Set for load/resume sessions: the agent replays its whole
  /// history, but the app transcript is the UI source of truth.
  bool _suppressBootstrap;

  /// True while [loadHistory] is collecting a replay. Bootstrap suppression
  /// does not apply to an explicit reconciliation request.
  bool _collectingHistory = false;
  List<AcpSessionUpdate>? _historyBuffer;

  bool _disposed = false;

  /// Turn events in arrival order; each turn ends with exactly one [AcpStop].
  Stream<AcpSessionUpdate> get updates => _updates.stream;

  /// Surfaced permission cards, one at a time (single-slot hold).
  Stream<AgentPermissionRequest> get permissionRequests =>
      _permissionRequests.stream;

  /// Blocking Cursor extension requests (ask / plan) waiting on the hold.
  Stream<AcpPendingClientRequest> get clientRequests => _clientRequests.stream;

  /// Sends `session/prompt` and resolves once the stop reason is emitted.
  ///
  /// Turns are strictly sequential: throws [StateError] when a prompt is
  /// already in flight for this session.
  ///
  /// Prompt-phase errors are routed through the connection's translator; a
  /// translated [acpStopCancelled] becomes an [AcpStopKind.cancelled] stop
  /// with no error surfaced, everything else an [AcpStopKind.error] stop
  /// carrying the translated message. Abort suppression (set by [cancel])
  /// stays on for the whole turn and is cleared when the turn ends.
  Future<void> prompt(String text) async {
    _suppressBootstrap = false;
    if (_promptInFlight) {
      throw StateError('A prompt turn is already in flight for this session.');
    }
    _promptInFlight = true;
    try {
      final response = await _client.client.prompt(
        acpd.PromptRequest.text(sessionId, text),
      );
      _emit(AcpStop(kind: _mapStopReason(response.stopReason)));
    } on Object catch (error) {
      final translated = _connection.translator.translateStopError(
        error,
        suppressAbort: _suppressAbort,
      );
      if (translated == acpStopCancelled) {
        _emit(const AcpStop(kind: AcpStopKind.cancelled));
      } else {
        _emit(AcpStop(kind: AcpStopKind.error, message: translated));
      }
    } finally {
      _promptInFlight = false;
      _suppressAbort = false;
    }
  }

  /// Replays the whole session through `session/load` and returns the mapped
  /// history without emitting it on [updates].
  ///
  /// ACP v1 has no out-of-turn update stream: after `end_turn` the agent can
  /// keep working on background tasks and only records the resulting messages
  /// in its own history. The chat layer calls this to reconcile that history
  /// with the app transcript (see `AcpChatRuntimeCubit.syncHistory`).
  ///
  /// Returns an empty list when the session is disposed. Throws [StateError]
  /// while a prompt is in flight — callers must wait for the stop event.
  Future<List<AcpSessionUpdate>> loadHistory({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_disposed) return const [];
    if (_connection.negotiatedCapabilities?.loadSession != true) return const [];
    if (_promptInFlight) {
      throw StateError(
        'Cannot load ACP history while a prompt turn is in flight.',
      );
    }
    if (_collectingHistory) return const [];
    _collectingHistory = true;
    final buffer = <AcpSessionUpdate>[];
    _historyBuffer = buffer;
    try {
      final response = await _client.client.loadSession(
        acpd.LoadSessionRequest(
          sessionId: sessionId,
          cwd: cwd,
          mcpServers: mcpServers,
          meta: meta,
        ),
        timeout: timeout,
      );
      if (!_disposed) {
        _applyConfigOptions(response.configOptions);
      }
      return List<AcpSessionUpdate>.unmodifiable(buffer);
    } finally {
      _collectingHistory = false;
      _historyBuffer = null;
    }
  }

  /// Sends `session/cancel` for the current turn.
  ///
  /// Flips abort suppression so a quirk-shaped abort error from the agent is
  /// reported as [AcpStopKind.cancelled] instead of an error. Trailing
  /// tool-call updates keep flowing onto [updates] until the stop reason.
  void cancel() {
    _suppressAbort = true;
    _client.client.cancel(sessionId);
    _gate.complete(
      sessionId: sessionId,
      memberId: _permissionMemberId,
      reply: const AcpCancelledHoldReply(),
    );
  }

  /// Answers the held permission request (if any).
  ///
  /// Returns the reply kind when a held request was completed with it, and
  /// null when nothing was held (already answered, timed out, or disposed) —
  /// in that case the agent has already received the cancelled default.
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async {
    if (_disposed) return null;
    final delivered = _gate.complete(
      sessionId: sessionId,
      memberId: _permissionMemberId,
      reply: AcpPermissionHoldReply(kind: reply, always: always),
    );
    return delivered ? reply : null;
  }

  /// Answers the held ask-question request (if any).
  Future<void> answerAsk(AcpAskHoldReply reply) async {
    if (_disposed) return;
    _gate.complete(
      sessionId: sessionId,
      memberId: _permissionMemberId,
      reply: reply,
    );
  }

  /// Answers the held create-plan request (if any).
  Future<void> answerPlan(AcpPlanHoldReply reply) async {
    if (_disposed) return;
    _gate.complete(
      sessionId: sessionId,
      memberId: _permissionMemberId,
      reply: reply,
    );
  }

  /// Releases the notification/request registrations and stream controllers.
  ///
  /// A still-held permission request is answered with the cancelled default
  /// so the agent is never left waiting, and the connection's open-session
  /// slot is released so a new session may be opened if needed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _gate.clearSeat(sessionId: sessionId, memberId: _permissionMemberId);
    _updateRegistration?.dispose();
    _permissionRegistration?.dispose();
    for (final registration in _extensionRegistrations) {
      registration.dispose();
    }
    _extensionRegistrations.clear();
    _updates.close();
    _permissionRequests.close();
    _clientRequests.close();
    _connection.sessionDisposed(this);
  }

  /// Replays a `session/update` that arrived before this session object
  /// existed (agent emits auth/commands during `session/new`).
  void replayRawNotification(Map<String, Object?> params) =>
      _onSessionUpdate(params);

  /// Replays a parsed `_auth/status_update` that arrived during handshake.
  void replayAuth(AcpAuthNotice notice) {
    _connection.lastAuthNotice = notice;
    _emit(notice);
  }

  void _onSessionUpdate(Object? params) {
    if (_disposed) return;
    // Bootstrap suppression hides the load/resume replay from [updates], but
    // an explicit [loadHistory] reconciliation must still observe it.
    final collecting = _collectingHistory;
    if (_suppressBootstrap && !collecting) return;
    if (params is! Map) return;
    final raw = Map<String, Object?>.from(params);
    final acpd.SessionUpdateNotification notification;
    try {
      notification = acpd.SessionUpdateNotification.fromJson(raw);
    } on Object catch (error, stackTrace) {
      final notice = parseAcpAuthNotice(raw);
      if (notice != null) {
        if (collecting) return;
        _connection.lastAuthNotice = notice;
        _emit(notice);
        return;
      }
      AppLogger.instance.w(
        'ACP: dropping malformed update: $error',
        stackTrace: stackTrace,
      );
      return;
    }
    if (notification.sessionId != sessionId) return;
    final update = notification.update;
    if (update is acpd.ConfigOptionSessionUpdate) {
      _applyConfigOptions(update.configOptions);
      return;
    }
    final mapped = _mapUpdate(update);
    if (mapped == null) return;
    if (collecting) {
      _historyBuffer?.add(mapped);
      return;
    }
    _emit(mapped);
  }

  Future<Object?> _onRequestPermission(Object? params) async {
    // dispose() closed the request stream; answer with the cancelled default
    // so the agent is never left waiting (mirrors the stale/timeout paths).
    if (_disposed) return _encodePermission(const acpd.PermissionCancelled());
    if (_rawSessionIdMismatch(params)) {
      return _encodePermission(const acpd.PermissionCancelled());
    }
    if (params is! Map) {
      return _encodePermission(const acpd.PermissionCancelled());
    }
    final autoOptionId = autoAllowAcpPermissionOptionId(
      params,
      allowNonHost: permissionPolicy != LaunchSecurityPolicy.ask,
    );
    if (autoOptionId != null) {
      return _encodePermission(acpd.PermissionSelected(optionId: autoOptionId));
    }
    final acpd.RequestPermissionRequest request;
    try {
      request = acpd.RequestPermissionRequest.fromJson(
        normalizeAcpPermissionOptionKinds(Map<String, Object?>.from(params)),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        'ACP: dropping malformed permission: $error',
        stackTrace: stackTrace,
      );
      return _encodePermission(const acpd.PermissionCancelled());
    }
    if (request.sessionId != sessionId) {
      return _encodePermission(const acpd.PermissionCancelled());
    }

    _permissionRequests.add(_toPermissionRequest(request));
    final reply = await _waitHold();
    return _encodePermission(_outcomeFor(reply, request.options));
  }

  Map<String, Object?> _encodePermission(acpd.RequestPermissionOutcome outcome) {
    return _connection.translator.encodePermissionResponse(outcome);
  }

  /// True when the payload names a different ACP session than this one.
  ///
  /// A missing `sessionId` is treated as matching so handshake-shaped
  /// permission requests still auto-allow.
  bool _rawSessionIdMismatch(Object? params) {
    if (params is! Map) return false;
    final id = params['sessionId'] ?? params['session_id'];
    if (id == null) return false;
    return id != sessionId;
  }

  /// Maps the held reply to the ACP outcome the agent receives.
  ///
  /// A `null` reply (timeout, dispose, or a superseded hold) answers with the
  /// cancelled outcome — the ACP v1 stand-in for "deny", matching Zed's
  /// mapping. `allowOnce` selects the request's first allow-once option;
  /// `always` prefers the chosen option's optionId (carried on
  /// [AgentPermissionAlwaysOption.payload], assigned when the card was built)
  /// and falls back to the request's first allow-always option.
  acpd.RequestPermissionOutcome _outcomeFor(
    AcpHoldReply? reply,
    List<acpd.PermissionOption> options,
  ) {
    if (reply is! AcpPermissionHoldReply) {
      return const acpd.PermissionCancelled();
    }
    switch (reply.kind) {
      case AgentPermissionReplyKind.allowOnce:
        final optionId = _firstOptionOfKind(
          options,
          acpd.PermissionOptionKind.allowOnce,
        );
        if (optionId == null) {
          return const acpd.PermissionCancelled();
        }
        return acpd.PermissionSelected(optionId: optionId);
      case AgentPermissionReplyKind.always:
        final payload = reply.always?.payload;
        final optionId = payload is String
            ? payload
            : _firstOptionOfKind(
                options,
                acpd.PermissionOptionKind.allowAlways,
              );
        if (optionId == null) {
          return const acpd.PermissionCancelled();
        }
        return acpd.PermissionSelected(optionId: optionId);
      case AgentPermissionReplyKind.reject:
        return const acpd.PermissionCancelled();
    }
  }

  void _emitClientRequest(AcpPendingClientRequest pending) {
    if (!_clientRequests.isClosed) _clientRequests.add(pending);
  }

  Future<AcpHoldReply?> _waitHold() => _gate.wait(
    sessionId: sessionId,
    memberId: _permissionMemberId,
    timeout: permissionTimeout,
  );

  String? _firstOptionOfKind(
    List<acpd.PermissionOption> options,
    acpd.PermissionOptionKind kind,
  ) {
    for (final option in options) {
      if (option.kind == kind) return option.optionId;
    }
    return null;
  }

  /// Builds the chat-layer permission card for an ACP request.
  ///
  /// The card's reply correlation key is the tool call id; allow-always
  /// options become [AgentPermissionAlwaysOption]s whose payload carries the
  /// ACP optionId to echo on an "always" reply.
  AgentPermissionRequest _toPermissionRequest(
    acpd.RequestPermissionRequest request,
  ) {
    final toolCall = request.toolCall;
    return AgentPermissionRequest(
      id: toolCall.toolCallId,
      description: _describeToolCall(toolCall),
      patterns: const [],
      always: request.options
          .where((o) => o.kind == acpd.PermissionOptionKind.allowAlways)
          .map(
            (o) =>
                AgentPermissionAlwaysOption(label: o.name, payload: o.optionId),
          )
          .toList(),
      sessionID: sessionId,
      toolMessageID: null,
      toolCallID: toolCall.toolCallId,
    );
  }

  String _describeToolCall(acpd.ToolCallUpdate toolCall) {
    final title = toolCall.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final kind = toolCall.kind?.name ?? 'tool';
    final rawInput = toolCall.rawInput;
    if (rawInput is String && rawInput.trim().isNotEmpty) {
      return '$kind ${rawInput.trim()}';
    }
    return kind;
  }

  AcpSessionUpdate? _mapUpdate(acpd.SessionUpdate update) {
    switch (update) {
      case acpd.UserMessageChunk():
        return AcpMessageChunk(
          role: AcpRole.user,
          content: _chunkText(update.chunk),
          isThought: false,
        );
      case acpd.AgentMessageChunk():
        return AcpMessageChunk(
          role: AcpRole.assistant,
          content: _chunkText(update.chunk),
          isThought: false,
        );
      case acpd.AgentThoughtChunk():
        return AcpMessageChunk(
          role: AcpRole.assistant,
          content: _chunkText(update.chunk),
          isThought: true,
        );
      case acpd.ToolCallUpdateSession(:final toolCall):
        return AcpToolCallUpdate(
          toolCallId: toolCall.toolCallId,
          title: toolCall.title,
          status: _mapToolCallStatus(toolCall.status),
          background: _isBackgroundToolCall(toolCall.rawInput),
        );
      case acpd.ToolCallStatusUpdate(:final update):
        return AcpToolCallUpdate(
          toolCallId: update.toolCallId,
          title: update.title,
          status: _mapToolCallStatus(update.status),
          background: _isBackgroundToolCall(update.rawInput),
        );
      case acpd.PlanUpdate(:final plan):
        return AcpPlan(
          entries: plan.entries
              .map(
                (e) => AcpPlanEntry(
                  content: e.content,
                  priority: _mapPlanPriority(e.priority),
                  status: _mapPlanStatus(e.status),
                ),
              )
              .toList(),
        );
      // Available-commands, mode, session-info, and usage updates have no
      // chat-layer representation yet. Config options are handled before
      // mapping (they update the model selector).
      default:
        return null;
    }
  }

  String _chunkText(acpd.ContentChunk chunk) {
    // TODO(acp): non-text content blocks (image, audio, resource_link,
    // resource) are discarded here — map them once the chat layer can render
    // non-text message parts; for now an empty chunk keeps the boundary.
    final content = chunk.content;
    if (content is acpd.TextContentBlock) return content.text;
    return '';
  }

  /// OpenCode's shell tool marks out-of-turn command launches in `rawInput`.
  bool _isBackgroundToolCall(Object? rawInput) {
    if (rawInput is! Map) return false;
    return rawInput['background'] == true ||
        rawInput['run_in_background'] == true;
  }

  AcpToolCallStatus? _mapToolCallStatus(acpd.ToolCallStatus? status) {
    if (status == null) return null;
    return switch (status) {
      acpd.ToolCallStatus.pending => AcpToolCallStatus.pending,
      acpd.ToolCallStatus.inProgress => AcpToolCallStatus.inProgress,
      acpd.ToolCallStatus.completed => AcpToolCallStatus.completed,
      acpd.ToolCallStatus.failed => AcpToolCallStatus.failed,
    };
  }

  AcpPlanEntryPriority _mapPlanPriority(acpd.PlanEntryPriority priority) {
    return switch (priority) {
      acpd.PlanEntryPriority.high => AcpPlanEntryPriority.high,
      acpd.PlanEntryPriority.medium => AcpPlanEntryPriority.medium,
      acpd.PlanEntryPriority.low => AcpPlanEntryPriority.low,
    };
  }

  AcpPlanEntryStatus _mapPlanStatus(acpd.PlanEntryStatus status) {
    return switch (status) {
      acpd.PlanEntryStatus.pending => AcpPlanEntryStatus.pending,
      acpd.PlanEntryStatus.inProgress => AcpPlanEntryStatus.inProgress,
      acpd.PlanEntryStatus.completed => AcpPlanEntryStatus.completed,
    };
  }

  AcpStopKind _mapStopReason(acpd.StopReason reason) {
    return switch (reason) {
      acpd.StopReason.endTurn => AcpStopKind.endTurn,
      acpd.StopReason.maxTokens => AcpStopKind.maxTokens,
      acpd.StopReason.maxTurnRequests => AcpStopKind.maxTokens,
      acpd.StopReason.refusal => AcpStopKind.aborted,
      acpd.StopReason.cancelled => AcpStopKind.cancelled,
    };
  }

  void _emit(AcpSessionUpdate update) {
    if (!_updates.isClosed) _updates.add(update);
  }
}
