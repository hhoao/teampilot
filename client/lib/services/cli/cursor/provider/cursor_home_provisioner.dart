import 'dart:convert';

import '../../../../models/team_config.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import '../../../io/filesystem.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../capabilities/prompt_provision.dart';
import 'cursor_auth_artifacts.dart';
import 'cursor_cli_config_policy.dart';
import 'cursor_home_agent_status_overlay.dart';
import 'cursor_home_bus_overlay.dart';
import 'cursor_home_layout.dart';
import 'cursor_member_home_passthrough.dart';
import 'cursor_provider_credentials_service.dart';

/// Merges provider auth, role rule, and mixed-mode team-bus overlay into a
/// member fake HOME.
final class CursorHomeProvisioner {
  CursorHomeProvisioner({
    required Filesystem fs,
    CursorHomeLayout? layout,
    CursorProviderCredentialsService? credentials,
    PromptProvisionCapability? promptProvision,
  }) : _fs = fs,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext),
       _credentials = credentials,
       _promptProvision =
           promptProvision ??
           CursorPromptProvisionCapability(
             fs: fs,
             layout: layout ?? CursorHomeLayout(pathContext: fs.pathContext),
           );

  final Filesystem _fs;
  final CursorHomeLayout _layout;
  final CursorProviderCredentialsService? _credentials;
  final PromptProvisionCapability _promptProvision;

  Future<void> provision({
    required String memberHome,
    required String? providerId,
    required TeamMemberConfig member,
    required MemberBusIdleEndpoint? busIdle,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    MemberAgentStatusEndpoint? agentStatus,
    String? realHomeRoot,
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

    if (!mixed) {
      await _promptProvision.provision(
        PromptProvisionContext(
          member: member,
          memberHome: memberHome,
          forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
          mixed: false,
          pushDelivery: false,
        ),
      );
      if (agentStatus != null) {
        await writeAgentStatusHooks(
          memberHome: memberHome,
          memberId: member.id,
          agentStatus: agentStatus,
        );
      }
      return;
    }

    await provisionOverlayOnly(
      memberHome: memberHome,
      member: member,
      busIdle: busIdle,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
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
  }) async {
    if (!member.isValid) return;

    await _ensureOverlayDirs(memberHome);
    await _ensureAgentCommandTipSuppressed(memberHome);
    await _mergeTeamBusPermissions(
      memberHome,
      cliConfigJson: cliConfigJson,
    );
    await _promptProvision.provision(
      PromptProvisionContext(
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
    await CursorMemberHomePassthrough(fs: _fs, layout: _layout).mirror(
      realHomeRoot: realHome,
      memberHomeRoot: memberHome,
    );
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
    Map<String, Object?>? existing;
    if (cliConfigJson != null) {
      existing = CursorCliConfigPolicy.parseConfigJson(cliConfigJson);
    } else {
      final raw = await _fs.readString(path);
      existing = raw != null
          ? CursorCliConfigPolicy.parseConfigJson(raw)
          : null;
    }
    final merged = CursorCliConfigPolicy.applyMixedTeamSessionPolicy(
      existing ?? const {},
    );
    await _fs.atomicWrite(path, _jsonPretty(merged));
  }

  Future<void> _writeBusOverlay({
    required String memberHome,
    required TeamMemberConfig member,
    required MemberBusIdleEndpoint busIdle,
  }) async {
    final idleScriptPath = _layout.idleScript(memberHome);

    await _fs.atomicWrite(
      idleScriptPath,
      CursorHomeBusOverlay.idleScript(memberId: member.id, idle: busIdle),
    );
    final hooksPath = _layout.hooksConfig(memberHome);
    final raw = await _fs.readString(hooksPath);
    Map<String, Object?> existing;
    if (raw != null && raw.trim().isNotEmpty) {
      existing = (jsonDecode(raw) as Map).cast<String, Object?>();
    } else {
      existing = <String, Object?>{};
    }
    await _fs.atomicWrite(
      hooksPath,
      _jsonPretty(
        CursorHomeBusOverlay.mergeHooksConfig(
          existing,
          idleScriptPath: idleScriptPath,
        ),
      ),
    );
    await _mergeTeamBusMcp(
      memberHome: memberHome,
      memberId: member.id,
      busIdle: busIdle,
    );
  }

  /// Writes per-event forwarding scripts and merges agent-status hooks into
  /// `~/.cursor/hooks.json` (preserving the bus `stop` hook when present).
  ///
  /// Public so the config-profile phase can provision hooks into an
  /// already-resolved mixed-mode member home.
  Future<void> writeAgentStatusHooks({
    required String memberHome,
    required String memberId,
    required MemberAgentStatusEndpoint agentStatus,
  }) async {
    for (final event in CursorHomeAgentStatusOverlay.statusEvents) {
      final fileName = CursorHomeAgentStatusOverlay.scriptFileName(event);
      await _fs.atomicWrite(
        _layout.agentStatusScript(memberHome, fileName),
        CursorHomeAgentStatusOverlay.scriptFor(
          endpoint: agentStatus,
          memberId: memberId,
          event: event,
        ),
      );
    }

    final hooksPath = _layout.hooksConfig(memberHome);
    final raw = await _fs.readString(hooksPath);
    Map<String, Object?> existing;
    if (raw != null && raw.trim().isNotEmpty) {
      existing = (jsonDecode(raw) as Map).cast<String, Object?>();
    } else {
      existing = <String, Object?>{};
    }
    final merged = CursorHomeAgentStatusOverlay.mergeHooksConfig(
      existing,
      scriptPathFor: (event) => _layout.agentStatusScript(
        memberHome,
        CursorHomeAgentStatusOverlay.scriptFileName(event),
      ),
    );
    await _fs.atomicWrite(hooksPath, _jsonPretty(merged));
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
