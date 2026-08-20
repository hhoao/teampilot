import 'dart:collection';

import '../../models/config_bundle.dart';
import '../../repositories/workspace_project_config_repository.dart';
import 'catalog_kind.dart';

/// Binds catalog ids into a workspace [ConfigBundle] (`project-config.json`).
///
/// v1 accepts [CatalogBindTo.workspace] only.
class CatalogWorkspaceBinder {
  CatalogWorkspaceBinder({WorkspaceProjectConfigRepository? repo})
    : _repo = repo ?? WorkspaceProjectConfigRepository();

  final WorkspaceProjectConfigRepository _repo;

  Future<void> bindIds({
    required String workspaceId,
    required CatalogBindTo bindTo,
    required void Function(ConfigBundle current) apply,
  }) {
    return _mutate(workspaceId: workspaceId, bindTo: bindTo, apply: apply);
  }

  Future<void> unbindIds({
    required String workspaceId,
    required CatalogBindTo bindTo,
    required void Function(ConfigBundle current) apply,
  }) {
    return _mutate(workspaceId: workspaceId, bindTo: bindTo, apply: apply);
  }

  Future<void> _mutate({
    required String workspaceId,
    required CatalogBindTo bindTo,
    required void Function(ConfigBundle current) apply,
  }) async {
    if (bindTo != CatalogBindTo.workspace) {
      throw CatalogException(
        'bind_scope_unsupported',
        'bind_to other than workspace is not supported',
      );
    }
    await _repo.updateBundle(workspaceId, (config) {
      final draft = ConfigBundle(
        skillIds: List<String>.of(config.bundle.skillIds),
        pluginIds: List<String>.of(config.bundle.pluginIds),
        mcpServerIds: List<String>.of(config.bundle.mcpServerIds),
        hookIds: List<String>.of(config.bundle.hookIds),
      );
      apply(draft);
      return config.copyWith(
        bundle: ConfigBundle(
          skillIds: LinkedHashSet<String>.of(draft.skillIds).toList(),
          pluginIds: LinkedHashSet<String>.of(draft.pluginIds).toList(),
          mcpServerIds: LinkedHashSet<String>.of(draft.mcpServerIds).toList(),
          hookIds: LinkedHashSet<String>.of(draft.hookIds).toList(),
        ),
      );
    });
  }
}
