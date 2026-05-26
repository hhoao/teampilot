import 'package:teampilot/services/app/flashskyai_agent_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agentIdFromMdFilename', () {
    test('strips .md extension', () {
      expect(
        FlashskyaiAgentCatalogService.agentIdFromMdFilename(
          'image-analyzer.md',
        ),
        'image-analyzer',
      );
      expect(
        FlashskyaiAgentCatalogService.agentIdFromMdFilename('test-runner.md'),
        'test-runner',
      );
    });

    test('rejects non-markdown and hidden names', () {
      expect(
        FlashskyaiAgentCatalogService.agentIdFromMdFilename('readme.txt'),
        isNull,
      );
      expect(
        FlashskyaiAgentCatalogService.agentIdFromMdFilename('.hidden.md'),
        isNull,
      );
      expect(
        FlashskyaiAgentCatalogService.agentIdFromMdFilename('.md'),
        isNull,
      );
    });
  });

  group('FlashskyaiAgentCatalog', () {
    test('activeDropdownValue maps empty, builtin, and custom', () {
      expect(
        FlashskyaiAgentCatalog.activeDropdownValue(''),
        FlashskyaiAgentCatalog.noneDropdownValue,
      );
      expect(
        FlashskyaiAgentCatalog.activeDropdownValue('  '),
        FlashskyaiAgentCatalog.noneDropdownValue,
      );
      expect(
        FlashskyaiAgentCatalog.activeDropdownValue('general-purpose'),
        'general-purpose',
      );
      expect(
        FlashskyaiAgentCatalog.activeDropdownValue(' my-agent '),
        FlashskyaiAgentCatalog.customDropdownValue,
      );
      expect(
        FlashskyaiAgentCatalog.activeDropdownValue(
          'image-analyzer',
          userAgentIds: ['image-analyzer'],
        ),
        'image-analyzer',
      );
    });

    test('dropdownValues starts with none and ends with custom', () {
      final v = FlashskyaiAgentCatalog.dropdownValues();
      expect(v.first, FlashskyaiAgentCatalog.noneDropdownValue);
      expect(v.last, FlashskyaiAgentCatalog.customDropdownValue);
      expect(v, contains('flashskyai-code-guide'));
      expect(v, contains('statusline-setup'));

      final withUser = FlashskyaiAgentCatalog.dropdownValues(
        userAgentIds: ['image-analyzer', 'test-runner'],
      );
      expect(withUser, contains('image-analyzer'));
      expect(withUser, contains('test-runner'));
      expect(
        withUser.indexOf('image-analyzer'),
        lessThan(withUser.indexOf(FlashskyaiAgentCatalog.customDropdownValue)),
      );
    });

    test('isKnownAgentId matches builtin and user lists', () {
      expect(
        FlashskyaiAgentCatalog.isKnownAgentId('general-purpose'),
        isTrue,
      );
      expect(
        FlashskyaiAgentCatalog.isKnownAgentId(
          'test-runner',
          userAgentIds: ['test-runner'],
        ),
        isTrue,
      );
      expect(
        FlashskyaiAgentCatalog.isKnownAgentId('unknown'),
        isFalse,
      );
    });

    test('tryParseBuiltinId only matches known ids', () {
      expect(
        FlashskyaiAgentCatalog.tryParseBuiltinId('general-purpose')!.id,
        'general-purpose',
      );
      expect(FlashskyaiAgentCatalog.tryParseBuiltinId('unknown'), isNull);
    });
  });
}
