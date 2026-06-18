import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/personal_identity.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/resource/resource_provisioning_service.dart';
import 'package:teampilot/services/resource/resource_scope.dart'; // ResourceScope + ResourceCatalog
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() { setUpTestAppStorage(); });
  tearDown(() { tearDownTestAppStorage(); });

  test('provisionForLaunch materializes skills into the leaf config dir', () async {
    final fs = AppStorage.fs;
    final tmp = await fs.createTempDir(prefix: 'prov_test_');
    final skillsRoot = fs.pathContext.join(tmp, 'skills', 'installed');
    final src = fs.pathContext.join(skillsRoot, 'demo-skill');
    await fs.ensureDir(src);
    final configDir = fs.pathContext.join(tmp, 'cfg', 'flashskyai');

    final service = ResourceProvisioningService(
      fs: fs,
      registry: CliToolRegistry.builtIn(),
    );

    await service.provisionForLaunch(
      scope: const PersonalResourceScope(
        personal: PersonalIdentity(id: 'p', display: 'p', bundle: ConfigBundle(skillIds: ['demo'])),
      ),
      cli: CliTool.flashskyai,
      configDir: configDir,
      catalog: ResourceCatalog(
        skills: [
          Skill(id: 'demo', name: 'Demo', description: '', directory: 'demo-skill', installedAt: 0, updatedAt: 0),
        ],
        skillsRoot: skillsRoot,
        pathContext: fs.pathContext,
      ),
    );

    final entries = await fs.listDir(fs.pathContext.join(configDir, 'skills'));
    expect(entries.map((e) => e.name), contains('demo-skill'));
  });
}
