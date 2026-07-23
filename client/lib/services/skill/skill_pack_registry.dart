import '../../models/skill_acquire_spec.dart';
import '../../models/skill_pack.dart';

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

/// Garry Tan's gstack sprint specialists as one installable pack.
SkillPack get kGstackSkillPack => SkillPack(
  id: 'garrytan/gstack',
  name: 'gstack',
  repoOwner: 'garrytan',
  repoName: 'gstack',
  repoBranch: 'main',
  acquire: const SkillAcquireSpec(kind: 'git-pack'),
  skills: const [
    SkillPackEntry(
      id: 'garrytan/gstack:office-hours',
      directory: 'office-hours',
      name: 'Office Hours',
    ),
    SkillPackEntry(
      id: 'garrytan/gstack:plan-ceo-review',
      directory: 'plan-ceo-review',
      name: 'CEO Review',
    ),
    SkillPackEntry(
      id: 'garrytan/gstack:plan-eng-review',
      directory: 'plan-eng-review',
      name: 'Eng Manager Review',
    ),
    SkillPackEntry(
      id: 'garrytan/gstack:plan-design-review',
      directory: 'plan-design-review',
      name: 'Design Review',
    ),
    SkillPackEntry(
      id: 'garrytan/gstack:review',
      directory: 'review',
      name: 'Staff Review',
    ),
    SkillPackEntry(
      id: 'garrytan/gstack:investigate',
      directory: 'investigate',
      name: 'Investigate',
    ),
    SkillPackEntry(
      id: 'garrytan/gstack:qa',
      directory: 'qa',
      name: 'QA',
    ),
    SkillPackEntry(
      id: 'garrytan/gstack:cso',
      directory: 'cso',
      name: 'CSO',
    ),
    SkillPackEntry(
      id: 'garrytan/gstack:ship',
      directory: 'ship',
      name: 'Ship',
    ),
  ],
);

List<SkillPack> builtinSkillPacks() => [kGstackSkillPack];
