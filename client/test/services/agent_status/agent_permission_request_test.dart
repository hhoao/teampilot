import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';

void main() {
  group('parseClaudePermissionRequest', () {
    test(
      'builds description from tool name + input preview and echoes addRules suggestions',
      () {
        final request = parseClaudePermissionRequest(
          {
            'tool_name': 'Bash',
            'tool_input': {'command': 'rm -rf node_modules'},
            'permission_suggestions': [
              {
                'type': 'addRules',
                'rules': [
                  {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
                ],
                'behavior': 'allow',
                'destination': 'localSettings',
              },
              {'type': 'setMode', 'mode': 'auto', 'destination': 'session'},
            ],
          },
          toolName: 'Bash',
          toolInputPreview: 'rm -rf node_modules',
        );
        expect(request, isNotNull);
        expect(request!.id, '');
        expect(request.description, 'Bash rm -rf node_modules');
        expect(request.patterns, isEmpty);
        // Only addRules entries become always options; setMode is skipped (v1).
        expect(request.always, hasLength(1));
        expect(request.always.first.label, 'Bash(rm -rf node_modules)');
        expect(request.always.first.payload, isA<Map<String, Object?>>());
        expect((request.always.first.payload as Map)['type'], 'addRules');
      },
    );

    test('whole-tool addRules suggestion has bare tool label', () {
      final request = parseClaudePermissionRequest(
        {
          'tool_name': 'WebFetch',
          'tool_input': {'url': 'https://example.com'},
          'permission_suggestions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'WebFetch'},
              ],
              'behavior': 'allow',
              'destination': 'session',
            },
          ],
        },
        toolName: 'WebFetch',
        toolInputPreview: 'https://example.com',
      );
      expect(request!.always.first.label, 'WebFetch');
    });

    test('returns null without a tool name', () {
      expect(
        parseClaudePermissionRequest(
          const {},
          toolName: '',
          toolInputPreview: null,
        ),
        isNull,
      );
    });

    test('description falls back to tool name without input preview', () {
      final request = parseClaudePermissionRequest(
        {'tool_name': 'Bash'},
        toolName: 'Bash',
        toolInputPreview: null,
      );
      expect(request!.description, 'Bash');
    });
  });

  group('parsePermissionRequest (OpenCode)', () {
    test(
      'always prefixes map to options with null payload and prefix label',
      () {
        final request = parsePermissionRequest(const {
          'request_id': 'perm-1',
          'permission': 'Run `npm install`',
          'always': ['Bash', 'Bash(npm install:*)'],
        });
        expect(request!.always, hasLength(2));
        expect(request.always.first.label, 'Bash');
        expect(request.always.first.payload, isNull);
      },
    );
  });
}
