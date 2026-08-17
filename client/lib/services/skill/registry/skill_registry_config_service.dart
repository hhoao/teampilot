import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../../models/skill_registry_source.dart';
import '../../io/filesystem.dart';
import '../../io/local_filesystem.dart';
import '../../storage/app_storage.dart';

class SkillRegistryConfigService {
  SkillRegistryConfigService({
    Filesystem? fs,
    String? teampilotRoot,
    Future<String?> Function()? legacySkillsMpKeyReader,
  }) : _teampilotRoot = teampilotRoot?.trim(),
       _fs = fs ?? LocalFilesystem(),
       _legacySkillsMpKeyReader = legacySkillsMpKeyReader;

  final String? _teampilotRoot;
  final Filesystem _fs;
  final Future<String?> Function()? _legacySkillsMpKeyReader;

  Future<String> _configPath() async {
    final root = _teampilotRoot;
    if (root != null && root.isNotEmpty) {
      return AppPaths.skillRegistriesConfigPathForTeampilotRoot(root);
    }
    if (AppStorage.isInstalled) {
      return AppStorage.context.skillRegistriesConfigPath;
    }
    return AppStorage.paths.skillRegistriesConfigPath;
  }

  Future<String> _legacyReposPath() async {
    final root = _teampilotRoot;
    if (root != null && root.isNotEmpty) {
      return AppPaths.skillReposConfigPathForTeampilotRoot(root);
    }
    if (AppStorage.isInstalled) {
      return AppStorage.context.skillReposConfigPath;
    }
    return AppStorage.paths.skillReposConfigPath;
  }

  Future<SkillRegistriesConfig> load() async {
    final path = await _configPath();
    try {
      final stat = await _fs.stat(path);
      if (!stat.isFile) {
        final migrated = await _migrateIfNeeded();
        return migrated;
      }
      final text = await _fs.readString(path);
      if (text == null || text.trim().isEmpty) {
        return SkillRegistriesConfig.defaults();
      }
      final json = jsonDecode(text);
      if (json is! Map) return SkillRegistriesConfig.defaults();
      return SkillRegistriesConfig.fromJson(json.cast<String, Object?>());
    } catch (_) {
      return SkillRegistriesConfig.defaults();
    }
  }

  Future<void> save(SkillRegistriesConfig config) async {
    final path = await _configPath();
    await _fs.ensureDir(p.dirname(path));
    await _fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  /// One-time migration from legacy skills/repos.json + settings skillsMpApiKey.
  Future<SkillRegistriesConfig> _migrateIfNeeded() async {
    final defaults = SkillRegistriesConfig.defaults();
    final legacyPath = await _legacyReposPath();
    List<SkillRegistrySourceConfig> gitSources = const [];
    try {
      final stat = await _fs.stat(legacyPath);
      if (stat.isFile) {
        final text = await _fs.readString(legacyPath);
        if (text != null && text.trim().isNotEmpty) {
          final json = jsonDecode(text);
          if (json is Map) {
            final repos = json['repos'];
            if (repos is List) {
              gitSources = repos.whereType<Map>().map((raw) {
                final m = raw.cast<String, Object?>();
                final owner = (m['owner'] as String?) ?? '';
                final name = (m['name'] as String?) ?? '';
                return SkillRegistrySourceConfig(
                  id: 'git-$owner-$name',
                  kind: SkillRegistryKind.gitRepo,
                  label: '$owner/$name',
                  enabled: m['enabled'] as bool? ?? true,
                  gitOwner: owner,
                  gitName: name,
                  gitBranch: (m['branch'] as String?) ?? 'main',
                );
              }).toList();
            }
          }
        }
      }
    } catch (_) {
      gitSources = const [];
    }

    if (gitSources.isEmpty) {
      return defaults;
    }

    String? legacyKey;
    final reader = _legacySkillsMpKeyReader;
    if (reader != null) {
      try {
        legacyKey = await reader();
      } catch (_) {
        legacyKey = null;
      }
    }

    final sources = <SkillRegistrySourceConfig>[];
    for (final s in defaults.sources) {
      if (s.kind == SkillRegistryKind.gitRepo) continue;
      sources.add(s.id == 'skillsMp' && legacyKey != null && legacyKey.trim().isNotEmpty
          ? s.copyWith(apiToken: legacyKey.trim())
          : s);
    }
    sources.addAll(gitSources.isEmpty ? defaults.sources.where((s) => s.kind == SkillRegistryKind.gitRepo) : gitSources);
    final migrated = SkillRegistriesConfig(sources: sources);
    await save(migrated);
    return migrated;
  }
}
