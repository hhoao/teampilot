import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/agent_status/agent_attention_state.dart';
import '../services/agent_status/agent_status_event.dart';
import '../services/agent_status/ask_user_question.dart';
import '../services/agent_status/ask_user_question_hook_gate.dart';
import '../services/cli/claude/capabilities/permission_sticky.dart';
import '../services/agent_status/exit_plan_mode.dart';

/// Orca-aligned TTL: drop seat attention with no refresh after this duration.
const Duration agentAttentionStaleAfter = Duration(minutes: 30);

/// How often [AgentAttentionCubit] physically prunes stale seats so BlocBuilder
/// consumers clear waiting without waiting for a new hook.
const Duration agentAttentionPruneInterval = Duration(minutes: 1);

/// Per-seat attention snapshot with last-update timestamp for stale pruning.
class AgentSeatAttentionEntry extends Equatable {
  const AgentSeatAttentionEntry({
    required this.attention,
    required this.updatedAt,
    this.lastEvent,
    this.dismissedAskRequestId,
    this.askReplyError,
    this.dismissedPlanFingerprint,
    this.activeSubagentIds = const <String>{},
    this.parentStopPending = false,
  });

  final AgentSeatAttention attention;
  final DateTime updatedAt;

  /// Last applied event (sticky permission context).
  final AgentStatusEvent? lastEvent;

  /// Ask id optimistically dismissed via [AgentAttentionCubit.markAskAnswered].
  /// Same-id waiting events are ignored until restore or a new ask arrives.
  final String? dismissedAskRequestId;

  /// Plan fingerprint of an ExitPlanMode approval/rejection answered from the
  /// chat card. Same-plan `PermissionRequest` waiting echoes are ignored so
  /// the card does not reappear for a plan the user already decided.
  final String? dismissedPlanFingerprint;

  /// Optional error from `question.reply_failed` after optimistic dismiss.
  final String? askReplyError;

  /// 活动子 agent id 集合（codex SubagentStart/SubagentStop 维护，按 id 去重）。
  /// 非空时该 seat 免除 attention TTL——宁可在无输出的长任务期间保守保住
  /// terminal，也不能提前判空闲导致回收。
  final Set<String> activeSubagentIds;

  /// 父任务已上报 Stop/StopFailure 但仍有子 agent 未结束：seat 保持 working，
  /// 集合清空后才真正转 done。
  final bool parentStopPending;

  @override
  List<Object?> get props => [
    attention,
    updatedAt,
    lastEvent,
    dismissedAskRequestId,
    askReplyError,
    dismissedPlanFingerprint,
    activeSubagentIds,
    parentStopPending,
  ];
}

/// Seat-keyed agent attention for History banner / sidebar consumers.
class AgentAttentionState extends Equatable {
  const AgentAttentionState({this.seats = const {}, DateTime Function()? clock})
    : _clock = clock;

  final Map<String, AgentSeatAttentionEntry> seats;
  final DateTime Function()? _clock;

  DateTime get _now => (_clock ?? DateTime.now)();

