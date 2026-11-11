import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/ai_message_strings_from_l10n.dart';

void main() {
  test('same locale input yields the same strings instance', () {
    final l10n = AppLocalizationsEn();

    final first = aiMessageStringsFromL10n(l10n);
    final second = aiMessageStringsFromL10n(l10n);

    // `AiMessageStringsScope` notifies by identity, so reusing the instance is
    // what keeps chain-of-thought blocks from rebuilding on every streamed
    // chunk of the surrounding transcript.
    expect(identical(first, second), isTrue);
  });

  test('the thinking-process stats flag is part of the key', () {
    final l10n = AppLocalizationsEn();

    final plain = aiMessageStringsFromL10n(l10n);
    final withStats = aiMessageStringsFromL10n(
      l10n,
      thinkingProcessToolCalls: true,
    );

    expect(identical(plain, withStats), isFalse);
    expect(plain.formatThinkingProcessStats, isNull);
    expect(withStats.formatThinkingProcessStats, isNotNull);
    // Cached entries stay addressable in both shapes.
    expect(
      identical(aiMessageStringsFromL10n(l10n), plain),
      isTrue,
    );
  });

  test('a different CLI label yields different strings', () {
    final l10n = AppLocalizationsEn();

    final generic = aiMessageStringsFromL10n(l10n);
    final claude = aiMessageStringsFromL10n(l10n, permissionCliName: 'Claude');

    expect(identical(generic, claude), isFalse);
  });

  test('separate AppLocalizations instances for one locale share strings', () {
    // Hosts resolve l10n through different paths and can hand back a fresh
    // instance per build; the cache must key on locale, not on the object.
    final a = AppLocalizationsEn();
    final b = AppLocalizationsEn();
    expect(identical(a, b), isFalse, reason: 'distinct instances');

    expect(
      identical(
        aiMessageStringsFromL10n(a),
        aiMessageStringsFromL10n(b),
      ),
      isTrue,
    );
  });

  test('cache stats record a miss then a hit', () {
    final l10n = AppLocalizationsEn();
    const probeCli = 'StatsProbeCli';
    final missesBefore = aiMessageStringsCacheStats.misses;
    final hitsBefore = aiMessageStringsCacheStats.hits;

    aiMessageStringsFromL10n(l10n, permissionCliName: probeCli);
    expect(aiMessageStringsCacheStats.misses, missesBefore + 1);

    aiMessageStringsFromL10n(l10n, permissionCliName: probeCli);
    expect(aiMessageStringsCacheStats.misses, missesBefore + 1);
    expect(aiMessageStringsCacheStats.hits, greaterThan(hitsBefore));
  });
}
