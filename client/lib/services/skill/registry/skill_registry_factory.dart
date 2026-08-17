import 'package:http/http.dart' as http;

import '../../../models/skill.dart';
import '../../../models/skill_registry_source.dart';
import '../../../repositories/skill_repository.dart';
import 'api_registry_source.dart';
import 'git_repo_registry_source.dart';
import 'skill_registry_source.dart';

abstract final class SkillRegistryFactory {
  static List<SkillRegistrySource> build(
    SkillRegistriesConfig config, {
    required SkillRepository repository,
    http.Client? client,
  }) => [
    for (final c in config.sources)
      if (c.kind == SkillRegistryKind.api)
        ApiRegistrySource(c, client: client)
      else
        GitRepoRegistrySource(
          c,
          discoverableProvider: () => repository.readCachedDiscoverable(
            SkillRepo(
              owner: c.gitOwner ?? '',
              name: c.gitName ?? '',
              branch: c.gitBranch ?? 'main',
            ),
          ),
          syncNow: () async {
            await repository.syncRepoCache(
              SkillRepo(
                owner: c.gitOwner ?? '',
                name: c.gitName ?? '',
                branch: c.gitBranch ?? 'main',
              ),
              force: true,
            );
          },
        ),
  ];
}
