import 'package:path/path.dart' as p;

import '../../models/team_config.dart';
import 'runtime_layout.dart';

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

  final RuntimeLayout layout;

  static const sharedProviderKey = '_shared';
  static const cursorPluginsCacheRel = 'plugins/cache';
  static const cursorStatsigRel = 'statsig-cache.json';
  static const codexTmpPluginsCacheRel = 'tmp-plugins';
  static const codexPluginsCacheRel = 'plugins-cache';

  static String providerKey(String? providerId) {
    final trimmed = providerId?.trim() ?? '';
    return trimmed.isEmpty ? sharedProviderKey : trimmed;
  }

  p.Context get _ctx => layout.pathContext;

  String globalRoot({required String tool, String? providerId}) => _ctx.join(
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
  }) => _ctx.join(globalRoot(tool: tool, providerId: providerId), cacheRel);

  String workspaceToolRelPath({
    required String workspaceId,
    required String tool,
    required String toolRel,
  }) => _ctx.join(layout.workspaceConfigToolDir(workspaceId, tool), toolRel);

  static List<CliCacheBinding> bindingFor(CliTool tool) => switch (tool) {
    CliTool.cursor => const [
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
    CliTool.opencode => const [
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
    CliTool.codex => const [
      CliCacheBinding(
        cacheRel: codexTmpPluginsCacheRel,
        toolRel: '.tmp/plugins',
      ),
      CliCacheBinding(cacheRel: codexPluginsCacheRel, toolRel: 'plugins/cache'),
    ],
    CliTool.claude || CliTool.flashskyai => const [],
  };
}
