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
            'header': 'Plan',
            'options': [
              {'label': 'Fix', 'description': 'Fix the bug now'},
              {'label': 'Skip'},
            ],
          },
        ],
      });
      expect(q, hasLength(1));
      expect(q!.single.header, 'Plan');
      expect(q.single.options[0].label, 'Fix');
      expect(q.single.options[0].description, 'Fix the bug now');
      expect(q.single.options[1].description, isNull);
    });

    test('parses multiSelect and multi_select variants', () {
      final a = parseAskUserQuestions({
        'questions': [
          {
            'question': 'q',
            'options': ['a'],
            'multiSelect': true,
          },
        ],
      });
      expect(a!.single.multiSelect, isTrue);
      final b = parseAskUserQuestions({
        'questions': [
          {
            'question': 'q',
            'options': ['a'],
            'multi_select': true,
          },
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
            {
              'options': ['a'],
            },
          ],
        }),
        isNull,
      );
      // At least one valid entry wins over malformed siblings.
      final q = parseAskUserQuestions({
        'questions': [
          {'question': 'bad'},
          {
            'question': 'good',
            'options': ['a'],
          },
        ],
      });
      expect(q, hasLength(1));
      expect(q!.single.question, 'good');
    });

    test('skips empty option labels', () {
      final q = parseAskUserQuestions({
        'questions': [
          {
            'question': 'q',
            'options': [
              '',
              {'label': '  '},
            ],
          },
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

    test('parses Cursor prompt / title / allow_multiple aliases', () {
      final q = parseAskUserQuestions({
        'questions': [
          {
            'id': 'weather',
            'prompt': 'How is the weather today?',
            'allow_multiple': false,
            'options': [
              {'id': 'sunny', 'label': 'Sunny'},
              {'id': 'rainy', 'label': 'Rainy'},
            ],
          },
          {
            'id': 'drinks',
            'title': 'What drinks do you like?',
            'allow_multiple': true,
            'options': [
              {'id': 'coffee', 'label': 'Coffee'},
              {'id': 'tea', 'label': 'Tea'},
            ],
          },
        ],
      });
      expect(q, hasLength(2));
      expect(q![0].id, 'weather');
      expect(q[0].question, 'How is the weather today?');
      expect(q[0].multiSelect, isFalse);
      expect(q[0].options[0].id, 'sunny');
      expect(q[1].question, 'What drinks do you like?');
      expect(q[1].multiSelect, isTrue);
    });
  });

  group('parseQuestionsList', () {
    test('parses a raw questions array (opencode top-level body)', () {
      final q = parseQuestionsList([
        {
          'question': 'OK?',
          'options': ['Yes', 'No'],
        },
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

  group('parseAskUserAnswers', () {
    const weather = AgentAskUserQuestion(
      question: 'How is the weather today?',
      id: 'weather',
      options: [
        AgentAskUserOption(label: 'Sunny', id: 'sunny'),
        AgentAskUserOption(label: 'Rainy', id: 'rainy'),
      ],
    );
    const drinks = AgentAskUserQuestion(
      question: 'What drinks do you like?',
      id: 'drinks',
      multiSelect: true,
      options: [
        AgentAskUserOption(label: 'Coffee', id: 'coffee'),
        AgentAskUserOption(label: 'Tea', id: 'tea'),
        AgentAskUserOption(label: 'Water', id: 'water'),
      ],
    );

    test('reads Claude answers map keyed by question text', () {
      final answers = parseAskUserAnswers(
        questions: const [weather, drinks],
        result: {
          'answers': {
            'How is the weather today?': 'Sunny',
            'What drinks do you like?': 'Coffee, Tea',
          },
        },
      );
      expect(answers, ['Sunny', 'Coffee, Tea']);
    });

    test('reads OpenCode list-of-lists aligned with questions', () {
      final answers = parseAskUserAnswers(
        questions: const [weather, drinks],
        result: {
          'answers': [
            ['Sunny'],
            ['Coffee', 'Tea'],
          ],
        },
      );
      expect(answers, ['Sunny', 'Coffee, Tea']);
    });

    test('maps Cursor option ids and question ids to labels', () {
      final answers = parseAskUserAnswers(
        questions: const [weather, drinks],
        result: {
          'answers': [
            {
              'id': 'weather',
              'selected': ['sunny'],
            },
            {
              'id': 'drinks',
              'selected': ['coffee', 'tea'],
            },
          ],
        },
      );
      expect(answers, ['Sunny', 'Coffee, Tea']);
    });

    test('decodes JSON string results and leaves missing answers null', () {
      final answers = parseAskUserAnswers(
        questions: const [weather, drinks],
        result: '{"answers":{"How is the weather today?":"Sunny"}}',
      );
      expect(answers, ['Sunny', isNull]);
    });

    test('uses a raw string result as the first question answer', () {
      final answers = parseAskUserAnswers(
        questions: const [weather],
        result: 'Sunny',
      );
      expect(answers, ['Sunny']);
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
              {
                'question': 'OK?',
                'options': ['Yes', 'No'],
              },
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
