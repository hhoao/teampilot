import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/compose/compose_landing_bundle.dart';
import 'package:teampilot/services/compose/compose_slash_catalog.dart';
import 'package:teampilot/services/compose/compose_trigger_insert.dart';
import 'package:teampilot/services/compose/compose_trigger_query.dart';
import 'package:flutter/material.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/skill.dart';

void main() {
  group('detectComposeTrigger', () {
    test('detects @ file token at cursor', () {
      const text = 'please read @src/ma';
      final trigger = detectComposeTrigger(text, text.length);
      expect(trigger?.kind, ComposeTriggerKind.fileReference);
      expect(trigger?.query, 'src/ma');
      expect(trigger?.triggerStart, 12);
    });

    test('detects / slash token at line start', () {
      const text = '/brain';
      final trigger = detectComposeTrigger(text, text.length);
      expect(trigger?.kind, ComposeTriggerKind.slashInvoke);
      expect(trigger?.query, 'brain');
      expect(trigger?.triggerStart, 0);
    });

    test('ignores @ inside email-like token', () {
      const text = 'mail user@host';
      expect(detectComposeTrigger(text, text.length), isNull);
    });

    test('ignores stale @ after whitespace boundary', () {
      const text = '@file done ';
      expect(detectComposeTrigger(text, text.length), isNull);
    });
  });

  group('replaceComposeTrigger', () {
    test('replaces active token and leaves trailing space', () {
      final controller = TextEditingController(text: 'run /bra');
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
      final trigger = detectComposeTrigger(controller.text, controller.text.length)!;

      controller.value = replaceComposeTrigger(
        controller,
        trigger,
        '/brainstorming',
      );

      expect(controller.text, 'run /brainstorming ');
      expect(controller.selection.baseOffset, 19);
    });
  });

  group('buildComposeSlashCandidates', () {
    test('includes only bundle-enabled skills and plugin commands', () {
      final candidates = buildComposeSlashCandidates(
        skills: const [
          Skill(
            id: 's1',
            name: 'Brainstorm',
            description: '',
            directory: 'brainstorming',
            installedAt: 0,
            updatedAt: 0,
          ),
          Skill(
            id: 's2',
            name: 'Other',
            description: '',
            directory: 'other-skill',
            installedAt: 0,
            updatedAt: 0,
          ),
        ],
        plugins: const [
          Plugin(
            id: 'p1',
            name: 'Review',
            description: '',
            version: '1.0.0',
            directory: 'review',
            capabilities: PluginCapabilities(
              commands: [PluginCommand(name: 'review-pr')],
            ),
            installedAt: 0,
            updatedAt: 0,
          ),
        ],
        enabledBundle: const ConfigBundle(
          skillIds: ['s1'],
          pluginIds: ['p1'],
        ),
        query: 'brain',
      );

      expect(candidates.map((c) => c.insertText), ['/brainstorming']);
    });
  });

  group('unionConfigBundles', () {
    test('merges ids from identity and workspace without duplicates', () {
      final effective = unionConfigBundles(
        const ConfigBundle(skillIds: ['a', 'b'], pluginIds: ['p1']),
        const ConfigBundle(skillIds: ['b', 'c'], pluginIds: ['p1', 'p2']),
      );

      expect(effective.skillIds, ['a', 'b', 'c']);
      expect(effective.pluginIds, ['p1', 'p2']);
    });

    test('returns identity ids when workspace is empty', () {
      expect(
        unionConfigBundles(
          const ConfigBundle(skillIds: ['a']),
          const ConfigBundle(),
        ).skillIds,
        ['a'],
      );
    });
  });
}
