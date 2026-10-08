import '../../cancellation.dart';
import '../../team_bus.dart';
import '../jsonrpc.dart';
import '../toolkit/mcp_schema.dart';
import '../toolkit/mcp_tool_response.dart';
import '../toolkit/teammate_bus_tool.dart';
import '../toolkit/teammate_bus_tool_call.dart';
import '../toolkit/teammate_bus_tool_format.dart';
import '../toolkit/teammate_bus_tool_name.dart';
import '../toolkit/wait_delivery.dart';

final class WaitForMessageTool extends TeammateBusTool {
  const WaitForMessageTool();

  @override
  TeammateBusToolName get name => TeammateBusToolName.waitForMessage;

  @override
  String get description =>
      'Your single idle loop. Blocks indefinitely until there is something '
      'to do, then returns ONE JSON shape: (a) {"messages":[...]} for '
      'teammate/operator mail, or (b) a bare task object '
      '(id/status/title/brief) already claimed for you from the shared '
      'work queue. Distinguish by top-level keys (messages vs id/title). '
      'If a task, do it and report via update_task; if messages, handle '
      'them. Either way, call wait_for_message again afterwards. User '
      'input while you wait arrives as from:"user" in the messages array. '
      '(Team leads only ever receive messages here.)';

  @override
  Map<String, Object?> get inputSchema => McpSchema.object();

  @override
  Future<JsonRpcResponse> call(TeammateBusToolCall call) async {
    _noteEnteredWaitLoop(call);
    return _respond(
      call,
      await call.bus.receiveWork(call.memberId),
      acknowledgeMessages: true,
    );
  }

  /// SSE path: receive work without marking read until the client confirms.
  static Future<WaitDelivery> beginStreamWait(
    TeammateBusToolCall call, {
    CancellationToken? cancel,
  }) async {
    _noteEnteredWaitLoop(call);
    final outcome = await call.bus.receiveWork(call.memberId, cancel: cancel);
    switch (outcome) {
      case MessageWork(:final messages):
        final ids = [for (final message in messages) message.id];
        return WaitDelivery(
          response: _encodeOutcome(call.requestId, outcome),
          confirm: () => call.bus.acknowledgeDelivery(call.memberId, ids),
          abort: () => call.bus.redeliver(call.memberId, messages),
        );
      case TaskWork(:final task):
        return WaitDelivery(
          response: _encodeOutcome(call.requestId, outcome),
          confirm: () async {},
          abort: () => call.bus.releaseTask(task.id),
        );
      case EmptyWork():
        return WaitDelivery(
          response: _encodeOutcome(call.requestId, outcome),
          confirm: () async {},
          abort: () {},
        );
    }
  }

  static void _noteEnteredWaitLoop(TeammateBusToolCall call) {
    call.ctx.onEnteredWaitLoop?.call(call.memberId);
  }

  static Future<JsonRpcResponse> _respond(
    TeammateBusToolCall call,
    WorkBatch outcome, {
    required bool acknowledgeMessages,
  }) async {
    if (acknowledgeMessages) {
      switch (outcome) {
        case MessageWork(:final messages):
          await call.bus.acknowledgeDelivery(call.memberId, [
            for (final message in messages) message.id,
          ]);
        case TaskWork() || EmptyWork():
          break;
      }
    }
    return _encodeOutcome(call.requestId, outcome);
  }

  static JsonRpcResponse _encodeOutcome(Object? requestId, WorkBatch outcome) {
    switch (outcome) {
      case MessageWork(:final messages):
        return McpToolResponse.ok(
          requestId,
          TeammateBusToolFormat.encodeBatch(messages),
        );
      case TaskWork(:final task):
        return McpToolResponse.ok(
          requestId,
          TeammateBusToolFormat.encodeTaskAssignment(task),
        );
      case EmptyWork():
        return McpToolResponse.ok(
          requestId,
          TeammateBusToolFormat.encodeBatch(const []),
        );
    }
  }
}
