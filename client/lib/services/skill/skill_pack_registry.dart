import '../../models/skill_pack.dart';
import '../../models/skill_pack_instruction.dart';
import 'git_registry_skill_pack_source.dart';
import 'skill_pack_source.dart';

/// Built-in / in-app skill pack catalog with a lazily loaded remote registry.
class SkillPackRegistry {
  SkillPackRegistry({List<SkillPack>? packs, SkillPackSource? remote})
    : _byId = {
        for (final p in packs ?? builtinSkillPacks())
          if (p.id.isNotEmpty) p.id: p,
      },
      _remote = remote ?? GitRegistrySkillPackSource();

  final Map<String, SkillPack> _byId;
  final SkillPackSource _remote;

  bool _loaded = false;
  Future<void>? _loading;

  SkillPack? byId(String id) => _byId[id.trim()];

  List<SkillPack> all() => _byId.values.toList(growable: false);

  Future<void> ensureLoaded({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await _loadRemote(forceRefresh: true);
      return;
    }
    if (_loaded) return;
    final inFlight = _loading;
    if (inFlight != null) return inFlight;
    final loading = _loadRemote();
    _loading = loading;
    try {
      await loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _loadRemote({bool forceRefresh = false}) async {
    try {
      final remote = await _remote.fetchPacks(forceRefresh: forceRefresh);
      for (final pack in remote) {
        _byId.putIfAbsent(pack.id, () => pack);
      }
    } finally {
      _loaded = true;
    }
  }
}

/// Garry Tan's gstack sprint specialists — reference Dockerfile-like pack.
SkillPack get kGstackSkillPack => SkillPack(
  id: 'garrytan/gstack',
  name: 'gstack',
  install: [
    FromInstruction.parseRef('garrytan/gstack@main'),
    const SkillsInstruction(includeAll: true),
    const RunInstruction(shell: './setup', optional: true),
    const PathInstruction(['bin']),
  ],
);

List<SkillPack> builtinSkillPacks() => [kGstackSkillPack];
