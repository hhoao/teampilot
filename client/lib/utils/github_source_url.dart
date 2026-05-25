import '../models/plugin.dart';
import '../models/plugin_external_source.dart';
import '../models/skill.dart';

/// Builds a GitHub browse URL for a repo-relative skill directory.
String? resolveSkillRepoGithubUrl({
  String? readmeUrl,
  String? repoOwner,
  String? repoName,
  String? repoBranch,
  String? directory,
}) {
  final direct = _nonEmpty(readmeUrl);
  if (direct != null) return direct;
  final owner = _nonEmpty(repoOwner);
  final name = _nonEmpty(repoName);
  if (owner == null || name == null) return null;
  return githubTreeUrl(
    owner: owner,
    name: name,
    branch: _nonEmpty(repoBranch) ?? 'main',
    path: directory,
  );
}

/// Installed or discoverable skill entry.
extension SkillGithubBrowse on Skill {
  String? get githubBrowseUrl => resolveSkillRepoGithubUrl(
    readmeUrl: readmeUrl,
    repoOwner: repoOwner,
    repoName: repoName,
    repoBranch: repoBranch,
    directory: directory,
  );
}

extension DiscoverableSkillGithubBrowse on DiscoverableSkill {
  String? get githubBrowseUrl => resolveSkillRepoGithubUrl(
    readmeUrl: readmeUrl,
    repoOwner: repoOwner,
    repoName: repoName,
    repoBranch: repoBranch,
    directory: directory,
  );
}

extension SkillsShEntryGithubBrowse on SkillsShEntry {
  String? get githubBrowseUrl => resolveSkillRepoGithubUrl(
    readmeUrl: readmeUrl,
    repoOwner: repoOwner,
    repoName: repoName,
    repoBranch: repoBranch,
    directory: directory,
  );
}

/// Plugin / marketplace discovery browse URL.
String? resolvePluginGithubUrl({
  String? readmeUrl,
  String? homepageUrl,
  String? marketplaceOwner,
  String? marketplaceName,
  String? marketplaceBranch,
  String? sourcePath,
  PluginExternalSource? externalSource,
}) {
  final direct = _nonEmpty(readmeUrl) ?? _nonEmpty(homepageUrl);
  if (direct != null) return direct;
  if (externalSource != null) {
    return _githubUrlFromExternalSource(
      externalSource,
      fallbackBranch: marketplaceBranch,
    );
  }
  final owner = _nonEmpty(marketplaceOwner);
  final name = _nonEmpty(marketplaceName);
  if (owner == null || name == null) return null;
  return githubTreeUrl(
    owner: owner,
    name: name,
    branch: _nonEmpty(marketplaceBranch) ?? 'main',
    path: sourcePath,
  );
}

extension PluginGithubBrowse on Plugin {
  String? get githubBrowseUrl => resolvePluginGithubUrl(
    readmeUrl: readmeUrl,
    homepageUrl: homepageUrl,
    marketplaceOwner: marketplaceOwner,
    marketplaceName: marketplaceName,
    marketplaceBranch: marketplaceBranch,
  );
}

extension DiscoverablePluginGithubBrowse on DiscoverablePlugin {
  String? get githubBrowseUrl => resolvePluginGithubUrl(
    readmeUrl: readmeUrl,
    marketplaceOwner: marketplaceOwner,
    marketplaceName: marketplaceName,
    marketplaceBranch: marketplaceBranch,
    sourcePath: source,
    externalSource: externalSource,
  );
}

String githubTreeUrl({
  required String owner,
  required String name,
  required String branch,
  String? path,
}) {
  final cleanName = name.replaceAll(RegExp(r'\.git$'), '');
  final trimmed = (path ?? '').trim();
  if (trimmed.isEmpty || trimmed == '.') {
    return 'https://github.com/$owner/$cleanName';
  }
  var rel = trimmed.replaceAll('\\', '/');
  while (rel.startsWith('./')) {
    rel = rel.substring(2);
  }
  if (rel.isEmpty) return 'https://github.com/$owner/$cleanName';
  return 'https://github.com/$owner/$cleanName/tree/$branch/$rel';
}

String? _githubUrlFromExternalSource(
  PluginExternalSource source, {
  String? fallbackBranch,
}) {
  final clone = source.cloneUrl.trim();
  if (clone.isEmpty) return null;
  final match = RegExp(
    r'github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$',
    caseSensitive: false,
  ).firstMatch(clone.replaceAll(RegExp(r'^git@github\.com:'), 'https://github.com/'));
  if (match != null) {
    final owner = match.group(1);
    final name = match.group(2);
    if (owner != null && name != null) {
      final branch = _nonEmpty(source.ref) ?? _nonEmpty(fallbackBranch) ?? 'main';
      return githubTreeUrl(
        owner: owner,
        name: name,
        branch: branch,
        path: source.subPath.isEmpty ? null : source.subPath,
      );
    }
  }
  return clone;
}

String? _nonEmpty(String? value) {
  final v = value?.trim();
  if (v == null || v.isEmpty) return null;
  return v;
}
