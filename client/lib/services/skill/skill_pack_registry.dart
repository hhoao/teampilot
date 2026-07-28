import '../../models/skill_pack.dart';
import '../../models/skill_pack_instruction.dart';

/// Built-in / in-app skill pack catalog (extensible later via git registry).
class SkillPackRegistry {
  SkillPackRegistry({List<SkillPack>? packs})
    : _byId = {
        for (final p in packs ?? builtinSkillPacks())
          if (p.id.isNotEmpty) p.id: p,
      };

  final Map<String, SkillPack> _byId;

  SkillPack? byId(String id) => _byId[id.trim()];

  List<SkillPack> all() => _byId.values.toList(growable: false);
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
