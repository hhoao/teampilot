import '../../models/run/launch_configuration.dart';
import '../../models/run/launch_type_contribution.dart';
import '../../models/workspace_folder.dart';
import '../storage/app_storage.dart';
import 'launch_config_store.dart';
import 'launch_type_registry.dart';

/// Glob-based launch configuration recommendations for workspace folders.
///
/// v1 uses extension `discover.globs` only; adapter `discover` RPC is optional
/// and not required for recommendations.
class LaunchDiscover {
  LaunchDiscover({required LaunchConfigIo io}) : _io = io;

  final LaunchConfigIo _io;

  Future<List<OwnedLaunchConfiguration>> discover({
    required List<WorkspaceFolder> folders,
    required LaunchTypeRegistry registry,
    List<OwnedLaunchConfiguration> existing = const [],
  }) async {
    final existingKeys = {
      for (final owned in existing) owned.selectionKey,
    };
    final results = <OwnedLaunchConfiguration>[];

    for (final folder in folders) {
      for (final contribution in registry.contributions) {
        if (!contribution.isDiscoverEnabled) continue;
        if (contribution.discoverGlobs.isEmpty) continue;
        if (!registry.isAvailable(
          contribution.type,
          targetId: folder.targetId,
        )) {
          continue;
        }

        var matched = false;
        for (final glob in contribution.discoverGlobs) {
          if (await _globMatches(folder: folder, glob: glob)) {
            matched = true;
            break;
          }
        }
        if (!matched) continue;

        final owned = OwnedLaunchConfiguration(
          owner: folder,
          configuration: _configurationFromDiscover(contribution),
        );
        if (existingKeys.contains(owned.selectionKey)) continue;
        results.add(owned);
      }
    }

    return results;
  }

  Future<bool> _globMatches({
    required WorkspaceFolder folder,
    required String glob,
  }) async {
    final normalized = glob.replaceAll(r'\', '/');
    // Match [AppPaths.pathContextForDataRoot]: POSIX roots must not become
    // `\proj\…` on Windows hosts (memory IO + WSL/SSH folder paths).
    final ctx = AppPaths.pathContextForDataRoot(folder.path);
    if (!normalized.contains('*') && !normalized.contains('?')) {
      final path = ctx.join(folder.path, normalized);
      return _io.exists(path, targetId: folder.targetId);
    }

    if (normalized.startsWith('**/')) {
      final suffix = normalized.substring(3);
      return _findUnderTree(
        folder: folder,
        root: folder.path,
        suffix: suffix,
      );
    }

    final path = ctx.join(folder.path, normalized);
    return _io.exists(path, targetId: folder.targetId);
  }

  Future<bool> _findUnderTree({
    required WorkspaceFolder folder,
    required String root,
    required String suffix,
  }) async {
    final ctx = AppPaths.pathContextForDataRoot(root);
    final direct = ctx.join(root, suffix);
    if (await _io.exists(direct, targetId: folder.targetId)) {
      return true;
    }

    // Memory / test IO has no listDir — only direct paths are checked.
    return false;
  }

  LaunchConfiguration _configurationFromDiscover(
    LaunchTypeContribution contribution,
  ) {
    final discover = contribution.discover;
    final template = discover?['configuration'];
    final base = <String, Object?>{
      'type': contribution.type,
      if (template is Map) ...template.cast<String, Object?>(),
    };

    final id = (base['id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      base['id'] = contribution.type;
    }

    final name = (base['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      final displayName = discover?['displayName'] as String?;
      base['name'] = displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : contribution.type;
    }

    base['type'] = contribution.type;
    return LaunchConfiguration.fromJson(base);
  }
}
