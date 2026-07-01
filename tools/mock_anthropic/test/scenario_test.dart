import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/scenarios/doorbell_dispatch_mixed_claude.dart';
import 'package:mock_anthropic/scenarios/mail_priority_mixed_claude.dart';
import 'package:mock_anthropic/scenarios/ping_pong_mixed_claude.dart';
import 'package:mock_anthropic/scenarios/task_dispatch_mixed_claude.dart';
import 'package:test/test.dart';

void main() {
  test('pingPongMixedClaude registers lead and worker scenarios', () {
    final reg = pingPongMixedClaudeScenarios();
    expect(reg.keys, containsAll([leadScriptApiKey, workerScriptApiKey]));
    expect(reg.scenarioFor(leadScriptApiKey)!.turns.length, 3);
    expect(reg.scenarioFor(workerScriptApiKey)!.turns.length, 2);
  });

  test('ScenarioRegistry advances turns per api key', () {
    final reg = ScenarioRegistry({
      'k': MockScenario(turns: [
        ToolUseTurn(id: 't1', name: 'list_teammates', input: {}),
        TextTurn('done'),
      ]),
    });
    final first = reg.nextTurn('k');
    expect(first, isA<ToolUseTurn>());
    final second = reg.nextTurn('k');
    expect(second, isA<TextTurn>());
    expect(() => reg.nextTurn('k'), throwsStateError);
  });

  test('reset restores turn indices', () {
    final reg = ScenarioRegistry({
      'k': MockScenario(turns: [TextTurn('a'), TextTurn('b')]),
    });
    reg.nextTurn('k');
    reg.reset();
    expect(reg.nextTurn('k'), isA<TextTurn>());
  });

  test('taskDispatchMixedClaude covers add_tasks and wait_for_message', () {
    final reg = taskDispatchMixedClaudeScenarios();
    final lead = reg.scenarioFor(leadScriptApiKey)!;
    expect(lead.turns.length, 4);
    expect((lead.turns[1] as ToolUseTurn).name, contains('add_tasks'));
    final worker = reg.scenarioFor(workerScriptApiKey)!;
    expect(worker.turns.length, 3);
    expect((worker.turns[0] as ToolUseTurn).name, contains('wait_for_message'));
    expect((worker.turns[1] as ToolUseTurn).name, contains('wait_for_message'));
  });

  test('doorbellDispatchMixedClaude parks after prompt doorbell', () {
    final reg = doorbellDispatchMixedClaudeScenarios();
    final worker = reg.scenarioFor(workerScriptApiKey)!;
    expect(worker.turns[0], isA<TextTurn>());
    expect((worker.turns[1] as ToolUseTurn).name, contains('wait_for_message'));
  });

  test('mailPriorityMixedClaude interleaves tasks and mail on the worker', () {
    final reg = mailPriorityMixedClaudeScenarios();
    final lead = reg.scenarioFor(leadScriptApiKey)!;
    expect(lead.turns.length, 5);
    expect((lead.turns[1] as ToolUseTurn).name, contains('send_message'));
    expect((lead.turns[2] as ToolUseTurn).name, contains('add_tasks'));
    final worker = reg.scenarioFor(workerScriptApiKey)!;
    expect(worker.turns.length, 5);
    expect((worker.turns[3] as ToolUseTurn).name, contains('wait_for_message'));
  });
}