  /// Fresh seat entry, or null when absent / stale.
  AgentSeatAttentionEntry? entryFor({
    required String sessionId,
    required String memberId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final entry = seats[key];
    if (entry == null || _isStale(entry, _now)) return null;
    return entry;
  }

  /// Attention for a seat, or null when absent / stale.
  AgentSeatAttention? attentionFor({
    required String sessionId,
    required String memberId,
  }) => entryFor(sessionId: sessionId, memberId: memberId)?.attention;

  /// True when any fresh seat in [sessionId] is [AgentSeatAttention.waiting].
  bool sessionHasWaiting(String sessionId) =>
      waitingMemberIds(sessionId).isNotEmpty;

  /// True when any fresh seat in [sessionId] is [AgentSeatAttention.waiting] or
  /// [AgentSeatAttention.working] — Orca-style "agent still in a turn" for
  /// sidebar / History working indicators (PTY idle-watch may have ended the
  /// latch while permission was held).
  ///
  /// When [includeMember] is set, seats for which it returns false are ignored
  /// (e.g. mixed members parked in `wait_for_message`).
  bool sessionIsAgentActive(
    String sessionId, {
    bool Function(String memberId)? includeMember,
  }) {
    final prefix = '${sessionId.trim()}\u0000';
    final now = _now;
    for (final e in seats.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (_isStale(e.value, now)) continue;
      final memberId = e.key.substring(prefix.length);
      if (includeMember != null && !includeMember(memberId)) continue;
      final a = e.value.attention;
      if (a == AgentSeatAttention.waiting || a == AgentSeatAttention.working) {
        return true;
      }
    }
    return false;
  }

  /// Member ids currently waiting (fresh) for [sessionId].
  List<String> waitingMemberIds(String sessionId) {
    final prefix = '${sessionId.trim()}\u0000';
    final now = _now;
    final ids = <String>[];
    for (final e in seats.entries) {
      if (!e.key.startsWith(prefix)) continue;
      if (_isStale(e.value, now)) continue;
      if (e.value.attention != AgentSeatAttention.waiting) continue;
      ids.add(e.key.substring(prefix.length));
    }
    return ids;
  }

  AgentAttentionState copyWith({Map<String, AgentSeatAttentionEntry>? seats}) =>
      AgentAttentionState(seats: seats ?? this.seats, clock: _clock);

  /// Drop entries older than [agentAttentionStaleAfter].
  AgentAttentionState pruned([DateTime? now]) {
    final at = now ?? _now;
    final next = <String, AgentSeatAttentionEntry>{};
    for (final e in seats.entries) {
      if (!_isStale(e.value, at)) next[e.key] = e.value;
    }
    if (next.length == seats.length) return this;
    return copyWith(seats: next);
  }

  /// 活动子 agent 存在时永不过期（spec：TTL 例外）。
  static bool _isStale(AgentSeatAttentionEntry entry, DateTime now) =>
      entry.activeSubagentIds.isEmpty &&
      now.difference(entry.updatedAt) > agentAttentionStaleAfter;

  @override
  List<Object?> get props => [seats];
}

/// Holds seat-keyed attention; skip-permissions gate + 30m stale TTL.
class AgentAttentionCubit extends Cubit<AgentAttentionState> {
  AgentAttentionCubit({
    DateTime Function()? clock,
    Duration? pruneInterval = agentAttentionPruneInterval,
  }) : _clock = clock ?? DateTime.now,
       super(AgentAttentionState(clock: clock ?? DateTime.now)) {
    if (pruneInterval != null) {
      _pruneTimer = Timer.periodic(pruneInterval, (_) => pruneStale());
    }
  }

  final DateTime Function() _clock;
  Timer? _pruneTimer;

  /// Physically drop stale seats and emit when the map changes so BlocBuilder
  /// consumers clear waiting after TTL without a new hook.
  void pruneStale() {
    if (isClosed) return;
    final pruned = state.pruned(_clock());
    if (pruned != state) emit(pruned);
  }

