import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/plugin_external_source.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/utils/github_source_url.dart';

void main() {
  test('resolveSkillRepoGithubUrl prefers readmeUrl', () {
    expect(
      resolveSkillRepoGithubUrl(
        readmeUrl: 'https://example.com/readme',
        repoOwner: 'o',
        repoName: 'n',
      ),
      'https://example.com/readme',
    );
  });

  test('resolveSkillRepoGithubUrl builds tree path from repo', () {
    expect(
      resolveSkillRepoGithubUrl(
        repoOwner: 'anthropics',
        repoName: 'skills',
        repoBranch: 'main',
        directory: 'skills/commit',
      ),
      'https://github.com/anthropics/skills/tree/main/skills/commit',
    );
  });

  test('DiscoverableSkill.githubBrowseUrl', () {
    const skill = DiscoverableSkill(
      key: 'k',
      name: 'commit',
      description: '',
      directory: 'skills/commit',
      repoOwner: 'anthropics',
      repoName: 'skills',
      repoBranch: 'main',
    );
    expect(
      skill.githubBrowseUrl,
      'https://github.com/anthropics/skills/tree/main/skills/commit',
    );
  });

  test('DiscoverablePlugin.githubBrowseUrl for local marketplace entry', () {
    const plugin = DiscoverablePlugin(
      key: 'k',
      name: 'security',
      description: '',
      version: '1',
      marketplaceOwner: 'anthropics',
      marketplaceName: 'claude-plugins-official',
      marketplaceBranch: 'main',
      source: 'plugins/security',
    );
    expect(
      plugin.githubBrowseUrl,
      'https://github.com/anthropics/claude-plugins-official/tree/main/plugins/security',
    );
  });

  test('resolvePluginGithubUrl uses external git source', () {
    final url = resolvePluginGithubUrl(
      marketplaceOwner: 'anthropics',
      marketplaceName: 'official',
      marketplaceBranch: 'main',
      externalSource: const PluginExternalSource(
        cloneUrl: 'https://github.com/acme/tool.git',
        subPath: 'pkg/plugin',
        ref: 'v2',
      ),
    );
    expect(url, 'https://github.com/acme/tool/tree/v2/pkg/plugin');
  });
}
