import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/remote/materialization_manifest.dart';
import 'package:teampilot/services/remote/remote_credential_materializer.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  RemoteCredentialMaterializer materializer(InMemoryFilesystem fs) =>
      RemoteCredentialMaterializer(
        manifest: MaterializationManifest(fs: fs, machineRoot: '/remote'),
      );

  // A credential file whose content embeds a local-root absolute path.
  const creds = [
    CredentialFile(
      relativePath: 'providers.json',
      content: '{"keyFile":"/local/providers/claude/key.pem"}',
    ),
  ];

  test('opt-in off writes no credentials on the work machine', () async {
    final workFs = InMemoryFilesystem();
    await materializer(workFs).materialize(
      cli: CliTool.claude,
      workFs: workFs,
      machineRoot: '/remote',
      localRoot: '/local',
      optIn: false,
      localCredentials: creds,
    );
    expect(
      (await workFs.stat('/remote/providers/claude/providers.json')).exists,
      isFalse,
    );
  });

  test('opt-in on materializes creds and rebases link target to machineRoot',
      () async {
    final workFs = InMemoryFilesystem();
    await materializer(workFs).materialize(
      cli: CliTool.claude,
      workFs: workFs,
      machineRoot: '/remote',
      localRoot: '/local',
      optIn: true,
      localCredentials: creds,
    );
    final written =
        await workFs.readString('/remote/providers/claude/providers.json');
    expect(written, contains('/remote/providers/claude/key.pem'));
    expect(written, isNot(contains('/local'))); // rebased off the local root
  });

  test('rotation (changed cred bytes) re-pushes; unchanged is skipped',
      () async {
    final workFs = _CountingFs();
    final m = materializer(workFs);
    await m.materialize(
      cli: CliTool.claude,
      workFs: workFs,
      machineRoot: '/remote',
      localRoot: '/local',
      optIn: true,
      localCredentials: creds,
    );
    expect(workFs.writeStringCount, 1);

    // unchanged → skip
    await m.materialize(
      cli: CliTool.claude,
      workFs: workFs,
      machineRoot: '/remote',
      localRoot: '/local',
      optIn: true,
      localCredentials: creds,
    );
    expect(workFs.writeStringCount, 1);

    // rotated → re-push
    await m.materialize(
      cli: CliTool.claude,
      workFs: workFs,
      machineRoot: '/remote',
      localRoot: '/local',
      optIn: true,
      localCredentials: const [
        CredentialFile(relativePath: 'providers.json', content: 'rotated'),
      ],
    );
    expect(workFs.writeStringCount, 2);
  });
}

class _CountingFs extends InMemoryFilesystem {
  int writeStringCount = 0;
  @override
  Future<void> writeString(String path, String content) async {
    if (!path.endsWith('.materialized.json')) writeStringCount++;
    await super.writeString(path, content);
  }
}
