import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/scenarios/ping_pong_mixed_claude.dart';
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
}
