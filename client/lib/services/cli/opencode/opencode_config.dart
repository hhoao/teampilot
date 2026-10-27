import '../../../models/app_provider_config.dart';
import '../../../models/team_config.dart';
import '../../chat/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../registry/launch/cli_launch_capability_error.dart';

/// Native OpenCode v2 `opencode.json` merge helpers.
///
/// TeamPilot writes v2 keys only (`plugins`, `permissions`, `mcp.servers`,
/// `providers`, `model`, `default_agent`). V1 fields are not read or preserved.

const opencodeBusToolTimeoutMs = 86400000; // 24h

const opencodePluginsKey = 'plugins';
const opencodePermissionsKey = 'permissions';
const opencodeProvidersKey = 'providers';
const opencodeMcpKey = 'mcp';
const opencodeMcpServersKey = 'servers';
const opencodeModelKey = 'model';
const opencodeDefaultAgentKey = 'default_agent';

/// Stored on [AppProviderConfig.config] for OpenCode-only staging namespace.
abstract final class OpencodeProviderConfigKeys {
  OpencodeProviderConfigKeys._();

  static const subscription = 'opencodeSubscription';
}

/// OpenCode `opencode.json` provider key and `model` prefix (e.g. `opencode-go`).
///
/// When [OpencodeProviderConfigKeys.subscription] is set, it wins over [AppProviderConfig.id]
/// so TeamPilot can keep stable catalog ids (`opencode-go-2`) while reusing one
/// OpenCode provider namespace.
String opencodeStagingProviderKey(AppProviderConfig provider) {
  final subscription =
      provider.config[OpencodeProviderConfigKeys.subscription]?.toString().trim() ??
      '';
  if (subscription.isNotEmpty) return subscription;
  return provider.id.trim();
}

/// v2 TUI has no `--model`; the default is `opencode.json` `"model"`.
Map<String, Object?> mergeOpencodeDefaultModel(
  Map<String, Object?> config, {
  required String? providerId,
  required String? modelId,
}) {
  final provider = providerId?.trim() ?? '';
  final model = modelId?.trim() ?? '';
  if (model.isEmpty) return config;
  final selector = provider.isEmpty ? model : '$provider/$model';
  if (config[opencodeModelKey] == selector) return config;
  var next = {...config, opencodeModelKey: selector};
  if (provider.isNotEmpty) {
    next = mergeOpencodeEnsureModelInProvider(
      next,
      providerKey: provider,
      modelId: model,
    );
  }
  return next;
}

