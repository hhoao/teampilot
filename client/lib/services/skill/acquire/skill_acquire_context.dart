import '../../../models/skill_pack.dart';
import '../../../models/skill_install_recipe.dart';

/// Mutable run state shared across recipe steps.
class SkillAcquireContext {
  SkillAcquireContext({
    required this.overwrite,
    required this.expectedSkillId,
    this.pack,
    Map<String, String>? vars,
  }) : vars = {
         ...?vars,
       };

  final bool overwrite;
  final String expectedSkillId;
  final SkillPack? pack;
  final Map<String, String> vars;

  String? syncRoot;
  String? packRoot;
  String? packBin;
  final List<String> installedSkillIds = [];
  final List<String> pathExports = [];
  final Map<String, String> envExports = {};

  String resolve(String template) {
    var out = template;
    final replacements = <String, String>{
      ...vars,
      if (syncRoot != null) 'SYNC_ROOT': syncRoot!,
      if (packRoot != null) 'PACK_ROOT': packRoot!,
      if (packBin != null) 'PACK_BIN': packBin!,
    };
    for (final e in replacements.entries) {
      out = out.replaceAll('\$${e.key}', e.value);
      out = out.replaceAll('\${${e.key}}', e.value);
    }
    return out;
  }

  void applyExports(SkillInstallExports exports) {
    for (final p in exports.path) {
      final resolved = resolve(p);
      if (resolved.isNotEmpty) pathExports.add(resolved);
    }
    for (final e in exports.env.entries) {
      envExports[e.key] = resolve(e.value);
    }
    for (final id in exports.skills) {
      if (id.isNotEmpty && !installedSkillIds.contains(id)) {
        installedSkillIds.add(id);
      }
    }
  }
}
