import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/cli/claude/provider/claude_provider_credentials_service.dart';
import 'package:teampilot/services/remote/local_credential_exporter.dart';
import 'package:teampilot/services/cli/registry/cli_bootstrap.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    setUpTestAppStorage();
    CliToolRegistry.builtIn().configure(
      CliBootstrap(const {}, storage: testHomeStorage),
    );
  });

  tearDown(() {
    tearDownTestAppStorage();
  });

  test(
    'exports providers.json and linked credential files from home catalog',
    () async {
      final repo = AppProviderRepository(storage: testHomeStorage);
      await repo.saveProviders(CliTool.claude, [
        AppProviderConfig(
          id: 'deepseek',
          cli: CliTool.claude,
          name: 'deepseek',
          apiKey: 'sk-export',
          baseUrl: 'https://api.example.com',
          defaultModel: 'm1',
        ),
      ]);

      final credSvc = ClaudeProviderCredentialsService(
        fs: testHomeStorage.fs,
        basePath: testHomeStorage.appDataRoot,
        resolveHomeDirectory: () => testHomeStorage.home,
        storage: testHomeStorage,
      );
      final credPath = credSvc.credentialPath('deepseek');
      await testHomeStorage.fs.ensureDir(credSvc.providerDir('deepseek'));
      await testHomeStorage.fs.writeString(credPath, '{"apiKey":"file-only"}');

      final files = await LocalCredentialExporter(
        basePath: testHomeStorage.appDataRoot,
        home: testHomeStorage.home,
        storage: testHomeStorage,
      ).export(CliTool.claude);

      expect(files.any((f) => f.relativePath == 'providers.json'), isTrue);
      expect(
        files.firstWhere((f) => f.relativePath == 'providers.json').content,
        contains('sk-export'),
      );
      expect(
        files.any(
          (f) =>
              f.relativePath ==
              'deepseek/${ClaudeProviderCredentialsService.credentialsFileName}',
        ),
        isTrue,
      );
    },
  );
}