Map<String, Object?> mergeOpencodeEnsureModelInProvider(
  Map<String, Object?> config, {
  required String providerKey,
  required String modelId,
}) {
  final provider = providerKey.trim();
  final model = modelId.trim();
  if (provider.isEmpty || model.isEmpty) return config;

  final providers = <String, Object?>{
    ...((config[opencodeProvidersKey] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final existing =
      (providers[provider] as Map?)?.cast<String, Object?>() ??
      <String, Object?>{};
  final models = <String, Object?>{
    ...((existing['models'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  if (models.containsKey(model)) return config;
  models[model] = <String, Object?>{'name': model};
  providers[provider] = {...existing, 'models': models};
  return {...config, opencodeProvidersKey: providers};
}

/// v2 TUI has no `--agent`; the default is `opencode.json` `"default_agent"`.
Map<String, Object?> mergeOpencodeDefaultAgent(
  Map<String, Object?> config,
  String? agent,
) {
  final id = agent?.trim() ?? '';
  if (id.isEmpty) return config;
  if (config[opencodeDefaultAgentKey] == id) return config;
  return {...config, opencodeDefaultAgentKey: id};
}

Map<String, Object?> opencodePluginObject({
  required String package,
  Map<String, Object?>? options,
}) {
  if (options == null || options.isEmpty) {
    return <String, Object?>{'package': package};
  }
  return <String, Object?>{'package': package, 'options': options};
}

String? opencodePluginPackageOf(Object? entry) {
  if (entry is String) {
    final path = entry.trim();
    return path.isEmpty ? null : path;
  }
  if (entry is Map) {
    final package = entry['package']?.toString().trim() ?? '';
    return package.isEmpty ? null : package;
  }
  return null;
}

Map<String, Object?>? opencodePluginOptionsOf(Object? entry) {
  if (entry is! Map) return null;
  final options = entry['options'];
  if (options is! Map) return null;
  return options.cast<String, Object?>();
}

Object? opencodePluginMemberOf(Object? entry) =>
    opencodePluginOptionsOf(entry)?['member'];

Map<String, Object?> mergeOpencodeIdlePlugin(
  Map<String, Object?> config,
  String memberId,
  int port, {
  String? token,
  String? sessionId,
}) {
  final options = <String, Object?>{'member': memberId, 'port': port};
  if (sessionId != null && sessionId.isNotEmpty) {
    options['session'] = sessionId;
  }
  if (token != null && token.isNotEmpty) {
    options['token'] = token;
  }
  return mergeOpencodePluginEntries(config, [
    opencodePluginObject(package: './teampilot-idle-bus.js', options: options),
  ]);
}

/// Merges plugin entries into the v2 `plugins` array.
///
/// String paths are appended once. Object entries (`{package, options}`)
/// replace the existing object for the same package and member, so a
/// reconnect updates its endpoint without accumulating stale seat-scoped
/// runtime plugins.
Map<String, Object?> mergeOpencodePluginEntries(
  Map<String, Object?> config,
  Iterable<Object?> entries,
) {
  if (entries.isEmpty) return config;
  final plugins = List<Object?>.from(
    (config[opencodePluginsKey] as List?) ?? const [],
  );
  var changed = false;
  for (final entry in entries) {
    final path = opencodePluginPackageOf(entry);
    if (path == null) continue;
    final memberId = opencodePluginMemberOf(entry);
    final matchingIndexes = <int>[
      for (var index = 0; index < plugins.length; index++)
        if (opencodePluginPackageOf(plugins[index]) == path &&
            (memberId == null ||
                opencodePluginMemberOf(plugins[index]) == memberId))
          index,
    ];
    if (matchingIndexes.isEmpty) {
      plugins.add(entry);
      changed = true;
      continue;
    }
    if (entry is Map) {
      final existingIndex = matchingIndexes.first;
      if (plugins[existingIndex] != entry) {
        plugins[existingIndex] = entry;
        changed = true;
      }
      for (final index in matchingIndexes.skip(1).toList().reversed) {
        plugins.removeAt(index);
        changed = true;
      }
    }
  }
  if (!changed) return config;
  return {...config, opencodePluginsKey: plugins};
}

Map<String, Object?> opencodeMcpServersOf(Map<String, Object?> config) {
  final mcp =
      (config[opencodeMcpKey] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};
  return (mcp[opencodeMcpServersKey] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};
}

Map<String, Object?> withOpencodeMcpServers(
  Map<String, Object?> config,
  Map<String, Object?> servers,
) {
  final mcp = <String, Object?>{
    ...((config[opencodeMcpKey] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
    opencodeMcpServersKey: servers,
  };
  return {...config, opencodeMcpKey: mcp};
}

Map<String, Object?> opencodeMcpTimeout({required int milliseconds}) =>
    <String, Object?>{'catalog': milliseconds, 'execution': milliseconds};

/// Merges the teammate-bus MCP server into `mcp.servers`.
Map<String, Object?> mergeOpencodeTeammateBusMcp(
  Map<String, Object?> config,
  String memberId,
  int port, {
  required String sessionId,
  String? bridgePath,
}) {
  final servers = <String, Object?>{...opencodeMcpServersOf(config)};
  final endpoint = 'http://127.0.0.1:$port/mcp';
  servers[teammateBusMcpServerName] = bridgePath != null
      ? <String, Object?>{
          'type': 'local',
          'command': <String>[
            bridgePath,
            '--member',
            memberId,
            '--session',
            sessionId,
            '--bus-url',
            endpoint,
          ],
          'disabled': false,
          'timeout': opencodeMcpTimeout(milliseconds: opencodeBusToolTimeoutMs),
        }
      : <String, Object?>{
          'type': 'remote',
          'url': endpoint,
          'disabled': false,
          'headers': <String, Object?>{
            teammateBusMcpMemberHeader: memberId,
            teammateBusMcpSessionHeader: sessionId,
          },
          'timeout': opencodeMcpTimeout(milliseconds: opencodeBusToolTimeoutMs),
        };
  return withOpencodeMcpServers(config, servers);
}

String? opencodeProviderPackage(String npm) {
  final trimmed = npm.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('aisdk:')) return trimmed;
  if (trimmed.contains('ai-sdk')) return 'aisdk:$trimmed';
  return trimmed;
}

Map<String, Object?> mergeOpencodeProvider(
  Map<String, Object?> config,
  AppProviderConfig provider,
) {
  final id = opencodeStagingProviderKey(provider);
  if (id.isEmpty) return config;

  final providers = <String, Object?>{
    ...((config[opencodeProvidersKey] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final existing =
      (providers[id] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
  final entry = <String, Object?>{...existing};
  final settings = <String, Object?>{
    ...((existing['settings'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };

  final apiKey = provider.apiKey.trim();
  if (apiKey.isNotEmpty) settings['apiKey'] = apiKey;
  final baseUrl = provider.baseUrl.trim();
  if (baseUrl.isNotEmpty) settings['baseURL'] = baseUrl;

  final npm = provider.config['npm'];
  if (npm is String) {
    final packageName = opencodeProviderPackage(npm);
    if (packageName != null && entry['package'] == null) {
      entry['package'] = packageName;
    }
  }

  final defaultModel = provider.defaultModel.trim();
  if (defaultModel.isNotEmpty) {
    final models = <String, Object?>{
      ...((entry['models'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{}),
    };
    if (!models.containsKey(defaultModel)) {
      models[defaultModel] = <String, Object?>{'name': defaultModel};
      entry['models'] = models;
    }
  }

  if (settings.isNotEmpty) entry['settings'] = settings;
  if (entry.isEmpty) return config;

  providers[id] = entry;
  return {...config, opencodeProvidersKey: providers};
}

Map<String, Object?> mergeOpencodeReasoningEffort(
  Map<String, Object?> config,
  AppProviderConfig provider,
  String reasoningEffort, {
  String? memberModel,
}) {
  final effort = reasoningEffort.trim();
  if (effort.isEmpty) return config;

  final providerId = opencodeStagingProviderKey(provider);
  final modelId = (memberModel?.trim().isNotEmpty ?? false)
      ? memberModel!.trim()
      : provider.defaultModel.trim();
  if (providerId.isEmpty || modelId.isEmpty) return config;

  final providers = <String, Object?>{
    ...((config[opencodeProvidersKey] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final existing =
      (providers[providerId] as Map?)?.cast<String, Object?>() ??
      <String, Object?>{};
  final entry = <String, Object?>{...existing};
  final models = <String, Object?>{
    ...((existing['models'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final modelEntry = <String, Object?>{
    ...((models[modelId] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final settings = <String, Object?>{
    ...((modelEntry['settings'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  settings['reasoningEffort'] = effort;
  modelEntry['settings'] = settings;
  models[modelId] = modelEntry;
  entry['models'] = models;
  providers[providerId] = entry;
  return {...config, opencodeProvidersKey: providers};
}

List<Map<String, Object?>> opencodePermissionsOf(Map<String, Object?> config) {
  final raw = config[opencodePermissionsKey];
  if (raw is! List) return <Map<String, Object?>>[];
  return [
    for (final entry in raw)
      if (entry is Map) entry.cast<String, Object?>(),
  ];
}

bool _samePermissionRule(Map<String, Object?> a, Map<String, Object?> b) =>
    a['action'] == b['action'] && a['resource'] == b['resource'];

Map<String, Object?> upsertOpencodePermission(
  Map<String, Object?> config,
  Map<String, Object?> rule,
) {
  final permissions = opencodePermissionsOf(config);
  final index = permissions.indexWhere(
    (existing) => _samePermissionRule(existing, rule),
  );
  if (index >= 0) {
    if (permissions[index]['effect'] == rule['effect']) return config;
    permissions[index] = rule;
  } else {
    permissions.add(rule);
  }
  return {...config, opencodePermissionsKey: permissions};
}

String opencodeExternalDirectoryResource(String directory) {
  final trimmed = directory.trim();
  if (trimmed.endsWith('/')) return '$trimmed*';
  return '$trimmed/*';
}

Map<String, Object?> mergeOpencodeExternalDirectories(
  Map<String, Object?> config,
  Iterable<String> directories,
) {
  var next = config;
  var changed = false;
  for (final dir in directories) {
    final trimmed = dir.trim();
    if (trimmed.isEmpty) continue;
    final updated = upsertOpencodePermission(next, <String, Object?>{
      'action': 'external_directory',
      'resource': opencodeExternalDirectoryResource(trimmed),
      'effect': 'allow',
    });
    if (!identical(updated, next)) {
      next = updated;
      changed = true;
    }
  }
  return changed ? next : config;
}

Map<String, Object?> mergeOpencodeSecurityPolicy(
  Map<String, Object?> config,
  LaunchSecurityPolicy policy,
) {
  if (policy == LaunchSecurityPolicy.cliDefault) return config;
  if (policy != LaunchSecurityPolicy.fullAccess) {
    throw const CliLaunchCapabilityException(
      cli: CliTool.opencode,
      contributionKey: 'opencode-permission',
      reason:
          'OpenCode cannot represent this launch security policy through its '
          'current permission config schema.',
      exclusiveGroup: 'opencode-permission-mode',
    );
  }

  var next = upsertOpencodePermission(config, const {
    'action': 'edit',
    'resource': '*',
    'effect': 'allow',
  });
  next = upsertOpencodePermission(next, const {
    'action': 'shell',
    'resource': '*',
    'effect': 'allow',
  });
  next = upsertOpencodePermission(next, const {
    'action': 'external_directory',
    'resource': '*',
    'effect': 'allow',
  });
  return next;
}
