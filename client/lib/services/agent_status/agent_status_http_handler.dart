import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../cubits/agent_attention_cubit.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/exit_plan_mode_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../utils/logging/logger.dart';
import '../../services/terminal/prompt_submit_ack_tracker.dart';
import 'agent_status_event.dart';
import 'agent_status_normalizer.dart';
import 'ask_user_question.dart';
import 'ask_user_question_hook_gate.dart';
import 'exit_plan_mode.dart';
import 'exit_plan_mode_hook_gate.dart';

/// Max POST body size for `/agent-status` (~1 MiB).
const int agentStatusMaxBodyBytes = 1024 * 1024;

/// Parses CLI hook JSON → [AgentStatusNormalizer] → [AgentAttentionCubit].
///
/// Never touches TeamBus idle / park. Corrupt or oversized bodies keep prior
/// attention and return HTTP 200 `{}`.
///
/// AskUserQuestion `PreToolUse` holds the HTTP response until the chat card
/// answers via [AskUserQuestionHookGate], then returns Claude's official
/// `updatedInput.answers` allow payload (so the TUI is skipped).
class AgentStatusHttpHandler {
  AgentStatusHttpHandler({
    required this.attention,
    required this.resolveCli,
    required this.resolveSkipPermissions,
    this.askUserHookGate,
    this.exitPlanModeHookGate,
    this.promptAckTracker,
    CliToolRegistry? registry,
  }) : registry = registry ?? CliToolRegistry.builtIn();

  final AgentAttentionCubit attention;
  final CliTool? Function(String sessionId, String memberId) resolveCli;
  final bool Function(String sessionId, String memberId) resolveSkipPermissions;
  final AskUserQuestionHookGate? askUserHookGate;
  final ExitPlanModeHookGate? exitPlanModeHookGate;
  final PromptSubmitAckTracker? promptAckTracker;
  final CliToolRegistry registry;

  Future<void> handle(
    HttpRequest request, {
    required String sessionId,
    required String memberId,
  }) async {
    try {
      final raw = await _readJsonBody(request);
      final queryEvent = request.uri.queryParameters['event']?.trim();
      final body = _withHookEventName(raw, queryEvent);
      if (body != null) {
        final cli = resolveCli(sessionId, memberId);
        if (cli != null) {
          final event = AgentStatusNormalizer.normalize(cli: cli, body: body);
          if (event != null) {
            attention.applyEvent(
              sessionId: sessionId,
              memberId: memberId,
              event: event,
              skipPermissions: resolveSkipPermissions(sessionId, memberId),
            );
            final acked = promptAckTracker?.tryAck(
              sessionId: sessionId,
              memberId: memberId,
              text: event.prompt ?? '',
            ) ??
                false;
            if (acked) {
              appLogger.d(
                '[ai-history] prompt-submit acked session=$sessionId '
                'member=$memberId',
              );
            }
            final answered = await _maybeAnswerAskUserQuestionHook(
              request,
              sessionId: sessionId,
              memberId: memberId,
              event: event,
            );
            if (answered) return;
            final answeredPlan = await _maybeAnswerExitPlanModeHook(
              request,
              sessionId: sessionId,
              memberId: memberId,
              event: event,
            );
            if (answeredPlan) return;
          }
        }
      }
      await _writeOkEmpty(request);
    } catch (_) {
      try {
        await _writeOkEmpty(request);
      } catch (_) {}
    }
  }

  /// Returns true when the HTTP response was already written.
  Future<bool> _maybeAnswerAskUserQuestionHook(
    HttpRequest request, {
    required String sessionId,
    required String memberId,
    required AgentStatusEvent event,
  }) async {
    final gate = askUserHookGate;
    if (gate == null) return false;
    final hook = event.hookEventName?.trim() ?? '';
    final toolName = event.toolName;
    if (hook != 'PreToolUse' || !isAskUserQuestionTool(toolName)) {
      return false;
    }
    final questions = event.askUserQuestions;
    if (questions == null || questions.isEmpty) return false;
    final toolUseId = event.toolUseId?.trim() ?? '';
    if (toolUseId.isEmpty) return false;

    final reply = await gate.wait(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
    );
    if (reply == null) return false;

    if (reply.reject) {
      await _writeJson(request, {
        'hookSpecificOutput': {
          'hookEventName': 'PreToolUse',
          'permissionDecision': 'deny',
          'permissionDecisionReason': 'User dismissed the question',
        },
      });
      return true;
    }

    final qs = reply.questions;
    final answers = reply.answers;
    if (qs == null || answers == null || answers.isEmpty) return false;

    await _writeJson(request, {
      'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'allow',
        'updatedInput': {
          'questions': askUserQuestionsToJson(qs),
          'answers': answers,
        },
      },
    });
    return true;
  }

  /// Returns true when the HTTP response was already written.
  ///
  /// Holds ExitPlanMode `PreToolUse` until the chat card approves/rejects,
  /// then returns the official `permissionDecision` allow/deny (TUI skipped).
  Future<bool> _maybeAnswerExitPlanModeHook(
    HttpRequest request, {
    required String sessionId,
    required String memberId,
    required AgentStatusEvent event,
  }) async {
    final gate = exitPlanModeHookGate;
    if (gate == null) return false;
    final hook = event.hookEventName?.trim() ?? '';
    if (hook != 'PreToolUse' || !isExitPlanModeTool(event.toolName)) {
      return false;
    }
    final hasPlan =
        (event.planText?.trim() ?? '').isNotEmpty ||
        (event.planFilePath?.trim() ?? '').isNotEmpty;
    if (!hasPlan) return false;
    final cli = resolveCli(sessionId, memberId);
    if (cli == null) return false;
    final capability = registry.capability<ExitPlanModeCapability>(cli);
    if (capability == null || !capability.supportsInChatApproval) return false;
    final toolUseId = event.toolUseId?.trim() ?? '';
    if (toolUseId.isEmpty) return false;

    final reply = await gate.wait(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
    );
    if (reply == null) return false;

    if (reply.deny) {
      await _writeJson(request, {
        'hookSpecificOutput': {
          'hookEventName': 'PreToolUse',
          'permissionDecision': 'deny',
          'permissionDecisionReason': 'User rejected the plan',
        },
      });
      return true;
    }

    await _writeJson(request, {
      'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'allow',
      },
    });
    return true;
  }

  Map<String, Object?>? _withHookEventName(
    Map<String, Object?>? body,
    String? queryEvent,
  ) {
    if (body == null) return null;
    final existing = body['hook_event_name']?.toString().trim() ?? '';
    if (existing.isNotEmpty) return body;
    final event = queryEvent?.trim() ?? '';
    if (event.isEmpty) return body;
    return {...body, 'hook_event_name': event};
  }

  Future<Map<String, Object?>?> _readJsonBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    var overflow = false;
    await for (final chunk in request) {
      if (overflow) continue;
      builder.add(chunk);
      if (builder.length > agentStatusMaxBodyBytes) {
        overflow = true;
        builder.clear();
      }
    }
    if (overflow) return null;

    final bytes = builder.takeBytes();
    if (bytes.isEmpty) return null;

    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeOkEmpty(HttpRequest request) async {
    await _writeJson(request, const <String, Object?>{});
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      )
      ..write(jsonEncode(body));
    await request.response.close();
  }
}
