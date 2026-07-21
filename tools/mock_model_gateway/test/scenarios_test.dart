import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/scenarios/mixed_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/native_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:test/test.dart';

void main() {
  group('simple_3turn', () {
    test('binds simple-script to three distinct MARK_A* TextTurns', () {
      final scenarios = simple3TurnScenarios();
      expect(scenarios.keys, [simpleScriptApiKey]);
      expect(simpleScriptApiKey, 'simple-script');

      final turns = scenarios[simpleScriptApiKey]!.turns;
      expect(turns, hasLength(3));
      expect(turns, everyElement(isA<TextTurn>()));
      expect(
        turns.map((t) => (t as TextTurn).text),
        ['MARK_A1', 'MARK_A2', 'MARK_A3'],
      );
    });
  });

  group('mixed_collab_3plus', () {
    test('registers lead/worker with teambus toolRefs and ≥3 lead markers', () {
      expect(leadScriptApiKey, 'lead-script');
      expect(workerScriptApiKey, 'worker-script');

      final scenarios = mixedCollab3PlusScenarios();
      expect(
        scenarios.keys,
        containsAll([leadScriptApiKey, workerScriptApiKey]),
      );

      final lead = scenarios[leadScriptApiKey]!;
      final worker = scenarios[workerScriptApiKey]!;

      final leadTexts = lead.turns.whereType<TextTurn>().map((t) => t.text);
      expect(
        leadTexts,
        containsAll(['MARK_LEAD_1', 'MARK_LEAD_2', 'MARK_LEAD_DONE']),
      );
      expect(leadTexts.length, greaterThanOrEqualTo(3));

      final leadTools = lead.turns.whereType<ToolUseTurn>().toList();
      expect(
        leadTools.map((t) => t.toolRef),
        containsAll(['teambus.list_teammates', 'teambus.send_message']),
      );
      expect(
        leadTools.every((t) => t.toolRef.startsWith('teambus.')),
        isTrue,
        reason: 'mixed recipe must use logical teambus.* toolRefs, not mcp__',
      );

      final workerTools = worker.turns.whereType<ToolUseTurn>().toList();
      expect(
        workerTools.map((t) => t.toolRef),
        containsAll(['teambus.wait_for_message', 'teambus.send_message']),
      );
      expect(
        workerTools.every((t) => t.toolRef.startsWith('teambus.')),
        isTrue,
      );

      final workerTexts = worker.turns.whereType<TextTurn>().map((t) => t.text);
      expect(workerTexts, contains('MARK_WORKER_1'));
    });
  });

  group('native_collab_3plus', () {
    test('uses native.* toolRefs with dispatch/reply/close and ≥3 texts', () {
      final scenarios = nativeCollab3PlusScenarios();
      expect(
        scenarios.keys,
        containsAll([leadScriptApiKey, workerScriptApiKey]),
      );

      final lead = scenarios[leadScriptApiKey]!;
      final worker = scenarios[workerScriptApiKey]!;

      final leadTexts = lead.turns.whereType<TextTurn>().map((t) => t.text);
      expect(
        leadTexts,
        containsAll(['MARK_LEAD_1', 'MARK_LEAD_2', 'MARK_LEAD_DONE']),
      );
      expect(leadTexts.length, greaterThanOrEqualTo(3));

      final leadTools = lead.turns.whereType<ToolUseTurn>().toList();
      expect(
        leadTools.map((t) => t.toolRef),
        containsAll([
          'native.TeamCreate',
          'native.TaskCreate',
          'native.TeamDelete',
        ]),
      );
      expect(
        leadTools.every((t) => t.toolRef.startsWith('native.')),
        isTrue,
        reason: 'native recipe must use logical native.* toolRefs',
      );

      final workerTools = worker.turns.whereType<ToolUseTurn>().toList();
      expect(
        workerTools.map((t) => t.toolRef),
        contains('native.TaskUpdate'),
      );
      expect(
        workerTools.every((t) => t.toolRef.startsWith('native.')),
        isTrue,
      );

      final workerTexts = worker.turns.whereType<TextTurn>().map((t) => t.text);
      expect(workerTexts, contains('MARK_WORKER_1'));
    });
  });
}
