import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('round-trips every field', () {
    const event = SessionUsageEvent(
      requestId: 'claude:msg_1',
      cli: CliTool.claude,
      model: 'claude-sonnet-4',
      inputTokens: 100,
      outputTokens: 40,
      cacheReadTokens: 25,
      cacheCreationTokens: 10,
      cacheCreation1hTokens: 5,
      inputSemantics: UsageInputSemantics.fresh,
      timestampMs: 1720612802000,
      sessionId: 's1',
      memberId: 'dev-0',
      teamId: 'team1',
      isFinal: true,
      costMicroUsd: 1234,
    );

    final decoded = SessionUsageEvent.fromJson(event.toJson());

    expect(decoded, event);
    expect(decoded.toJson(), event.toJson());
    expect(decoded.freshInputTokens, 100);
    expect(decoded.hasBillableTokens, isTrue);
  });

  test('total semantics subtracts cache from fresh input', () {
    const event = SessionUsageEvent(
      requestId: 'codex:t:1',
      cli: CliTool.codex,
      model: 'gpt-5',
      inputTokens: 100,
      outputTokens: 10,
      cacheReadTokens: 30,
      cacheCreationTokens: 5,
      inputSemantics: UsageInputSemantics.total,
      timestampMs: 1,
      sessionId: 's1',
    );

    expect(event.freshInputTokens, 65);
  });

  test('zero-token event is not billable', () {
    expect(
      const SessionUsageEvent(
        requestId: 'x',
        cli: CliTool.claude,
        model: '',
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheCreationTokens: 0,
        inputSemantics: UsageInputSemantics.fresh,
        timestampMs: 0,
        sessionId: '',
      ).hasBillableTokens,
      isFalse,
    );
  });
}
