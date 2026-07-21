import 'package:mock_model_gateway/core/scenario_engine.dart';
import 'package:mock_model_gateway/core/turns.dart';
import 'package:test/test.dart';

void main() {
  test('advances turns per actor and exhausts loudly', () {
    final engine = ScenarioEngine({
      'a': MockScenario(
        turns: [
          TextTurn('one'),
          TextTurn('two'),
          TextTurn('three'),
        ],
      ),
    });
    expect(engine.nextTurn('a'), isA<TextTurn>());
    expect(engine.nextTurn('a'), isA<TextTurn>());
    expect(engine.nextTurn('a'), isA<TextTurn>());
    expect(() => engine.nextTurn('a'), throwsStateError);
  });

  test('resolves toolRef via ToolNameResolver', () {
    final engine = ScenarioEngine(
      {
        'a': MockScenario(
          turns: [
            ToolUseTurn(
              id: '1',
              toolRef: 'teambus.send_message',
              input: {'to': 'w'},
            ),
          ],
        ),
      },
      toolNames: (ref) =>
          'mcp__teammate-bus__$ref'.replaceAll('teambus.', ''),
    );
    final turn = engine.nextResolvedTurn('a');
    expect(turn, isA<ResolvedToolUseTurn>());
    expect(
      (turn as ResolvedToolUseTurn).wireName,
      'mcp__teammate-bus__send_message',
    );
  });
}
