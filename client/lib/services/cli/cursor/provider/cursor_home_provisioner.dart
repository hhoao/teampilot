import 'dart:convert';

import '../../../../models/hook_entry.dart';
import '../../../../models/team_config.dart';
import '../../../host/host_script_runner.dart';
import '../../../hook/glue_script_builder.dart';
import '../../../io/filesystem.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../registry/capabilities/hook_capability.dart';
import '../../registry/capabilities/prompt_capability.dart';
import '../../registry/prompt/prompt_hub_service.dart';
import '../../registry/config_profile/hook_seat_context_completer.dart';
import '../../registry/hook/managed_hook_provisioner.dart';
import '../capabilities/cli_config_merger.dart';
import '../capabilities/prompt.dart';
import 'cursor_auth_artifacts.dart';
import 'cursor_cli_config_policy.dart';
import 'cursor_home_bus_overlay.dart';
import 'cursor_home_layout.dart';
import 'cursor_hook_writer.dart';
import 'cursor_launch_model.dart';
import 'cursor_member_home_passthrough.dart';
import 'cursor_provider_credentials_service.dart';

/// Merges provider auth, role rule, and mixed-mode team-bus overlay into a
/// member fake HOME.
final class CursorHomeProvisioner {
  CursorHomeProvisioner({
    required Filesystem fs,
    CursorHomeLayout? layout,
    CursorProviderCredentialsService? credentials,
    PromptCapability? promptProvision,
  }) : _fs = fs,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext),
       _credentials = credentials,
       _promptProvision =
           promptProvision ??
           CursorPromptCapability(
             fs: fs,
             layout: layout ?? CursorHomeLayout(pathContext: fs.pathContext),
           );

  final Filesystem _fs;
  final CursorHomeLayout _layout;
  final CursorProviderCredentialsService? _credentials;
  final PromptCapability _promptProvision;

  Future<void> provision({
    required String memberHome,
    required String? providerId,
    required TeamMemberConfig member,
    required MemberBusIdleEndpoint? busIdle,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    bool promptAlreadyMaterialized = false,
    String? realHomeRoot,
    String? warmCacheHomeRoot,
  }) async {
    await _ensureCursorDirs(memberHome);
    await _mirrorRealHomePassthrough(
      memberHome: memberHome,
      realHomeRoot: realHomeRoot,
    );

    final id = providerId?.trim();
    if (id != null && id.isNotEmpty) {
      await _credentials?.syncAuthToMemberHome(id, memberHome);
    }
    // After auth sync: seed tip flag (sync skips existing files, so a
    // provider copy without the tip cannot wipe this when we write last).
    await _ensureAgentCommandTipSuppressed(memberHome);

    if (!member.isValid) return;

    await _seedWarmCaches(memberHome, warmCacheHomeRoot: warmCacheHomeRoot);
    await _stampLaunchModel(memberHome, member.model);

    if (!mixed) {
      if (promptAlreadyMaterialized) return;
      await const PromptHubService().provisionForCli(
        cli: CliTool.cursor,
        capability: _promptProvision,
        providers: [_promptProvision as PromptContributionProvider],
        ctx: PromptMaterializeContext(
          member: member,
          memberHome: memberHome,
          forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
          mixed: false,
          pushDelivery: false,
        ),
      );
      return;
    }

    await provisionOverlayOnly(
      memberHome: memberHome,
      member: member,
      busIdle: busIdle,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      warmCacheHomeRoot: warmCacheHomeRoot,
    );
  }

  /// Writes role rule, merged [cli-config.json], and optional bus overlay.
  ///
  /// Does not sync auth or touch member-private paths such as `chats/`.
  Future<void> provisionOverlayOnly({
    required String memberHome,
    required TeamMemberConfig member,
    required MemberBusIdleEndpoint? busIdle,
    required bool forceTeamLeadDelegateMode,
    String? cliConfigJson,
    String? sharedMcpBasePath,
    String? warmCacheHomeRoot,
  }) async {
    if (!member.isValid) return;

    await _ensureOverlayDirs(memberHome);
    await _ensureAgentCommandTipSuppressed(memberHome);
    await _mergeTeamBusPermissions(memberHome, cliConfigJson: cliConfigJson);
    await _seedWarmCaches(memberHome, warmCacheHomeRoot: warmCacheHomeRoot);
    await _stampLaunchModel(memberHome, member.model);
    await const PromptHubService().provisionForCli(
      cli: CliTool.cursor,
      capability: _promptProvision,
      providers: [_promptProvision as PromptContributionProvider],
      ctx: PromptMaterializeContext(
        member: member,
        memberHome: memberHome,
        forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
        mixed: true,
        pushDelivery: true,
      ),
    );

    if (busIdle == null) return;

    await _seedMemberMcpFromBase(
      memberHome: memberHome,
      sharedMcpBasePath: sharedMcpBasePath,
    );
    await _writeBusOverlay(
      memberHome: memberHome,
      member: member,
      busIdle: busIdle,
    );
  }

  Future<void> _mirrorRealHomePassthrough({
    required String memberHome,
    String? realHomeRoot,
  }) async {
    final realHome = realHomeRoot?.trim() ?? '';
    if (realHome.isEmpty) return;
    await CursorMemberHomePassthrough(
      fs: _fs,
      layout: _layout,
    ).mirror(realHomeRoot: realHome, memberHomeRoot: memberHome);
  }

  Future<void> _ensureCursorDirs(String memberHome) async {
    final cursorDir = _layout.cursorDir(memberHome);
    await _fs.ensureDir(cursorDir);
    await _fs.ensureDir(
      _fs.pathContext.join(cursorDir, CursorHomeLayout.rulesDirName),
    );
    await _fs.ensureDir(
      _fs.pathContext.join(cursorDir, CursorHomeLayout.hooksDirName),
    );
    await _fs.ensureDir(_layout.configCursorDir(memberHome));
  }

  /// Suppresses cursor-agent's one-shot "`agent` alias" tip in isolated HOMEs.
  Future<void> _ensureAgentCommandTipSuppressed(String memberHome) async {
    final path = _layout.agentCliState(memberHome);
    Map<String, Object?> existing = {};
    final raw = await _fs.readString(path);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          existing = Map<String, Object?>.from(decoded);
        }
      } on Object {
        // Corrupt state — rewrite a minimal valid tip-suppressed file.
      }
    }
    if (existing[CursorAuthArtifacts.hasShownAgentCommandTipKey] == true) {
      return;
    }
    existing['version'] =
        existing['version'] ?? CursorAuthArtifacts.agentCliStateVersion;
    existing[CursorAuthArtifacts.hasShownAgentCommandTipKey] = true;
    await _fs.atomicWrite(path, _jsonPretty(existing));
  }

  Future<void> _ensureOverlayDirs(String memberHome) async {
    final cursorDir = _layout.cursorDir(memberHome);
    await _fs.ensureDir(cursorDir);
    await _fs.ensureDir(
      _fs.pathContext.join(cursorDir, CursorHomeLayout.rulesDirName),
    );
    await _fs.ensureDir(
      _fs.pathContext.join(cursorDir, CursorHomeLayout.hooksDirName),
    );
  }

  Future<void> _mergeTeamBusPermissions(
    String memberHome, {
    String? cliConfigJson,
  }) async {
    final path = _layout.cliConfig(memberHome);
    final onDisk = await _readCliConfig(path) ?? const <String, Object?>{};
    final baseJson = cliConfigJson;
    final Map<String, Object?> base;
    if (baseJson != null) {
      base = CursorCliConfigPolicy.parseConfigJson(baseJson) ?? const {};
    } else {
      base = onDisk;
    }
    final merged = CursorCliConfigMerger.mergeMemberConfig(
      base: base,
      memberOverrides: baseJson != null ? onDisk : const {},
    );
    await _fs.atomicWrite(path, _jsonPretty(merged));
  }

  Future<void> _seedWarmCaches(
    String memberHome, {
    String? warmCacheHomeRoot,
  }) async {
    final warm = warmCacheHomeRoot?.trim() ?? '';
    if (warm.isEmpty) return;

    await _copyFileIfMissing(
      src: _layout.statsigCache(warm),
      dest: _layout.statsigCache(memberHome),
    );
    await _seedMissingCliConfigFields(
      memberHome: memberHome,
      warmHome: warm,
      keys: const ['serverConfigCache', 'authInfo'],
    );
  }

  Future<void> _copyFileIfMissing({
    required String src,
    required String dest,
  }) async {
    if ((await _fs.stat(dest)).isFile) return;
    if (!(await _fs.stat(src)).isFile) return;
    await _fs.ensureDir(_fs.pathContext.dirname(dest));
    final raw = await _fs.readString(src);
    if (raw == null) return;
    await _fs.atomicWrite(dest, raw);
  }

  Future<void> _seedMissingCliConfigFields({
    required String memberHome,
    required String warmHome,
    required List<String> keys,
  }) async {
    final destPath = _layout.cliConfig(memberHome);
    final dest = await _readCliConfig(destPath) ?? <String, Object?>{};
    final warm = await _readCliConfig(_layout.cliConfig(warmHome));
    if (warm == null) return;

    var changed = false;
    for (final key in keys) {
      if (dest[key] != null) continue;
      final value = warm[key];
      if (value == null) continue;
      dest[key] = value;
      changed = true;
    }
    if (!changed) return;
    dest.putIfAbsent('version', () => CursorCliConfigPolicy.defaultVersion);
    await _fs.ensureDir(_fs.pathContext.dirname(destPath));
    await _fs.atomicWrite(destPath, _jsonPretty(dest));
  }

  Future<void> _stampLaunchModel(String memberHome, String pickerId) async {
    if (pickerId.trim().isEmpty) return;
    final path = _layout.cliConfig(memberHome);
    final existing = await _readCliConfig(path) ?? <String, Object?>{};
    final stamped = CursorLaunchModel.applyToConfig(existing, pickerId);
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.atomicWrite(path, _jsonPretty(stamped));
  }

  Future<Map<String, Object?>?> _readCliConfig(String path) async {
    final raw = await _fs.readString(path);
    if (raw == null) return null;
    return CursorCliConfigPolicy.parseConfigJson(raw);
  }

  Future<void> _writeBusOverlay({
    required String memberHome,
    required TeamMemberConfig member,
    required MemberBusIdleEndpoint busIdle,
  }) async {
    // 收敛：bus idle stop hook 经 completer + 统一 writer 落盘（与
    // config-profile 阶段同一渲染路径，按 command 去重幂等）。
    await writeHooks(
      memberHome: memberHome,
      entries: [
        ...const HookSeatContextCompleter().busAwarenessHooks(
          member: member,
          cli: CliTool.cursor,
          pushDelivery: true,
        ),
        ...const HookSeatContextCompleter().busIdleHooks(
          idle: busIdle,
          memberId: member.id,
        ),
      ],
      runner: null,
    );
    await _mergeTeamBusMcp(
      memberHome: memberHome,
      memberId: member.id,
      busIdle: busIdle,
    );
  }

  /// Writes hooks into `~/.cursor/hooks.json`, preserving existing entries.
  /// Managed（agent-status / bus idle）与用户条目同一渲染路径；glue + 转发
  /// 脚本落在 `~/.cursor/hooks/`。
  Future<void> writeHooks({
    required String memberHome,
    required List<HookEntry> entries,
    required HostScriptRunner? runner,
  }) async {
    if (entries.isEmpty) return;
    final hooksDir = _fs.pathContext.join(
      _layout.cursorDir(memberHome),
      CursorHomeLayout.hooksDirName,
    );
    final result =
        await ManagedHookProvisioner(
          fs: _fs,
          joinWork: _fs.pathContext.join,
          atomicWrite: true,
          ensureParentDirs: true,
        ).provision(
          writer: const CursorHookWriter(),
          entries: entries,
          ctx: HookRenderContext(
            hooksDir: hooksDir,
            runner: runner,
            glueBuilder: const GlueScriptBuilder(),
          ),
        );
    final hooksJsonPath = _layout.hooksConfig(memberHome);
    final existing = await _readHooksJson(hooksJsonPath);
    final fragment =
        (result.configFragments['hooks.json'] as Map<String, Object?>?) ??
        const <String, Object?>{};
    final merged = mergeCursorHooksConfig(existing, fragment);
    await _fs.atomicWrite(hooksJsonPath, _jsonPretty(merged));
  }

  Future<Map<String, Object?>> _readHooksJson(String path) async {
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) {
      return const {'version': 1, 'hooks': <String, Object?>{}};
    }
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  Future<void> _seedMemberMcpFromBase({
    required String memberHome,
    String? sharedMcpBasePath,
  }) async {
    final basePath = sharedMcpBasePath?.trim() ?? '';
    if (basePath.isEmpty) return;

    final baseRaw = await _fs.readString(basePath);
    if (baseRaw == null || baseRaw.trim().isEmpty) return;

    final memberPath = _layout.mcpConfig(memberHome);
    final memberRaw = await _fs.readString(memberPath);
    Map<String, Object?> existing;
    if (memberRaw != null && memberRaw.trim().isNotEmpty) {
      existing = (jsonDecode(memberRaw) as Map).cast<String, Object?>();
    } else {
      existing = (jsonDecode(baseRaw) as Map).cast<String, Object?>();
    }

    final baseServers =
        ((jsonDecode(baseRaw) as Map).cast<String, Object?>()['mcpServers']
                as Map?)
            ?.cast<String, Object?>() ??
        const <String, Object?>{};
    final memberServers =
        ((existing['mcpServers'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{});
    existing['mcpServers'] = <String, Object?>{
      ...baseServers,
      ...memberServers,
    };

    await _fs.atomicWrite(memberPath, _jsonPretty(existing));
  }

  Future<void> _mergeTeamBusMcp({
    required String memberHome,
    required String memberId,
    required MemberBusIdleEndpoint busIdle,
  }) async {
    final path = _layout.mcpConfig(memberHome);
    final raw = await _fs.readString(path);
    Map<String, Object?> existing;
    if (raw != null && raw.trim().isNotEmpty) {
      existing = (jsonDecode(raw) as Map).cast<String, Object?>();
    } else {
      existing = <String, Object?>{};
    }

    final mergedServers = <String, Object?>{
      ...((existing['mcpServers'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{}),
      ...((jsonDecode(
                        CursorHomeBusOverlay.buildMcpJson(
                          memberId: memberId,
                          idle: busIdle,
                        ),
                      )
                      as Map)
                  .cast<String, Object?>()['mcpServers']
              as Map)
          .cast<String, Object?>(),
    };
    existing['mcpServers'] = mergedServers;

    await _fs.atomicWrite(path, _jsonPretty(existing));
  }

  String _jsonPretty(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);
}
