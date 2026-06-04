import '../../cubits/skill_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/skill.dart';

enum SkillSearchSource { repos, skillsSh }

Map<String, String> skillDiscoveryRepoFilterChoices(
  SkillState state,
  AppLocalizations l10n,
) {
  final choices = <String, String>{'all': l10n.skillsFilterRepoAll};
  for (final r in state.repos.where((r) => r.enabled)) {
    choices[r.githubUrl] = r.fullName;
  }
  for (final d in state.discoverable) {
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
  required SkillState state,
  required Set<String> installedKeys,
  required String filterRepo,
  required String filterStatus,
  required String searchQuery,
}) {
  return state.discoverable.where((d) {
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
