import '../../l10n/app_localizations.dart';
import '../../models/skill.dart';

enum SkillSearchSource { repos, skillsSh }

Set<String> skillInstalledKeys(List<Skill> installed) {
  return installed
      .map(
        (s) =>
            '${s.directory.toLowerCase()}:${(s.repoOwner ?? '').toLowerCase()}:${(s.repoName ?? '').toLowerCase()}',
      )
      .toSet();
}

String skillsShInstallKey(SkillsShEntry entry) {
  return '${entry.directory.toLowerCase()}:${entry.repoOwner.toLowerCase()}:${entry.repoName.toLowerCase()}';
}

bool sameDiscoverableSkills(
  List<DiscoverableSkill> a,
  List<DiscoverableSkill> b,
) {
  if (a.length != b.length) return false;
  final keysA = a.map(_discoverableSkillKey).toSet();
  return keysA.length == a.length &&
      b.every((skill) => keysA.contains(_discoverableSkillKey(skill)));
}

String _discoverableSkillKey(DiscoverableSkill skill) {
  return '${skill.directory}:${skill.repoOwner}:${skill.repoName}';
}

typedef SkillDiscoverySyncSlice = ({
  bool discoveryLoading,
  Set<String> repoSyncingKeys,
});

typedef SkillDiscoveryFilterSlice = ({
  List<SkillRepo> repos,
  List<DiscoverableSkill> discoverable,
});

typedef SkillDiscoveryGridSlice = ({
  List<DiscoverableSkill> discoverable,
  bool discoveryLoading,
  List<SkillRepo> repos,
  Set<String> busyIds,
});

Map<String, String> skillDiscoveryRepoFilterChoices(
  List<SkillRepo> repos,
  List<DiscoverableSkill> discoverable,
  AppLocalizations l10n,
) {
  final choices = <String, String>{'all': l10n.skillsFilterRepoAll};
  for (final r in repos.where((r) => r.enabled)) {
    choices[r.githubUrl] = r.fullName;
  }
  for (final d in discoverable) {
    final url = 'https://github.com/${d.repoOwner}/${d.repoName}';
    choices.putIfAbsent(url, () => '${d.repoOwner}/${d.repoName}');
  }
  return choices;
}

String resolveSkillDiscoveryRepoFilter(
  String raw,
  Map<String, String> choices,
) {
  if (choices.containsKey(raw)) return raw;
  final byLabel = choices.entries.where((e) => e.value == raw).toList();
  if (byLabel.length == 1) return byLabel.first.key;
  return 'all';
}

bool skillDiscoveryMatchesRepoFilter(DiscoverableSkill skill, String filterRepo) {
  if (filterRepo == 'all') return true;
  final url = 'https://github.com/${skill.repoOwner}/${skill.repoName}';
  return url == filterRepo ||
      '${skill.repoOwner}/${skill.repoName}' == filterRepo;
}

List<DiscoverableSkill> filterDiscoverableSkills({
  required List<DiscoverableSkill> discoverable,
  required Set<String> installedKeys,
  required String filterRepo,
  required String filterStatus,
  required String searchQuery,
}) {
  return discoverable.where((d) {
    if (!skillDiscoveryMatchesRepoFilter(d, filterRepo)) return false;
    final installKey =
        '${d.directory.split('/').last.toLowerCase()}:${d.repoOwner.toLowerCase()}:${d.repoName.toLowerCase()}';
    final installed = installedKeys.contains(installKey);
    if (filterStatus == 'installed' && !installed) return false;
    if (filterStatus == 'uninstalled' && installed) return false;
    if (searchQuery.trim().isEmpty) return true;
    final q = searchQuery.toLowerCase();
    return d.name.toLowerCase().contains(q) ||
        '${d.repoOwner}/${d.repoName}'.toLowerCase().contains(q);
  }).toList();
}

String discoverableSkillInstallKey(DiscoverableSkill skill) {
  return '${skill.directory.split('/').last.toLowerCase()}:${skill.repoOwner.toLowerCase()}:${skill.repoName.toLowerCase()}';
}
