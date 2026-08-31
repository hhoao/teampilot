import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/scenarios/catalog_mcp_simple_claude.dart';
import 'package:mock_model_gateway/scenarios/doorbell_dispatch_mixed_claude.dart';
import 'package:mock_model_gateway/scenarios/mail_priority_mixed_claude.dart';
import 'package:mock_model_gateway/scenarios/mixed_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/native_collab_3plus.dart';
import 'package:mock_model_gateway/scenarios/ping_pong_mixed_claude.dart';
import 'package:mock_model_gateway/scenarios/simple_3turn.dart';
import 'package:mock_model_gateway/scenarios/task_complete_mixed_claude.dart';
import 'package:mock_model_gateway/scenarios/task_dispatch_mixed_claude.dart';
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
      expect(turns.map((t) => (t as TextTurn).text), [
        'MARK_A1',
        'MARK_A2',
        'MARK_A3',
      ]);
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
          'native.TaskGet',
        ]),
      );
      expect(
        leadTools.every((t) => t.toolRef.startsWith('native.')),
        isTrue,
        reason: 'native recipe must use logical native.* toolRefs',
      );

      final workerTools = worker.turns.whereType<ToolUseTurn>().toList();
      expect(workerTools.map((t) => t.toolRef), contains('native.TaskUpdate'));
      expect(workerTools.every((t) => t.toolRef.startsWith('native.')), isTrue);

      final workerTexts = worker.turns.whereType<TextTurn>().map((t) => t.text);
      expect(workerTexts, contains('MARK_WORKER_1'));
    });
  });

  group('legacy mixed_claude ports', () {
    void expectTeambusOnly(Map<String, MockScenario> scenarios) {
      for (final scenario in scenarios.values) {
        for (final turn in scenario.turns) {
          switch (turn) {
            case ToolUseTurn(:final toolRef):
              expect(toolRef.startsWith('teambus.'), isTrue);
              expect(toolRef.contains('mcp__'), isFalse);
            case AssignedTaskUpdateTurn(:final toolRef):
              expect(toolRef.startsWith('teambus.'), isTrue);
              expect(toolRef.contains('mcp__'), isFalse);
            case TextTurn():
              break;
          }
        }
      }
    }

    test(
      'ping_pong_mixed_claude keeps lead/worker keys and wait/send turns',
      () {
        final scenarios = pingPongMixedClaudeScenarios();
        expect(
          scenarios.keys,
          containsAll([leadScriptApiKey, workerScriptApiKey]),
        );
        expectTeambusOnly(scenarios);
        final leadTools = scenarios[leadScriptApiKey]!.turns
            .whereType<ToolUseTurn>()
            .map((t) => t.toolRef);
        expect(
          leadTools,
          containsAll(['teambus.list_teammates', 'teambus.send_message']),
        );
      },
    );

    test('task_dispatch_mixed_claude scripts add_tasks + wait claim', () {
      final scenarios = taskDispatchMixedClaudeScenarios();
      expectTeambusOnly(scenarios);
      final leadTools = scenarios[leadScriptApiKey]!.turns
          .whereType<ToolUseTurn>()
          .map((t) => t.toolRef);
      expect(leadTools, contains('teambus.add_tasks'));
      expect(taskDispatchWorkerParkOnlyScenarios(), isNotEmpty);
    });

    test('task_complete_mixed_claude scripts AssignedTaskUpdateTurn', () {
      final scenarios = taskCompleteMixedClaudeScenarios();
      expectTeambusOnly(scenarios);
      final updates = scenarios[workerScriptApiKey]!.turns
          .whereType<AssignedTaskUpdateTurn>()
          .toList();
      expect(updates, hasLength(1));
      expect(updates.single.toolRef, 'teambus.update_task');
      expect(updates.single.status, 'done');
    });

    test('mail_priority_mixed_claude sends mail before add_tasks', () {
      final scenarios = mailPriorityMixedClaudeScenarios();
      expectTeambusOnly(scenarios);
      final leadTools = scenarios[leadScriptApiKey]!.turns
          .whereType<ToolUseTurn>()
          .map((t) => t.toolRef)
          .toList();
      expect(
        leadTools.indexOf('teambus.send_message'),
        lessThan(leadTools.indexOf('teambus.add_tasks')),
      );
    });

    test('doorbell_dispatch_mixed_claude starts worker at prompt', () {
      final scenarios = doorbellDispatchMixedClaudeScenarios();
      expectTeambusOnly(scenarios);
      final workerTurns = scenarios[workerScriptApiKey]!.turns;
      expect(workerTurns.first, isA<TextTurn>());
      expect(
        workerTurns.whereType<ToolUseTurn>().first.toolRef,
        'teambus.wait_for_message',
      );
    });
  });

  group('catalog_mcp_simple_claude', () {
    test('scripts search_skills then create_skill then MARK_CATALOG_OK', () {
      final scenarios = catalogMcpSimpleClaudeScenarios();
      expect(scenarios.keys, [simpleScriptApiKey]);

      final turns = scenarios[simpleScriptApiKey]!.turns;
      expect(turns, hasLength(3));

      final tools = turns.whereType<ToolUseTurn>().toList();
      expect(tools.map((t) => t.toolRef), [
        'catalog.search_skills',
        'catalog.create_skill',
      ]);
      expect(
        tools.every((t) => t.toolRef.startsWith('catalog.')),
        isTrue,
        reason: 'catalog recipe must use logical catalog.* toolRefs, not mcp__',
      );
      expect(tools.every((t) => !t.toolRef.contains('mcp__')), isTrue);
      expect(tools[1].input['directory'], catalogL2SkillDirectory);
      expect(tools[1].input['name'], catalogL2SkillName);
      expect(tools[1].input['body'], catalogL2SkillBody);

      expect(turns.last, isA<TextTurn>());
      expect((turns.last as TextTurn).text, markCatalogOk);
    });
  });
}
