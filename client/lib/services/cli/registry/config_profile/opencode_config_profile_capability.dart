import 'package:flutter/foundation.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/personal_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../provider/opencode/opencode_auth_artifacts.dart';
import '../../../provider/opencode/opencode_data_layout.dart';
import '../../../provider/opencode/opencode_provider_settings_resolver.dart';
import '../../../provider/opencode/opencode_effort_capability.dart';
import '../../../session/member_role_provision.dart';
import '../../../storage/runtime_storage_context.dart';
import '../../../team_bus/mcp/bus_bridge_locator.dart';
import '../../../team_bus/mcp/teammate_bus_mcp_config.dart';
import '../capabilities/cli_effort_capability.dart';
import '../capabilities/config_profile_capability.dart';
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

/// opencode 工具调用超时(ms）。opencode 默认只有 30s（`DEFAULT_TIMEOUT`），长阻塞的
/// `wait_for_message` 因此很快超时。opencode 用同一个 MCP SDK，超时由 config 的
/// `timeout` 控；设大到 24h 让它不主动超时（stdio 下这是唯一上限；remote 下也把
/// 30s 提到 24h，严格改进）。对齐 claude 的 `busToolTimeoutMs`。
const opencodeBusToolTimeoutMs = 86400000; // 24h

/// Merges the teammate-bus MCP server into opencode.json `mcp` so the member can
/// send/receive teammate messages (mixed mode).
///
/// opencode uses the top-level `mcp` field (not `mcpServers`). 传 [bridgePath]
/// （本地 PTY + 桥接可用）→ `type: "local"`（stdio，经 `teammate_bus_bridge` 绕开
/// HTTP 传输超时，`wait_for_message` 真阻塞）；否则 `type: "remote"`（HTTP 回落）。
/// 两者都带 `timeout` = [opencodeBusToolTimeoutMs]，并需 `enabled` 才会启动加载。
@visibleForTesting
Map<String, Object?> mergeOpencodeTeammateBusMcp(
  Map<String, Object?> config,
  String memberId,
  int port, {
  String? bridgePath,
}) {
  final servers = <String, Object?>{
    ...((config['mcp'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final endpoint = 'http://127.0.0.1:$port/mcp';
  servers[teammateBusMcpServerName] = bridgePath != null
      ? <String, Object?>{
          'type': 'local',
          'command': <String>[
            bridgePath,
            '--member',
            memberId,
            '--bus-url',
            endpoint,
          ],
          'enabled': true,
          'timeout': opencodeBusToolTimeoutMs,
        }
      : <String, Object?>{
          'type': 'remote',
          'url': endpoint,
          'enabled': true,
          'headers': <String, Object?>{teammateBusMcpMemberHeader: memberId},
          'timeout': opencodeBusToolTimeoutMs,
        };
  return {...config, 'mcp': servers};
}

/// Merges a provider's credentials into opencode.json `provider.<id>.options`.
///
/// opencode reads `apiKey` / `baseURL` (note the capital `URL`) from the
/// provider's `options`; an optional `npm` (from the app provider's `config`)
/// tells opencode which SDK to use for fully custom, non-catalog providers.
@visibleForTesting
Map<String, Object?> mergeOpencodeProvider(
  Map<String, Object?> config,
  AppProviderConfig provider,
) {
  final id = provider.id.trim();
  if (id.isEmpty) return config;

  final providers = <String, Object?>{
    ...((config['provider'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  final existing =
      (providers[id] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
  final entry = <String, Object?>{...existing};
  final options = <String, Object?>{
    ...((existing['options'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };

  final apiKey = provider.apiKey.trim();
  if (apiKey.isNotEmpty) options['apiKey'] = apiKey;
  final baseUrl = provider.baseUrl.trim();
  if (baseUrl.isNotEmpty) options['baseURL'] = baseUrl;

  final npm = provider.config['npm'];
  if (npm is String && npm.trim().isNotEmpty && entry['npm'] == null) {
    entry['npm'] = npm.trim();
  }

  if (options.isNotEmpty) entry['options'] = options;
  if (entry.isEmpty) return config;

  providers[id] = entry;
  return {...config, 'provider': providers};
}

/// Writes `provider.<id>.models.<model>.options.reasoningEffort` for launch.
@visibleForTesting
Map<String, Object?> mergeOpencodeReasoningEffort(
  Map<String, Object?> config,
  AppProviderConfig provider,
  String reasoningEffort, {
  String? memberModel,
}) {
  final effort = reasoningEffort.trim();
  if (effort.isEmpty) return config;

  final providerId = provider.id.trim();
  final modelId = (memberModel?.trim().isNotEmpty ?? false)
      ? memberModel!.trim()
      : provider.defaultModel.trim();
  if (providerId.isEmpty || modelId.isEmpty) return config;

  final providers = <String, Object?>{
    ...((config['provider'] as Map?)?.cast<String, Object?>() ??
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
  final options = <String, Object?>{
    ...((modelEntry['options'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{}),
  };
  options['reasoningEffort'] = effort;
  modelEntry['options'] = options;
  models[modelId] = modelEntry;
  entry['models'] = models;
  providers[providerId] = entry;
  return {...config, 'provider': providers};
}

/// opencode CLI launch: provisions a per-session config dir (`OPENCODE_CONFIG_DIR`)
/// holding `opencode.json` (provider credentials, member identity via `AGENTS.md`,
/// and in mixed mode the team-bus idle plugin + teammate-bus MCP server).
final class OpencodeConfigProfileCapability implements ConfigProfileCapability {
  const OpencodeConfigProfileCapability();

  static const toolId = 'opencode';
  static const opencodeConfigFileName = 'opencode.json';
  static const agentsFileName = 'AGENTS.md';

  /// opencode treats `OPENCODE_CONFIG_DIR` as its config root: it loads
  /// `opencode.json` from this dir and auto-discovers `AGENTS.md` here as a
  /// global instruction. (The bare `OPENCODE` env is an internal run marker,
  /// not a path — setting it does nothing.)
  static const configDirEnv = 'OPENCODE_CONFIG_DIR';

  /// opencode stores session/message JSON under `$OPENCODE_DATA_DIR/storage`
  /// (default: the global `~/.local/share/opencode`). We pin it to the
  /// per-session config dir so the captured `ses_*` id is unambiguous and
  /// resume never crosses sessions. See docs/session-resume-architecture.md.
  static const dataDirEnv = 'OPENCODE_DATA_DIR';
  static const authContentEnv = 'OPENCODE_AUTH_CONTENT';

  static const _opencodeDataLayout = OpencodeDataLayout();

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final standalone = ctx.standaloneScope;
    final personal = ctx.personal;
    if (standalone != null && personal != null) {
      return _contributeStandaloneLaunch(ctx, standalone, personal);
    }
    return _contributeTeamLaunch(ctx);
  }

  Future<ConfigProfileLaunchContribution> _contributeTeamLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final paths = ctx.paths;
    final opencodeDir = paths.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      toolId,
      memberId: ctx.scope.memberId,
    );
    final team = ctx.team;
    final member = ctx.member;
    final mixed = team?.teamMode == TeamMode.mixed;
    final warnings = <String>[];

    await paths.fs.ensureDir(opencodeDir);

    final configPath = paths.pathContext.join(
      opencodeDir,
      opencodeConfigFileName,
    );
    var config = await paths.readSettingsFile(configPath);
    var changed = false;
    AppProviderConfig? launchProvider;

    if (team != null) {
      launchProvider = await _resolver(paths).resolveForLaunch(
        team: team,
        member: member,
      );
      if (launchProvider == null) {
        warnings.add('opencode_provider_missing');
      } else {
        config = mergeOpencodeProvider(config, launchProvider);
        final effort = _resolveOpencodeEffort(
          team: team,
          member: member,
          provider: launchProvider,
          profileEffort: '',
        );
        if (effort.isNotEmpty) {
          config = mergeOpencodeReasoningEffort(
            config,
            launchProvider,
            effort,
            memberModel: member?.model,
          );
        }
        changed = true;
      }
    }

    if (await _writeMemberIdentity(
      paths: paths,
      opencodeDir: opencodeDir,
      member: member,
      forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
      mixed: mixed,
    )) {
      changed = true;
    }

    final idleUrl = ctx.busIdleUrl;
    if (mixed &&
        idleUrl != null &&
        idleUrl.isNotEmpty &&
        member != null &&
        member.isValid) {
      final port = parseBusPortFromIdleUrl(idleUrl);
      if (port != null) {
        await _writeIdlePlugin(paths: paths, opencodeDir: opencodeDir);
        config = mergeOpencodeIdlePlugin(config, member.id, port);
        // 本地 PTY（native 后端）+ 桥接 exe 可用 → stdio（真无限阻塞）；否则 remote。
        final localNative = !RuntimeStorageContext.isInstalled ||
            RuntimeStorageContext.current.mode == StorageBackendMode.native;
        final bridgePath = localNative ? BusBridgeLocator.resolve() : null;
        config = mergeOpencodeTeammateBusMcp(
          config,
          member.id,
          port,
          bridgePath: bridgePath,
        );
        changed = true;
      }
    }

    if (changed) {
      await paths.writeJsonIfChanged(configPath, config);
    }

    final environment = <String, String>{
      configDirEnv: opencodeDir,
      dataDirEnv: opencodeDir,
    };
    final authContent = launchProvider == null
        ? null
        : await _readStoredAuthContent(paths, launchProvider);
    if (authContent != null) {
      environment[authContentEnv] = authContent;
    }

    return ConfigProfileLaunchContribution(
      environment: environment,
      warnings: warnings,
    );
  }

  Future<ConfigProfileLaunchContribution> _contributeStandaloneLaunch(
    ConfigProfileLaunchContext ctx,
    StandaloneLaunchProfileScope standalone,
    PersonalProfile personal,
  ) async {
    final paths = ctx.paths;
    final opencodeDir = standaloneSessionToolDir(paths, standalone, toolId);
    await paths.fs.ensureDir(opencodeDir);

    final configPath = paths.pathContext.join(
      opencodeDir,
      opencodeConfigFileName,
    );
    var config = await paths.readSettingsFile(configPath);
    var changed = false;

    final resolver = _resolver(paths);
    var provider = await resolver.findById(standaloneProviderId(ctx.preset));
    provider ??= await resolver.resolveSole();
    if (provider != null) {
      config = mergeOpencodeProvider(config, provider);
      final member = standaloneMemberFromPersonal(personal, preset: ctx.preset);
      final effort = _resolveOpencodeEffort(
        team: null,
        member: member,
        provider: provider,
        profileEffort: ctx.preset?.effort ?? '',
      );
      if (effort.isNotEmpty) {
        config = mergeOpencodeReasoningEffort(
          config,
          provider,
          effort,
          memberModel: member.model,
        );
      }
      changed = true;
    }

    if (await _writeMemberIdentity(
      paths: paths,
      opencodeDir: opencodeDir,
      member: standaloneMemberFromPersonal(personal, preset: ctx.preset),
      forceTeamLeadDelegateMode: false,
      mixed: false,
    )) {
      changed = true;
    }

    if (changed) {
      await paths.writeJsonIfChanged(configPath, config);
    }

    final environment = <String, String>{
      configDirEnv: opencodeDir,
      dataDirEnv: opencodeDir,
    };
    final authContent = provider == null
        ? null
        : await _readStoredAuthContent(paths, provider);
    if (authContent != null) {
      environment[authContentEnv] = authContent;
    }

    return ConfigProfileLaunchContribution(
      environment: environment,
    );
  }

  Future<String?> _readStoredAuthContent(
    ConfigProfileDelegate paths,
    AppProviderConfig provider,
  ) async {
    if (!provider.isOfficial) return null;
    final providerDir = paths.pathContext.join(
      paths.basePath,
      'providers',
      'opencode',
      provider.id,
    );
    final authPath = _opencodeDataLayout.providerAuthJsonPath(providerDir);
    if (!(await paths.fs.stat(authPath)).isFile) return null;
    final content = await paths.fs.readString(authPath);
    if (content == null || content.trim().isEmpty) return null;
    if (!OpencodeAuthArtifacts.authJsonIndicatesReady(content, provider.id)) {
      return null;
    }
    return content.trim();
  }

  OpencodeProviderSettingsResolver _resolver(ConfigProfileDelegate paths) =>
      OpencodeProviderSettingsResolver(
        basePath: paths.basePath,
        repository: AppProviderRepository(
          basePath: paths.basePath,
          fs: paths.fs,
        ),
      );

  /// Writes member identity to `AGENTS.md`; opencode auto-loads it from the
  /// config dir as a global instruction. Returns whether anything was written.
  Future<bool> _writeMemberIdentity({
    required ConfigProfileDelegate paths,
    required String opencodeDir,
    required TeamMemberConfig? member,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
  }) async {
    if (member == null || !member.isValid) return false;
    final prompt = MemberRoleProvision.composeRolePrompt(
      member: member,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: mixed,
    ).trim();
    if (prompt.isEmpty) return false;
    await paths.fs.atomicWrite(
      paths.pathContext.join(opencodeDir, agentsFileName),
      '$prompt\n',
    );
    return true;
  }

  Future<void> _writeIdlePlugin({
    required ConfigProfileDelegate paths,
    required String opencodeDir,
  }) async {
    final pluginPath = paths.pathContext.join(
      opencodeDir,
      opencodeIdlePluginFileName,
    );
    final existing = await paths.fs.readString(pluginPath);
    if (existing == opencodeIdlePluginSource) {
      return;
    }
    await paths.fs.atomicWrite(pluginPath, opencodeIdlePluginSource);
  }

  static String _resolveOpencodeEffort({
    required TeamProfile? team,
    required TeamMemberConfig? member,
    required AppProviderConfig provider,
    String? profileEffort,
  }) {
    if (profileEffort != null && profileEffort.trim().isNotEmpty) {
      return profileEffort.trim();
    }
    const capability = OpencodeEffortCapability();
    return resolveLaunchEffort(
      capability: capability,
      cli: CliTool.opencode,
      context: EffortResolveContext(
        team: team,
        member: member,
        provider: provider,
        model: member?.model.isNotEmpty == true
            ? member!.model
            : provider.defaultModel,
      ),
    );
  }
}
