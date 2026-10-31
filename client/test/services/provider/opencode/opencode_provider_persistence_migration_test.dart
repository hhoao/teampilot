import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/provider_persistence/provider_persistence_strategy.dart';
import 'package:teampilot/services/cli/opencode/provider_persistence.dart';
import 'package:teampilot/services/provider/tool_config_generator.dart';

import '../../../support/in_memory_filesystem.dart';

AppProviderConfig _goRow() => AppProviderConfig(
  id: 'opencode-go',
  cli: CliTool.opencode,
  name: 'OpenCode Go',
  apiKey: 'oc_sk_paid',
  baseUrl: 'https://opencode.ai/zen/go/v1',
  defaultModel: 'deepseek-v4-flash',
  config: const {'npm': '@ai-sdk/openai-compatible'},
);

AppProviderConfig _zenRow() => const AppProviderConfig(
  id: 'opencode',
  cli: CliTool.opencode,
  name: 'OpenCode',
  defaultModel: 'deepseek-v4.1-flash-free',
);

Future<List<AppProviderConfig>> _reconcile(
  List<AppProviderConfig> providers,
  List<List<AppProviderConfig>> saved,
) {
  return const OpencodeProviderPersistence().reconcileLoaded(
    ProviderPersistenceContext(
      fs: InMemoryFilesystem(),
      basePath: '/tmp/base',
      generator: const ToolConfigGenerator(),
      resolveHome: () => '',
      save: (cli, next) async => saved.add(next),
    ),
    providers,
  );
}

void main() {
  test('a legacy opencode-go row folds into the single OpenCode row', () async {
    final saved = <List<AppProviderConfig>>[];
    final result = await _reconcile([_goRow()], saved);

    final merged = result.single;
    expect(merged.id, 'opencode');
    expect(merged.name, 'OpenCode');
    expect(merged.apiKey, 'oc_sk_paid');
    expect(merged.config['opencodeSubscription'], 'opencode-go');
    expect(merged.baseUrl, 'https://opencode.ai/zen/go/v1');
    expect(merged.defaultModel, 'deepseek-v4-flash');
    expect(saved, hasLength(1));
  });

  test('an existing Zen row absorbs the legacy Go key and binding', () async {
    final saved = <List<AppProviderConfig>>[];
    final result = await _reconcile([_zenRow(), _goRow()], saved);

    expect(result, hasLength(1));
    final merged = result.single;
    expect(merged.id, 'opencode');
    expect(merged.apiKey, 'oc_sk_paid');
    expect(merged.defaultModel, 'deepseek-v4.1-flash-free');
    expect(merged.config['opencodeSubscription'], 'opencode-go');
  });

  test('a migrated list is not written again on the next load', () async {
    final saved = <List<AppProviderConfig>>[];
    final first = await _reconcile([_goRow()], saved);
    saved.clear();

    final second = await _reconcile(first, saved);
    expect(second.single.id, 'opencode');
    expect(saved, isEmpty);
  });

  test('rows without a legacy Go entry are left untouched', () async {
    final saved = <List<AppProviderConfig>>[];
    final result = await _reconcile([_zenRow()], saved);

    expect(result.single.id, 'opencode');
    expect(result.single.config.containsKey('opencodeSubscription'), isFalse);
    for (final rows in saved) {
      expect(rows.single.config.containsKey('opencodeSubscription'), isFalse);
    }
  });
}
