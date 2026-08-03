import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_normalizer.dart';
import 'package:teampilot/services/agent_status/ask_user_question.dart';

void main() {
  group('parseAskUserQuestions', () {
    test('parses string options', () {
      final q = parseAskUserQuestions({
        'questions': [
          {
            'question': 'Pick a language',
            'options': ['Dart', 'Rust'],
            'multiSelect': false,
          },
        ],
      });
      expect(q, hasLength(1));
      expect(q!.single.question, 'Pick a language');
      expect(q.single.options.map((o) => o.label), ['Dart', 'Rust']);
      expect(q.single.options.every((o) => o.description == null), isTrue);
      expect(q.single.multiSelect, isFalse);
    });

    test('parses object options with description', () {
      final q = parseAskUserQuestions({
        'questions': [
          {
            'question': 'How to proceed?',
            'options': [
              {'label': 'Fix', 'description': 'Fix the bug now'},
              {'label': 'Skip'},
            ],
          },
        ],
      });
      expect(q, hasLength(1));
      expect(q!.single.options[0].label, 'Fix');
      expect(q.single.options[0].description, 'Fix the bug now');
      expect(q.single.options[1].description, isNull);
    });

    test('parses multiSelect and multi_select variants', () {
      final a = parseAskUserQuestions({
        'questions': [
          {'question': 'q', 'options': ['a'], 'multiSelect': true},
        ],
      });
      expect(a!.single.multiSelect, isTrue);
      final b = parseAskUserQuestions({
        'questions': [
          {'question': 'q', 'options': ['a'], 'multi_select': true},
        ],
      });
      expect(b!.single.multiSelect, isTrue);
    });

    test('returns null for malformed inputs', () {
      expect(parseAskUserQuestions(null), isNull);
      expect(parseAskUserQuestions('not-a-map'), isNull);
      expect(parseAskUserQuestions({'questions': []}), isNull);
      expect(parseAskUserQuestions({'questions': 'nope'}), isNull);
      // Entries without a question text or options are skipped.
      expect(
        parseAskUserQuestions({
          'questions': [
            {'question': '   '},
            {'options': ['a']},
          ],
        }),
        isNull,
      );
      // At least one valid entry wins over malformed siblings.
      final q = parseAskUserQuestions({
        'questions': [
          {'question': 'bad'},
          {'question': 'good', 'options': ['a']},
        ],
      });
      expect(q, hasLength(1));
      expect(q!.single.question, 'good');
    });

    test('skips empty option labels', () {
      final q = parseAskUserQuestions({
        'questions': [
          {'question': 'q', 'options': ['', {'label': '  '}]},
        ],
      });
      // No usable options → entry dropped → null.
      expect(q, isNull);
    });

    test('parses opencode variants (multiple + explanation)', () {
      final q = parseAskUserQuestions({
        'questions': [
          {
            'question': 'Which stack?',
            'options': [
              {'label': 'Flutter', 'explanation': 'Cross-platform UI'},
              {'label': 'React Native'},
            ],
            'multiple': true,
          },
        ],
      });
      expect(q, hasLength(1));
      expect(q!.single.multiSelect, isTrue);
      expect(q.single.options[0].label, 'Flutter');
      expect(q.single.options[0].description, 'Cross-platform UI');
      expect(q.single.options[1].description, isNull);
    });
  });

  group('parseQuestionsList', () {
    test('parses a raw questions array (opencode top-level body)', () {
      final q = parseQuestionsList([
        {'question': 'OK?', 'options': ['Yes', 'No']},
      ]);
      expect(q, hasLength(1));
      expect(q!.single.question, 'OK?');
    });

    test('returns null for non-list or empty input', () {
      expect(parseQuestionsList(null), isNull);
      expect(parseQuestionsList('nope'), isNull);
      expect(parseQuestionsList(const []), isNull);
    });
  });

  group('AgentStatusNormalizer AskUserQuestion payload', () {
    test('attaches questions to AskUserQuestion PreToolUse waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'AskUserQuestion',
          'tool_use_id': 'toolu-q1',
          'tool_input': {
            'questions': [
              {'question': 'OK?', 'options': ['Yes', 'No']},
            ],
          },
        },
      );
      expect(e?.state, AgentSeatAttention.waiting);
      expect(e?.askUserQuestions, hasLength(1));
      expect(e?.askUserQuestions?.single.question, 'OK?');
      expect(e?.askUserQuestions?.single.options, hasLength(2));
      expect(e?.toolUseId, 'toolu-q1');
    });

    test('does not attach questions for non-AskUserQuestion tools', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'Bash',
          'tool_input': {'command': 'ls'},
        },
      );
      expect(e?.state, AgentSeatAttention.working);
      expect(e?.askUserQuestions, isNull);
    });

    test('PermissionRequest carries no questions', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PermissionRequest', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
      expect(e?.askUserQuestions, isNull);
    });
  });
}
