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
}
