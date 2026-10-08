import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_data_layout.dart';
import 'package:teampilot/services/cli/opencode/provider/opencode_live_import.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test(
    'imports an existing global opencode-go auth entry as official',
    () async {
      final fs = InMemoryFilesystem();
      const home = '/home/user';
      final layout = OpencodeDataLayout();
      final dataHome = layout.globalDataHome(home);
      await fs.writeString(
        layout.authJsonPath(dataHome),
        '{"opencode-go": {"type": "api", "key": "sk-test"}}',
      );

      final snapshot = await OpencodeLiveImport.loadSnapshot(
        ProviderCatalogLoadContext(
          fs: fs,
          homeDirectory: home,
          cwd: home,
          usePosixPaths: false,
        ),
      );

      expect(snapshot.providers, hasLength(1));
      expect(snapshot.sources, contains('live'));
      final provider = snapshot.providers.single;
      expect(provider.id, 'opencode-go');
      expect(provider.apiKey, 'sk-test');
      expect(provider.baseUrl, 'https://opencode.ai/zen/go/v1');
      expect(provider.defaultModel, 'deepseek-v4-flash');
    },
  );

  test(
    'reads v2 providers.settings and package from global opencode.json',
    () async {
      final fs = InMemoryFilesystem();
      const home = '/home/user';
      final layout = OpencodeDataLayout();
      final dataHome = layout.globalDataHome(home);
      final configHome = layout.globalConfigHome(home);
      await fs.writeString(
        layout.authJsonPath(dataHome),
        '{"custom-llm": {"type": "api", "key": "sk-live"}}',
      );
      await fs.writeString(layout.opencodeConfigPath(configHome), '''
{
  "model": "custom-llm/gpt-4",
  "providers": {
    "custom-llm": {
      "name": "Custom LLM",
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "https://api.custom.example/v1"
      }
    }
  }
}
''');

      final snapshot = await OpencodeLiveImport.loadSnapshot(
        ProviderCatalogLoadContext(
          fs: fs,
          homeDirectory: home,
          cwd: home,
          usePosixPaths: false,
        ),
      );

      expect(snapshot.providers, hasLength(1));
      final provider = snapshot.providers.single;
      expect(provider.id, 'custom-llm');
      expect(provider.name, 'Custom LLM');
      expect(provider.apiKey, 'sk-live');
      expect(provider.baseUrl, 'https://api.custom.example/v1');
      expect(provider.defaultModel, 'gpt-4');
      expect(provider.config['npm'], 'aisdk:@ai-sdk/openai-compatible');
    },
  );
}
