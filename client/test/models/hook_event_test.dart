import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  group('HookEvent', () {
    test('intercepting events', () {
      expect(HookEvent.preToolUse.isIntercepting, isTrue);
      expect(HookEvent.permissionRequest.isIntercepting, isTrue);
      expect(HookEvent.shellCommandRequest.isIntercepting, isTrue);
      expect(HookEvent.stop.isIntercepting, isFalse);
      expect(HookEvent.sessionStart.isIntercepting, isFalse);
    });
  });

  group('HookEventCapability.matrix', () {
    test('claude native event names are PascalCase', () {
      expect(
        HookEventCapability.nativeEvent(HookEvent.preToolUse, CliTool.claude),
        'PreToolUse',
      );
      expect(
        HookEventCapability.nativeEvent(HookEvent.stop, CliTool.flashskyai),
        'Stop',
      );
    });

    test('codex supports shellCommandRequest; claude does not', () {
      expect(
        HookEventCapability.supports(
          HookEvent.shellCommandRequest,
          CliTool.codex,
        ),
        isTrue,
      );
      expect(
        HookEventCapability.supports(
          HookEvent.shellCommandRequest,
          CliTool.claude,
        ),
        isFalse,
      );
    });

    test('cursor events are lowercase with beforeSubmitPrompt', () {
      expect(
        HookEventCapability.nativeEvent(
          HookEvent.userPromptSubmit,
          CliTool.cursor,
        ),
        'beforeSubmitPrompt',
      );
      expect(
        HookEventCapability.supports(HookEvent.sessionStart, CliTool.cursor),
        isTrue,
      );
      expect(
        HookEventCapability.support(
          HookEvent.permissionRequest,
          CliTool.cursor,
        ).supported,
        isFalse,
      );
    });

    test('opencode bridge events are approximate', () {
      final support = HookEventCapability.support(
        HookEvent.preToolUse,
        CliTool.opencode,
      );
      expect(support.supported, isTrue);
      expect(support.approximate, isTrue);
      expect(support.nativeEvent, 'tool.execute.before');
    });

    test('unknown combo falls back to unsupported', () {
      expect(
        HookEventCapability.support(
          HookEvent.notification,
          CliTool.opencode,
        ).supported,
        isFalse,
      );
    });
  });
}
