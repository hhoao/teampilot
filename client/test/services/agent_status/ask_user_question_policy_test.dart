import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/agent_status/ask_user_question.dart';
import 'package:teampilot/services/agent_status/ask_user_question_policy.dart';
import 'package:teampilot/services/cli/claude/capabilities/chat_interaction.dart';
import 'package:teampilot/services/cli/cursor/capabilities/chat_interaction.dart';
import 'package:teampilot/services/cli/opencode/capabilities/chat_interaction.dart';
import 'package:teampilot/services/cli/registry/capabilities/chat_interaction_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  const permissionRequest = AgentPermissionRequest(
    id: 'perm-1',
    description: 'Run `npm install`',
  );
  const singleSelectQuestion = AgentAskUserQuestion(
    question: 'Pick one',
    options: [AgentAskUserOption(label: 'A')],
  );

  const multiSelectQuestion = AgentAskUserQuestion(
    question: 'Pick many',
    options: [
      AgentAskUserOption(label: 'A'),
      AgentAskUserOption(label: 'B'),
    ],
    multiSelect: true,
  );

  const emptyOptionsQuestion = AgentAskUserQuestion(
    question: 'No options',
    options: [],
  );

  group('shouldShowAskUserQuestionCard', () {
    test('null capability returns false', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: null,
          questions: const [singleSelectQuestion],
        ),
        isFalse,
      );
    });

    test('Cursor / none capability returns false', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const CursorChatInteraction(),
          questions: const [singleSelectQuestion],
        ),
        isFalse,
      );
    });

    test('single single-select with pty returns true', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const ClaudeChatInteraction(),
          questions: const [singleSelectQuestion],
        ),
        isTrue,
      );
    });

    test('pty allows null askRequestId for ptyPicker', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const ClaudeChatInteraction(),
          questions: const [singleSelectQuestion],
          askRequestId: null,
        ),
        isTrue,
      );
    });

    test('multi-select with pty returns true (hook updatedInput path)', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const ClaudeChatInteraction(),
          questions: const [multiSelectQuestion],
        ),
        isTrue,
      );
    });

    test('multi-select with OpenCode returns true when askRequestId present', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const OpencodeChatInteraction(),
          questions: const [multiSelectQuestion],
          askRequestId: 'req-1',
        ),
        isTrue,
      );
    });

    test('pluginSdkReply missing askRequestId returns false', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const OpencodeChatInteraction(),
          questions: const [singleSelectQuestion],
          askRequestId: null,
        ),
        isFalse,
      );
    });

    test('empty options on single single-select returns false', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const ClaudeChatInteraction(),
          questions: const [emptyOptionsQuestion],
        ),
        isFalse,
      );
    });

    test('multiple single-select questions with pty returns true', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const ClaudeChatInteraction(),
          questions: const [
            singleSelectQuestion,
            AgentAskUserQuestion(
              question: 'Second',
              options: [AgentAskUserOption(label: 'B')],
            ),
          ],
        ),
        isTrue,
      );
    });

    test('multiple questions with multiSelect still require multiSelect support',
        () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const ClaudeChatInteraction(),
          questions: const [
            singleSelectQuestion,
            multiSelectQuestion,
          ],
        ),
        isTrue,
      );
    });

    test('multiple questions with OpenCode returns true when askRequestId present',
        () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const OpencodeChatInteraction(),
          questions: const [
            singleSelectQuestion,
            AgentAskUserQuestion(
              question: 'Second',
              options: [AgentAskUserOption(label: 'B')],
            ),
          ],
          askRequestId: 'req-2',
        ),
        isTrue,
      );
    });

    test('null or empty questions returns false', () {
      expect(
        shouldShowAskUserQuestionCard(
          capability: const ClaudeChatInteraction(),
          questions: null,
        ),
        isFalse,
      );
      expect(
        shouldShowAskUserQuestionCard(
          capability: const ClaudeChatInteraction(),
          questions: const [],
        ),
        isFalse,
      );
    });
  });

  group('shouldShowPermissionCard', () {
    test('null capability returns false', () {
      expect(
        shouldShowPermissionCard(
          capability: null,
          permissionRequest: permissionRequest,
          askRequestId: 'perm-1',
        ),
        isFalse,
      );
    });

    test('Claude family capability returns true', () {
      expect(
        shouldShowPermissionCard(
          capability: const ClaudeChatInteraction(),
          permissionRequest: permissionRequest,
          askRequestId: 'perm-1',
        ),
        isTrue,
      );
    });

    test('Cursor capability (no in-chat reply) returns false', () {
      expect(
        shouldShowPermissionCard(
          capability: const CursorChatInteraction(),
          permissionRequest: permissionRequest,
          askRequestId: 'perm-1',
        ),
        isFalse,
      );
    });

    test('OpenCode with payload and id returns true', () {
      expect(
        shouldShowPermissionCard(
          capability: const OpencodeChatInteraction(),
          permissionRequest: permissionRequest,
          askRequestId: 'perm-1',
        ),
        isTrue,
      );
    });

    test('OpenCode missing askRequestId returns false', () {
      expect(
        shouldShowPermissionCard(
          capability: const OpencodeChatInteraction(),
          permissionRequest: permissionRequest,
          askRequestId: null,
        ),
        isFalse,
      );
    });

    test('OpenCode without payload returns false', () {
      expect(
        shouldShowPermissionCard(
          capability: const OpencodeChatInteraction(),
          permissionRequest: null,
          askRequestId: 'perm-1',
        ),
        isFalse,
      );
    });

    test('hook-hold channel needs no request id', () {
      final claude = CliToolRegistry.builtIn()
          .capability<ChatInteractionCapability>(CliTool.claude);
      expect(
        shouldShowPermissionCard(
          capability: claude,
          permissionRequest: AgentPermissionRequest(
            id: '',
            description: 'Bash rm -rf node_modules',
          ),
          askRequestId: null,
        ),
        isTrue,
      );
    });

    test('plugin-SDK channel still requires a request id', () {
      final opencode = CliToolRegistry.builtIn()
          .capability<ChatInteractionCapability>(CliTool.opencode);
      expect(
        shouldShowPermissionCard(
          capability: opencode,
          permissionRequest: AgentPermissionRequest(
            id: '',
            description: 'Run `npm install`',
          ),
          askRequestId: null,
        ),
        isFalse,
      );
    });
  });
}
