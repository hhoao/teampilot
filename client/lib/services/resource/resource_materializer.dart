import '../../utils/logger.dart';
import '../io/filesystem.dart';
import 'link_strategy.dart';
import 'resource_kind.dart';

/// Result of reconciling one kind directory.
class MaterializeResult {
  const MaterializeResult({this.linked = const [], this.errors = const []});
  final List<String> linked;
  final List<String> errors;
}

/// The only component that touches disk. Reconciles `<kindDir>` so it contains
/// exactly the `desired` refs: removes stale entries, links missing ones, and
/// leaves correct symlinks untouched (idempotent).
class ResourceMaterializer {
  ResourceMaterializer({required Filesystem fs, LinkStrategy? linkStrategy})
      : _fs = fs,
        _link = linkStrategy ?? LinkStrategy(fs);

  final Filesystem _fs;
  final LinkStrategy _link;

  Future<MaterializeResult> reconcile({
    required String kindDir,
    required List<ResourceRef> desired,
  }) async {
    final path = _fs.pathContext;
    await _fs.ensureDir(kindDir);

    final existing = await _fs.listDir(kindDir);
    final desiredByName = {for (final r in desired) r.linkName: r};

    // Remove stale entries.
    for (final entry in existing) {
      if (!desiredByName.containsKey(entry.name)) {
        await _fs.removeRecursive(path.join(kindDir, entry.name));
      }
    }
    final existingNames = {
      for (final e in existing)
        if (desiredByName.containsKey(e.name)) e.name,
    };

    final linked = <String>[];
    final errors = <String>[];
    for (final ref in desired) {
      final target = path.join(kindDir, ref.linkName);
      final src = await _fs.stat(ref.sourceDir);
      if (!src.isDirectory) {
        errors.add('${ref.id}: source missing at ${ref.sourceDir}');
        continue;
      }
      if (existingNames.contains(ref.linkName)) {
        // Present already. Keep if a symlink points at the right source;
        // otherwise rebuild (stale target, or a prior copy that may be stale).
        final current = await _fs.readSymlinkTarget(target);
        if (current == ref.sourceDir) {
          linked.add(ref.linkName);
          continue;
        }
        await _fs.removeRecursive(target);
      }
      try {
        await _link.link(source: ref.sourceDir, target: target);
        linked.add(ref.linkName);
      } catch (e) {
        errors.add('${ref.id}: $e');
        appLogger.w('[resource] link failed for ${ref.id}: $e');
      }
    }
    return MaterializeResult(linked: linked, errors: errors);
  }
}
