import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/remote/remote_app_data_materializer.dart';
import 'package:teampilot/services/remote/remote_credential_materializer.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  ({InMemoryFilesystem homeFs, InMemoryFilesystem workFs}) seeded() {
    final homeFs = InMemoryFilesystem();
    // a little ancestry so reconcile has something to copy
    homeFs.files['/home/cli-defaults/claude/agents/x.md'] = 'A';
    return (homeFs: homeFs, workFs: InMemoryFilesystem());
  }

  const cred = [
    CredentialFile(relativePath: 'providers.json', content: '{"k":"v"}'),
  ];

  test('B1: opt-in on materializes credentials on the work machine', () async {
    final fs = seeded();
    var credLoaded = false;
    final m = RemoteAppDataMaterializer(
      loadLocalCredentials: (_) async {
        credLoaded = true;
        return cred;
      },
    );
    await m.materialize(
      homeFs: fs.homeFs,
      homeRoot: '/home',
      workFs: fs.workFs,
      machineRoot: '/remote',
      cli: CliTool.claude,
      workspaceId: 'w1',
      optInCredentials: true,
    );
    expect(credLoaded, isTrue);
    expect(
      (await fs.workFs.stat('/remote/providers/claude/providers.json')).isFile,
      isTrue,
    );
  });

  test('B1: opt-in off writes no credentials and does not load them', () async {
    final fs = seeded();
    var credLoaded = false;
    final m = RemoteAppDataMaterializer(
      loadLocalCredentials: (_) async {
        credLoaded = true;
        return cred;
      },
    );
    await m.materialize(
      homeFs: fs.homeFs,
      homeRoot: '/home',
      workFs: fs.workFs,
      machineRoot: '/remote',
      cli: CliTool.claude,
      workspaceId: 'w1',
      optInCredentials: false,
    );
    expect(credLoaded, isFalse);
    expect(
      (await fs.workFs.stat('/remote/providers/claude/providers.json')).exists,
      isFalse,
    );
  });

  test('B4: skills/plugins linker and relay provisioner run on the work fs',
      () async {
    final fs = seeded();
    final linked = <String>[];
    final relayed = <String>[];
    final m = RemoteAppDataMaterializer(
      loadLocalCredentials: (_) async => const [],
      linkResources: ({
        required workFs,
        required machineRoot,
        required cli,
        required workspaceId,
      }) async =>
          linked.add('${cli.value}@$machineRoot'),
      provisionRelay: ({required workFs, required machineRoot, required cli}) async =>
          relayed.add('${cli.value}@$machineRoot'),
    );
    await m.materialize(
      homeFs: fs.homeFs,
      homeRoot: '/home',
      workFs: fs.workFs,
      machineRoot: '/remote',
      cli: CliTool.claude,
      workspaceId: 'w1',
      optInCredentials: false,
    );
    expect(linked, ['claude@/remote']);
    expect(relayed, ['claude@/remote']);
  });
}
