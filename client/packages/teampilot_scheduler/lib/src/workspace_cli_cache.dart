import 'session_layout.dart';

final class CliCacheBinding {
  const CliCacheBinding({
    required this.cacheRel,
    required this.toolRel,
    this.isFile = false,
  });

  final String cacheRel;
  final String toolRel;
  final bool isFile;
}

final class WorkspaceCliCache {
  WorkspaceCliCache({required this.layout});

  final SessionLayout layout;

  static const sharedProviderKey = '_shared';
  static const cursorPluginsCacheRel = 'plugins/cache';
  static const cursorStatsigRel = 'statsig-cache.json';
  static const codexTmpPluginsCacheRel = 'tmp-plugins';
  static const codexPluginsCacheRel = 'plugins-cache';

  static String providerKey(String? providerId) {
    final trimmed = providerId?.trim() ?? '';
    return trimmed.isEmpty ? sharedProviderKey : trimmed;
  }

  String globalRoot({required String tool, String? providerId}) =>
      layout.pathContext.join(
        layout.teampilotRoot,
        'workspace',
        'cache',
        'cli',
        tool.trim(),
        providerKey(providerId),
      );

  String globalEntryPath({
    required String tool,
    String? providerId,
    required String cacheRel,
  }) => layout.pathContext.join(
    globalRoot(tool: tool, providerId: providerId),
    cacheRel,
  );

  String workspaceToolRelPath({
    required String workspaceId,
    required String tool,
    required String toolRel,
  }) => layout.pathContext.join(
    layout.workspaceConfigToolDir(workspaceId, tool),
    toolRel,
  );

  static List<CliCacheBinding> bindingFor(String tool) => switch (tool.trim()) {
    'cursor' => const [
      CliCacheBinding(
        cacheRel: cursorPluginsCacheRel,
        toolRel: 'home/.cursor/plugins/cache',
      ),
      CliCacheBinding(
        cacheRel: cursorStatsigRel,
        toolRel: 'home/.cursor/statsig-cache.json',
        isFile: true,
      ),
    ],
    'opencode' => const [
      CliCacheBinding(
        cacheRel: 'package.json',
        toolRel: 'package.json',
        isFile: true,
      ),
      CliCacheBinding(
        cacheRel: 'package-lock.json',
        toolRel: 'package-lock.json',
        isFile: true,
      ),
      CliCacheBinding(cacheRel: 'node_modules', toolRel: 'node_modules'),
    ],
    'codex' => const [
      CliCacheBinding(
        cacheRel: codexTmpPluginsCacheRel,
        toolRel: '.tmp/plugins',
      ),
      CliCacheBinding(cacheRel: codexPluginsCacheRel, toolRel: 'plugins/cache'),
    ],
    _ => const [],
  };
}
