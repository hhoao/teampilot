import 'package:flutter/foundation.dart';

import '../../../../models/team_config.dart';
import '../capabilities/config_profile_capability.dart';
import 'config_profile_context.dart';
import 'opencode_idle_plugin.dart';

/// Parses bus idle URL (e.g. `http://127.0.0.1:12345/idle`) to the listening port.
@visibleForTesting
int? parseBusPortFromIdleUrl(String? idleUrl) {
  if (idleUrl == null || idleUrl.isEmpty) return null;
  final uri = Uri.tryParse(idleUrl);
  if (uri == null || !uri.hasPort) return null;
  return uri.port;
}

/// Merges opencode.json `plugin` entry for TeamBus idle reporting (mixed mode).
@visibleForTesting
Map<String, Object?> mergeOpencodeIdlePlugin(
  Map<String, Object?> config,
  String memberId,
  int port,
) {
  final pluginPath = './$opencodeIdlePluginFileName';
  final entry = <Object?>[
    pluginPath,
    <String, Object?>{'member': memberId, 'port': port},
  ];
  final plugins = List<Object?>.from((config['plugin'] as List?) ?? const []);
  final exists = plugins.any(
    (e) =>
        e is List &&
        e.isNotEmpty &&
        e[0] == pluginPath &&
        e.length > 1 &&
        e[1] is Map &&
        (e[1] as Map)['member'] == memberId &&
        (e[1] as Map)['port'] == port,
  );
  if (!exists) {
    plugins.add(entry);
  }
  return {...config, 'plugin': plugins};
}

final class OpencodeConfigProfileCapability implements ConfigProfileCapability {
  const OpencodeConfigProfileCapability();

  static const opencodeConfigFileName = 'opencode.json';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final delegate = ctx.paths;
    final scope = ctx.scope;
    final opencodeDir = delegate.sessionToolDir(
      scope.teamId,
      scope.sessionId,
      'opencode',
    );

    final mixed = ctx.team?.teamMode == TeamMode.mixed;
    final idleUrl = ctx.busIdleUrl;
    final member = ctx.member;
    if (mixed &&
        idleUrl != null &&
        idleUrl.isNotEmpty &&
        member != null &&
        member.isValid) {
      final port = parseBusPortFromIdleUrl(idleUrl);
      if (port != null) {
        await _writeIdlePlugin(delegate: delegate, opencodeDir: opencodeDir);
        await _writeOpencodeConfig(
          delegate: delegate,
          opencodeDir: opencodeDir,
          memberId: member.id,
          port: port,
        );
      }
    }

    return ConfigProfileLaunchContribution(
      environment: {
        'OPENCODE': opencodeDir,
      },
    );
  }

  Future<void> _writeIdlePlugin({
    required ConfigProfileDelegate delegate,
    required String opencodeDir,
  }) async {
    final pluginPath = delegate.pathContext.join(
      opencodeDir,
      opencodeIdlePluginFileName,
    );
    final existing = await delegate.fs.readString(pluginPath);
    if (existing == opencodeIdlePluginSource) {
      return;
    }
    await delegate.fs.atomicWrite(pluginPath, opencodeIdlePluginSource);
  }

  Future<void> _writeOpencodeConfig({
    required ConfigProfileDelegate delegate,
    required String opencodeDir,
    required String memberId,
    required int port,
  }) async {
    final configPath = delegate.pathContext.join(
      opencodeDir,
      opencodeConfigFileName,
    );
    final existing = await delegate.readSettingsFile(configPath);
    final merged = mergeOpencodeIdlePlugin(existing, memberId, port);
    await delegate.writeJsonIfChanged(configPath, merged);
  }
}
