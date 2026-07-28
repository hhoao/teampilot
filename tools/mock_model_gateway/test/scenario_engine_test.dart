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
    expect((engine.nextTurn('a') as TextTurn).text, 'one');
    expect((engine.nextTurn('a') as TextTurn).text, 'two');
    expect((engine.nextTurn('a') as TextTurn).text, 'three');
    expect(() => engine.nextTurn('a'), throwsStateError);
  });

  test('keeps independent turn indices per actor', () {
    final engine = ScenarioEngine({
      'lead': MockScenario(
        turns: [
          TextTurn('lead-1'),
          TextTurn('lead-2'),
        ],
      ),
      'worker': MockScenario(
        turns: [
          TextTurn('worker-1'),
          TextTurn('worker-2'),
        ],
      ),
    });

    expect((engine.nextTurn('lead') as TextTurn).text, 'lead-1');
    expect((engine.nextTurn('worker') as TextTurn).text, 'worker-1');
    expect((engine.nextTurn('lead') as TextTurn).text, 'lead-2');
    expect((engine.nextTurn('worker') as TextTurn).text, 'worker-2');
    expect(() => engine.nextTurn('lead'), throwsStateError);
    expect(() => engine.nextTurn('worker'), throwsStateError);
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

  test('resetActor rewinds one seat without touching others', () {
    final engine = ScenarioEngine({
      'lead': MockScenario(
        turns: [
          TextTurn('lead-1'),
          TextTurn('lead-2'),
        ],
      ),
      'worker': MockScenario(
        turns: [
          TextTurn('worker-1'),
          TextTurn('worker-2'),
        ],
      ),
    });

    expect((engine.nextTurn('lead') as TextTurn).text, 'lead-1');
    expect((engine.nextTurn('worker') as TextTurn).text, 'worker-1');
    expect(engine.peekTurnIndex('lead'), 1);
    expect(engine.peekTurnIndex('worker'), 1);

    engine.resetActor('lead');
    expect(engine.peekTurnIndex('lead'), 0);
    expect(engine.peekTurnIndex('worker'), 1);
    expect((engine.nextTurn('lead') as TextTurn).text, 'lead-1');
    expect((engine.nextTurn('worker') as TextTurn).text, 'worker-2');
  });

  test('resetActor rejects unknown actors', () {
    final engine = ScenarioEngine({
      'lead': MockScenario(turns: [TextTurn('lead-1')]),
    });
    expect(() => engine.resetActor('missing'), throwsStateError);
  });

  test('resolves AssignedTaskUpdateTurn toolRef via ToolNameResolver', () {
    final engine = ScenarioEngine(
      {
        'a': MockScenario(
          turns: [
            AssignedTaskUpdateTurn(
              id: 'task-1',
              toolRef: 'teambus.update_task',
              status: 'completed',
              result: 'done',
            ),
          ],
        ),
      },
      toolNames: (ref) =>
          'mcp__teammate-bus__$ref'.replaceAll('teambus.', ''),
    );
    final turn = engine.nextResolvedTurn('a');
    expect(turn, isA<ResolvedAssignedTaskUpdateTurn>());
    final resolved = turn as ResolvedAssignedTaskUpdateTurn;
    expect(resolved.wireName, 'mcp__teammate-bus__update_task');
    expect(resolved.id, 'task-1');
    expect(resolved.status, 'completed');
    expect(resolved.result, 'done');
  });
}
