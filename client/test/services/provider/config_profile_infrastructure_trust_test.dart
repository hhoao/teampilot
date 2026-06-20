import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_infrastructure.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('metadataWithTrustedProjects writes projects trust flags', () async {
    final base = await Directory.systemTemp.createTemp('cfg_infra_trust_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    final fs = LocalFilesystem();
    final infra = ConfigProfileInfrastructure(
      basePath: base.path,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      fs: fs,
    );
    final metadataPath = p.join(base.path, '.claude.json');

    final metadata = await infra.metadataWithTrustedProjects(
      metadataPath: metadataPath,
      defaultMetadata: ClaudeConfigProfileCapability.defaultMetadata,
      defaultProjectConfig: ClaudeConfigProfileCapability.defaultProjectConfig,
      directories: const ['/workspace/new'],
    );

    final projects = metadata['projects'] as Map<String, Object?>;
    expect(
      (projects['/workspace/new'] as Map)['hasTrustDialogAccepted'],
      isTrue,
    );
    expect(
      (projects['/workspace/new'] as Map)['projectOnboardingSeenCount'],
      1,
    );
  });
}
