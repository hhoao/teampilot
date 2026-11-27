import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/ai_message_strings_from_l10n.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('stats hook is absent by default (PTY path)', () {
    final strings = aiMessageStringsFromL10n(l10n);
    expect(strings.formatThinkingProcessStats, isNull);
  });

  test('stats hook formats steps and tool calls when enabled (ACP path)', () {
    final strings = aiMessageStringsFromL10n(
      l10n,
      thinkingProcessToolCalls: true,
    );
    final hook = strings.formatThinkingProcessStats;
    expect(hook, isNotNull);
    expect(hook!(1, 2), 'Thinking process · 1 steps · 2 tool calls');
  });

  test('activity labels use unified English action copy', () {
    final strings = aiMessageStringsFromL10n(l10n);
    expect(strings.reasoningLabel(running: false), 'Thought');
    expect(strings.reasoningLabel(running: true), 'Thinking');
    expect(
      strings.toolActivityLabel(AiToolCallCategory.command, running: false),
      'Terminal command ran',
    );
    expect(
      strings.toolActivityLabel(AiToolCallCategory.command, running: true),
      'Running terminal command',
    );
    expect(
      strings.toolActivityLabel(AiToolCallCategory.edit, running: false),
      'Edit file',
    );
    expect(
      strings.toolActivityLabel(AiToolCallCategory.read, running: false),
      'Read file',
    );
  });

  test('activity labels use unified Chinese action copy', () {
    final strings = aiMessageStringsFromL10n(AppLocalizationsZh());
    expect(strings.reasoningLabel(running: false), '已思考');
    expect(strings.reasoningLabel(running: true), '思考中');
    expect(
      strings.toolActivityLabel(AiToolCallCategory.command, running: false),
      '终端命令已运行',
    );
    expect(
      strings.toolActivityLabel(AiToolCallCategory.command, running: true),
      '正在运行终端命令',
    );
    expect(
      strings.toolActivityLabel(AiToolCallCategory.edit, running: false),
      '编辑文件',
    );
    expect(
      strings.toolActivityLabel(AiToolCallCategory.read, running: false),
      '读取文件',
    );
  });
}