  /// Optimistically dismiss a waiting ask: move to [AgentSeatAttention.working]
  /// while retaining [AgentSeatAttentionEntry.lastEvent] so
  /// `question.reply_failed` can restore the card.
  ///
  /// Reads the dismissed id from [AgentSeatAttentionEntry.lastEvent]'s
  /// [AgentStatusEvent.askRequestId] — callers do not pass an id.
  void markAskAnswered({required String sessionId, required String memberId}) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final existing = state.seats[key];
    if (existing == null) return;
    if (existing.attention != AgentSeatAttention.waiting) return;
    final askRequestId = existing.lastEvent?.askRequestId;
    if (askRequestId == null || askRequestId.isEmpty) return;

    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats);
    seats[key] = AgentSeatAttentionEntry(
      attention: AgentSeatAttention.working,
      updatedAt: _clock(),
      lastEvent: existing.lastEvent,
      dismissedAskRequestId: askRequestId,
      askReplyError: null,
      dismissedPlanFingerprint: existing.dismissedPlanFingerprint,
      activeSubagentIds: existing.activeSubagentIds,
      parentStopPending: existing.parentStopPending,
    );
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  /// Optimistically drop a waiting seat back to working (plan approved /
  /// rejected from the chat card) while retaining
  /// [AgentSeatAttentionEntry.lastEvent]. Records the plan fingerprint so
  /// same-plan `PermissionRequest` waiting echoes (Claude's second, native
  /// plan confirmation) do not re-light the card.
  void dismissWaitingPlanApproval({
    required String sessionId,
    required String memberId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final existing = state.seats[key];
    if (existing == null || existing.attention != AgentSeatAttention.waiting) {
      return;
    }
    final lastEvent = existing.lastEvent;
    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats);
    seats[key] = AgentSeatAttentionEntry(
      attention: AgentSeatAttention.working,
      updatedAt: _clock(),
      lastEvent: lastEvent,
      dismissedPlanFingerprint: lastEvent == null
          ? null
          : exitPlanModeFingerprint(
              planText: lastEvent.planText,
              planFilePath: lastEvent.planFilePath,
            ),
      activeSubagentIds: existing.activeSubagentIds,
      parentStopPending: existing.parentStopPending,
    );
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  /// Apply a normalized status event for one seat.
  ///
  /// When [skipPermissions] is true and [event] is waiting, the event is
  /// ignored (prior non-waiting state kept, or no-op if absent).
  ///
  /// Sticky Claude permission (Orca): concurrent subagent tool activity does
  /// not clear waiting unless the approved tool resumes or an explicit prompt
  /// arrives.
  void applyEvent({
    required String sessionId,
    required String memberId,
    required AgentStatusEvent event,
    required bool skipPermissions,
  }) {
    // Claude Code's --dangerously-skip-permissions does not skip
    // AskUserQuestion, opencode's question tool always needs an answer,
    // opencode permission prompts are also interactive, and ExitPlanMode plan
    // approval is also an interactive prompt — these still block on the
    // operator. Keep the seat waiting for them so the chat card stays
    // available.
    final isInteractiveWaiting =
        event.state == AgentSeatAttention.waiting &&
        (isAskUserQuestionTool(event.toolName) ||
            isExitPlanModeTool(event.toolName) ||
            event.hookEventName == 'question.asked' ||
            event.hookEventName == 'permission.asked');
    if (skipPermissions &&
        event.state == AgentSeatAttention.waiting &&
        !isInteractiveWaiting) {
      pruneStale();
      return;
    }

    final now = _clock();
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final pruned = state.pruned(now);
    final existingEntry = pruned.seats[key];
    final previous = existingEntry?.lastEvent;

    // 子 agent 生命周期（codex SubagentStart/SubagentStop）先于通用注意力
    // 处理：子 agent 的完成绝不等于父完成。
    final hookName = event.hookEventName;
    if (hookName == 'SubagentStart' || hookName == 'SubagentStop') {
      final childId = event.toolAgentId?.trim() ?? '';
      if (childId.isEmpty) {
        // 无法定位子 agent：不参与计数、不改变状态（也绝不当作父完成）。
        if (pruned != state) emit(pruned);
        return;
      }
      _applySubagentLifecycle(
        key: key,
        event: event,
        isStart: hookName == 'SubagentStart',
        baseSeats: pruned.seats,
        now: now,
      );
      return;
    }

    // 父任务完成（Stop/StopFailure）：仍有子 agent 时仅记录 pending 并保持
    // working，最后一个子结束才转 done；集合为空走原有立即完成路径。
    final activeChildren = existingEntry?.activeSubagentIds ?? const <String>{};
    final isParentCompletion =
        (hookName == 'Stop' || hookName == 'StopFailure') &&
        activeChildren.isNotEmpty;
    if (isParentCompletion) {
      final seats = Map<String, AgentSeatAttentionEntry>.of(pruned.seats);
      // waiting 权限/提问卡保持可见，只更新跟踪状态。
      seats[key] = existingEntry!.attention == AgentSeatAttention.waiting
          ? AgentSeatAttentionEntry(
              attention: AgentSeatAttention.waiting,
              updatedAt: now,
              lastEvent: existingEntry.lastEvent,
              dismissedAskRequestId: existingEntry.dismissedAskRequestId,
              askReplyError: existingEntry.askReplyError,
              dismissedPlanFingerprint: existingEntry.dismissedPlanFingerprint,
              activeSubagentIds: existingEntry.activeSubagentIds,
              parentStopPending: true,
            )
          : AgentSeatAttentionEntry(
              attention: AgentSeatAttention.working,
              updatedAt: now,
              lastEvent: event,
              dismissedPlanFingerprint: existingEntry.dismissedPlanFingerprint,
              activeSubagentIds: existingEntry.activeSubagentIds,
              parentStopPending: true,
            );
      emit(AgentAttentionState(seats: seats, clock: _clock));
      return;
    }

    // Ignore echoed waiting for an optimistically dismissed ask.
    final dismissedId = existingEntry?.dismissedAskRequestId;
    if (event.state == AgentSeatAttention.waiting &&
        event.askRequestId != null &&
        dismissedId != null &&
        event.askRequestId == dismissedId) {
      if (pruned != state) emit(pruned);
      return;
    }

    // Ignore the `PermissionRequest` echo of a plan the user already approved
    // / rejected on the chat card (Claude's second, native plan confirmation).
    // The held hook is auto-answered by `ExitPlanPermissionRequestGate`; this
    // only keeps the dismissed card from re-lighting.
    final dismissedPlanFingerprint = existingEntry?.dismissedPlanFingerprint;
    if (event.state == AgentSeatAttention.waiting &&
        event.hookEventName == 'PermissionRequest' &&
        isExitPlanModeTool(event.toolName) &&
        dismissedPlanFingerprint != null &&
        dismissedPlanFingerprint.isNotEmpty) {
      final echoFingerprint = exitPlanModeFingerprint(
        planText: event.planText ?? previous?.planText,
        planFilePath: event.planFilePath ?? previous?.planFilePath,
      );
      if (echoFingerprint == dismissedPlanFingerprint) {
        final seats = Map<String, AgentSeatAttentionEntry>.of(pruned.seats);
        seats[key] = AgentSeatAttentionEntry(
          attention: AgentSeatAttention.working,
          updatedAt: now,
          lastEvent: existingEntry!.lastEvent,
          dismissedAskRequestId: existingEntry.dismissedAskRequestId,
          askReplyError: existingEntry.askReplyError,
          dismissedPlanFingerprint: dismissedPlanFingerprint,
          activeSubagentIds: existingEntry.activeSubagentIds,
          parentStopPending: existingEntry.parentStopPending,
        );
        emit(AgentAttentionState(seats: seats, clock: _clock));
        return;
      }
    }

    // Restore waiting ask card after reply_failed (keep prior questions).
    final isRestore =
        event.restoreAskWaiting ||
        event.hookEventName == 'question.reply_failed';
    if (isRestore && existingEntry != null) {
      final eventAskId = event.askRequestId;
      final lastAskId = existingEntry.lastEvent?.askRequestId;
      final matches =
          eventAskId != null &&
          (eventAskId == dismissedId || eventAskId == lastAskId);
      if (matches) {
        final seats = Map<String, AgentSeatAttentionEntry>.of(pruned.seats);
        seats[key] = AgentSeatAttentionEntry(
          attention: AgentSeatAttention.waiting,
          updatedAt: now,
          lastEvent: existingEntry.lastEvent,
          dismissedAskRequestId: null,
          askReplyError: event.message,
          dismissedPlanFingerprint: existingEntry.dismissedPlanFingerprint,
          activeSubagentIds: existingEntry.activeSubagentIds,
          parentStopPending: existingEntry.parentStopPending,
        );
        emit(AgentAttentionState(seats: seats, clock: _clock));
        return;
      }
    }

    // OpenCode answered the request natively (TUI / reject): `question.answered`
    // / `permission.answered` fire when the CLI resolved it itself, before any
    // `session.idle`. Dismiss the waiting card like [markAskAnswered] so the
    // chat card clears immediately instead of lingering until the turn ends.
    // A non-matching id (other request) never clobbers the pending ask.
    final isAnswered =
        event.hookEventName == 'question.answered' ||
        event.hookEventName == 'permission.answered';
    if (isAnswered && existingEntry != null) {
      final eventAskId = event.askRequestId;
      final lastAskId = existingEntry.lastEvent?.askRequestId;
      final dismissedId = existingEntry.dismissedAskRequestId;
      final matches =
          eventAskId != null &&
          (eventAskId == lastAskId || eventAskId == dismissedId);
      if (matches && existingEntry.attention == AgentSeatAttention.waiting) {
        final seats = Map<String, AgentSeatAttentionEntry>.of(pruned.seats);
        seats[key] = AgentSeatAttentionEntry(
          attention: AgentSeatAttention.working,
          updatedAt: now,
          lastEvent: existingEntry.lastEvent,
          dismissedAskRequestId: null,
          askReplyError: null,
          dismissedPlanFingerprint: existingEntry.dismissedPlanFingerprint,
          activeSubagentIds: existingEntry.activeSubagentIds,
          parentStopPending: existingEntry.parentStopPending,
        );
        emit(AgentAttentionState(seats: seats, clock: _clock));
      }
      // Matched but already optimistically dismissed (chat path) — keep as
      // is; non-matching ids never clobber the pending ask card.
      return;
    }

    final effective = preserveExitPlanModePayload(
      previous,
      preservePermissionRequestPayload(
        previous,
        preserveAskUserQuestionPayload(
          previous,
          attachClaudePermissionToolUseId(previous, event),
        ),
      ),
    );

    if (shouldKeepClaudePermissionVisible(previous, effective)) {
      // Keep the waiting row; do not let other-subagent activity overwrite it.
      if (pruned != state) emit(pruned);
      return;
    }

    final seats = Map<String, AgentSeatAttentionEntry>.of(pruned.seats);
    // 新用户回合（UserPromptSubmit）重置上一回合的子 agent 跟踪，避免旧
    // 集合/pending 泄漏；其余通用事件保留跟踪（父 pending 不被中途活动清掉）。
    final startsNewTurn = effective.hasExplicitPrompt;
    // 新的计划确认提示（未被回显抑制吸收的 waiting ExitPlanMode 事件）
    // 作废上一轮已决策计划的 fingerprint，避免错误抑制新一轮确认。
    final isFreshPlanPrompt =
        effective.state == AgentSeatAttention.waiting &&
        isExitPlanModeTool(effective.toolName);
    seats[key] = AgentSeatAttentionEntry(
      attention: effective.state,
      updatedAt: now,
      lastEvent: effective,
      dismissedPlanFingerprint: startsNewTurn || isFreshPlanPrompt
          ? null
          : existingEntry?.dismissedPlanFingerprint,
      activeSubagentIds: startsNewTurn
          ? const <String>{}
          : existingEntry?.activeSubagentIds ?? const <String>{},
      parentStopPending: startsNewTurn
          ? false
          : existingEntry?.parentStopPending ?? false,
    );
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  /// 子 agent 生命周期状态机（按 `sessionId+memberId+agentId` 幂等）：
  ///
  /// - Start：id 加入集合；waiting 权限/提问卡保持可见，只更新集合。
  /// - Stop：id 移出集合；集合清空且父已 [AgentSeatAttentionEntry.parentStopPending]
  ///   才转 done，否则保留 working/waiting。未知 id 或无 seat 的事件忽略，
  ///   重复/乱序事件不改变正确状态。
  void _applySubagentLifecycle({
    required String key,
    required AgentStatusEvent event,
    required bool isStart,
    required Map<String, AgentSeatAttentionEntry> baseSeats,
    required DateTime now,
  }) {
    final seats = Map<String, AgentSeatAttentionEntry>.of(baseSeats);
    final existing = seats[key];
    final id = event.toolAgentId!.trim();

    if (!isStart) {
      if (existing == null || !existing.activeSubagentIds.contains(id)) {
        return;
      }
      final remaining = Set<String>.of(existing.activeSubagentIds)..remove(id);
      final turnOver = remaining.isEmpty && existing.parentStopPending;
      final keepWaiting =
          !turnOver && existing.attention == AgentSeatAttention.waiting;
      seats[key] = AgentSeatAttentionEntry(
        attention: turnOver
            ? AgentSeatAttention.done
            : keepWaiting
            ? AgentSeatAttention.waiting
            : AgentSeatAttention.working,
        updatedAt: now,
        lastEvent: keepWaiting ? existing.lastEvent : event,
        dismissedAskRequestId: existing.dismissedAskRequestId,
        askReplyError: existing.askReplyError,
        dismissedPlanFingerprint: existing.dismissedPlanFingerprint,
        activeSubagentIds: remaining,
        parentStopPending: turnOver ? false : existing.parentStopPending,
      );
      emit(AgentAttentionState(seats: seats, clock: _clock));
      return;
    }

    final added = Set<String>.of(
      existing?.activeSubagentIds ?? const <String>{},
    )..add(id);
    final keepWaitingCard =
        existing != null && existing.attention == AgentSeatAttention.waiting;
    seats[key] = AgentSeatAttentionEntry(
      attention: keepWaitingCard
          ? AgentSeatAttention.waiting
          : AgentSeatAttention.working,
      updatedAt: now,
      lastEvent: keepWaitingCard ? existing.lastEvent : event,
      dismissedAskRequestId: existing?.dismissedAskRequestId,
      askReplyError: existing?.askReplyError,
      dismissedPlanFingerprint: existing?.dismissedPlanFingerprint,
      activeSubagentIds: added,
      parentStopPending: existing?.parentStopPending ?? false,
    );
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  /// Remove one seat (e.g. PTY dispose / disconnect).
  void clearSeat({required String sessionId, required String memberId}) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    if (!state.seats.containsKey(key)) return;
    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats)
      ..remove(key);
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  /// Remove the seat only when it is currently [AgentSeatAttention.working].
  /// Never touches [AgentSeatAttention.waiting] (permission prompts) so a
  /// PTY-quiet turn-end fallback cannot mis-clear a pending question.
  void clearWorkingIfWorking({
    required String sessionId,
    required String memberId,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    final entry = state.seats[key];
    if (entry == null) return;
    if (entry.attention != AgentSeatAttention.working) return;
    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats)
      ..remove(key);
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  /// Remove all seats for a session (e.g. tab close).
  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}\u0000';
    final seats = Map<String, AgentSeatAttentionEntry>.of(state.seats);
    final before = seats.length;
    seats.removeWhere((k, _) => k.startsWith(prefix));
    if (seats.length == before) return;
    emit(AgentAttentionState(seats: seats, clock: _clock));
  }

  @override
  Future<void> close() {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    return super.close();
  }
}
