import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_constants.dart';
import 'package:teampilot/services/team_generation/mcp/toolkit/team_composer_tool_registry.dart';

void main() {
  test('composer tools advertise rich contracts and annotations', () {
    final tools = listAdvertisedTeamComposerTools();
    expect(tools.map((t) => t['name']), TeamComposerToolName.all);

    final byName = {for (final tool in tools) tool['name'] as String: tool};

    final context = byName[TeamComposerToolName.getContext]!;
    expect(context['description'], contains('planSchema'));
    expect(context['outputSchema'], isA<Map>());
    expect((context['annotations'] as Map)['readOnlyHint'], isTrue);

    final validate = byName[TeamComposerToolName.validatePlan]!;
    expect(validate['description'], contains('field-by-field'));
    final plan = ((validate['inputSchema'] as Map)['properties'] as Map)['plan']
        as Map;
    expect(plan['required'], containsAll(['team', 'members']));
    expect((plan['properties'] as Map)['team'], isA<Map>());
    expect((validate['annotations'] as Map)['idempotentHint'], isTrue);

    final finalize = byName[TeamComposerToolName.finalize]!;
    expect(finalize['description'], contains('idempotencyKey'));
    expect((finalize['annotations'] as Map)['destructiveHint'], isTrue);
    expect((finalize['annotations'] as Map)['idempotentHint'], isTrue);
    expect(finalize['outputSchema'], isA<Map>());

    final probe = byName[TeamComposerToolName.probeTargets]!;
    expect(probe['description'], contains('validatedRevision'));
    expect(
      (((probe['inputSchema'] as Map)['properties'] as Map)['refresh'] as Map)
          ['description'],
      isNotEmpty,
    );
  });
}
