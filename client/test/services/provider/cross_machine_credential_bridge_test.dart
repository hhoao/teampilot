import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/claude/claude_provider_credentials_service.dart';
import 'package:teampilot/services/provider/codex/codex_auth_artifacts.dart';
import 'package:teampilot/services/provider/codex/codex_provider_credentials_service.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/provider/control_plane_profile_paths.dart';
import 'package:teampilot/services/provider/credential_binding.dart';
import 'package:teampilot/services/provider/cross_machine_credential_bridge.dart';
import 'package:teampilot/services/provider/cursor/cursor_home_layout.dart';
import 'package:teampilot/services/provider/cursor/cursor_provider_credentials_service.dart';
import 'package:teampilot/services/provider/opencode/opencode_data_layout.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/in_memory_filesystem.dart';

RuntimeContext _memoryContext(String dir, InMemoryFilesystem fs) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: fs,
  home: dir,
  cwd: dir,
  appDataRoot: dir,
  paths: AppPaths(dir),
);

void main() {
  test('materializeClaudeCredential copies home credential to work plane', () async {
    final homeFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    final catalog = ControlPlaneProfilePaths(
      _memoryContext('/home-catalog', homeFs),
    );
    final work = ConfigProfileService(
      basePath: '/work',
      home: '/work-home',
      fs: workFs,
      layout: _memoryContext('/work', workFs).layout,
    );

    final svc = ClaudeProviderCredentialsService(
      fs: catalog.fs,
      basePath: catalog.basePath,
      resolveHomeDirectory: () => catalog.home,
    );
    final src = svc.credentialPath('anthropic');
    await catalog.fs.ensureDir(svc.providerDir('anthropic'));
    await catalog.fs.writeString(src, '{"token":"home-secret"}');
    expect(await catalog.fs.readBytes(src), isNotEmpty);

    final copied = await CrossMachineCredentialBridge.materializeClaudeCredential(
      catalog: catalog,
      work: work,
      providerId: 'anthropic',
      binding: CredentialBindingKind.isolated,
    );
    expect(copied, isTrue);

    final workSvc = ClaudeProviderCredentialsService(
      fs: work.fs,
      basePath: work.basePath,
      resolveHomeDirectory: () => work.home,
    );
    final destBytes = await work.fs.readBytes(
      workSvc.credentialPath('anthropic'),
    );
    expect(destBytes, isNotNull);
    expect(String.fromCharCodes(destBytes!), contains('home-secret'));
  });

  test('materializeClaudeCredential returns false when source missing', () async {
    final catalog = ControlPlaneProfilePaths(
      _memoryContext('/home-catalog', InMemoryFilesystem()),
    );
    final work = ConfigProfileService(
      basePath: '/work',
      home: '/work-home',
      fs: InMemoryFilesystem(),
      layout: _memoryContext('/work', InMemoryFilesystem()).layout,
    );

    expect(
      await CrossMachineCredentialBridge.materializeClaudeCredential(
        catalog: catalog,
        work: work,
        providerId: 'missing',
        binding: CredentialBindingKind.linked,
      ),
      isFalse,
    );
  });

  test('materializeCodexAuth copies auth.json to work plane', () async {
    final homeFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    final catalog = ControlPlaneProfilePaths(
      _memoryContext('/home-catalog', homeFs),
    );
    final work = ConfigProfileService(
      basePath: '/work',
      home: '/work-home',
      fs: workFs,
      layout: _memoryContext('/work', workFs).layout,
    );

    final catalogSvc = CodexProviderCredentialsService(
      fs: catalog.fs,
      basePath: catalog.basePath,
    );
    final src = catalogSvc.credentialPath('openai');
    await catalog.fs.ensureDir(catalogSvc.providerDir('openai'));
    await catalog.fs.writeString(src, '{"access_token":"x"}');

    expect(
      await CrossMachineCredentialBridge.materializeCodexAuth(
        catalog: catalog,
        work: work,
        providerId: 'openai',
      ),
      isTrue,
    );

    final dest = work.pathContext.join(
      work.basePath,
      'providers',
      CliTool.codex.value,
      'openai',
      CodexAuthArtifacts.authFileName,
    );
    expect(
      String.fromCharCodes((await work.fs.readBytes(dest))!),
      contains('access_token'),
    );
  });

  test('materializeCursorCredential copies auth.json to work home tree', () async {
    final homeFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    final catalog = ControlPlaneProfilePaths(
      _memoryContext('/home-catalog', homeFs),
    );
    final work = ConfigProfileService(
      basePath: '/work',
      home: '/work-home',
      fs: workFs,
      layout: _memoryContext('/work', workFs).layout,
    );

    final catalogSvc = CursorProviderCredentialsService(
      fs: catalog.fs,
      basePath: catalog.basePath,
    );
    final authPath = CursorHomeLayout(
      pathContext: catalog.fs.pathContext,
    ).authJson(catalogSvc.providerHome('default'));
    await catalog.fs.ensureDir(catalog.fs.pathContext.dirname(authPath));
    await catalog.fs.writeString(
      authPath,
      '{"accessToken":"remote-token"}',
    );

    expect(
      await CrossMachineCredentialBridge.materializeCursorCredential(
        catalog: catalog,
        work: work,
        providerId: 'default',
      ),
      isTrue,
    );

    final workSvc = CursorProviderCredentialsService(
      fs: work.fs,
      basePath: work.basePath,
    );
    final dest = CursorHomeLayout(pathContext: work.fs.pathContext).authJson(
      workSvc.providerHome('default'),
    );
    expect(
      String.fromCharCodes((await work.fs.readBytes(dest))!),
      contains('remote-token'),
    );
  });

  test('materializeOpencodeAuth copies provider auth.json to work plane', () async {
    const layout = OpencodeDataLayout();
    final homeFs = InMemoryFilesystem();
    final workFs = InMemoryFilesystem();
    final catalog = ControlPlaneProfilePaths(
      _memoryContext('/home-catalog', homeFs),
    );
    final work = ConfigProfileService(
      basePath: '/work',
      home: '/work-home',
      fs: workFs,
      layout: _memoryContext('/work', workFs).layout,
    );

    final src = layout.providerAuthJsonPath(
      catalog.pathContext.join(
        catalog.basePath,
        'providers',
        CliTool.opencode.value,
        'official',
      ),
    );
    await catalog.fs.ensureDir(catalog.fs.pathContext.dirname(src));
    await catalog.fs.writeString(src, '{"provider":"official","ready":true}');

    expect(
      await CrossMachineCredentialBridge.materializeOpencodeAuth(
        catalog: catalog,
        work: work,
        providerId: 'official',
      ),
      isTrue,
    );

    final dest = layout.providerAuthJsonPath(
      work.pathContext.join(
        work.basePath,
        'providers',
        CliTool.opencode.value,
        'official',
      ),
    );
    expect(
      String.fromCharCodes((await work.fs.readBytes(dest))!),
      contains('official'),
    );
  });
}
