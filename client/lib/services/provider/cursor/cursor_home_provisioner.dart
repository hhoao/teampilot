import 'dart:convert';

import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../../team_bus/member_bus_idle_endpoint.dart';
import 'cursor_cli_config_policy.dart';
import 'cursor_home_bus_overlay.dart';
import 'cursor_home_layout.dart';
import 'cursor_member_home_passthrough.dart';
import 'cursor_provider_credentials_service.dart';
import 'cursor_role_rule_writer.dart';

/// Merges provider auth, role rule, and mixed-mode team-bus overlay into a
/// member fake HOME.
final class CursorHomeProvisioner {
  CursorHomeProvisioner({
    required Filesystem fs,
    CursorHomeLayout? layout,
    CursorProviderCredentialsService? credentials,
  }) : _fs = fs,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext),
       _credentials = credentials;

  final Filesystem _fs;
  final CursorHomeLayout _layout;
  final CursorProviderCredentialsService? _credentials;

  Future<void> provision({
    required String memberHome,
    required String? providerId,
    required TeamMemberConfig member,
    required MemberBusIdleEndpoint? busIdle,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
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

    if (!member.isValid) return;

    if (!mixed) {
      await _syncRoleRule(
        memberHome: memberHome,
        member: member,
        forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
        mixed: false,
        pushDelivery: false,
      );
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
    await _mergeTeamBusPermissions(
      memberHome,
      cliConfigJson: cliConfigJson,
    );
    await _syncRoleRule(
      memberHome: memberHome,
      member: member,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: true,
      pushDelivery: true,
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

  Future<void> _syncRoleRule({
    required String memberHome,
    required TeamMemberConfig member,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
    required bool pushDelivery,
  }) {
    return CursorRoleRuleWriter(fs: _fs, layout: _layout).sync(
      memberHome: memberHome,
      member: member,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: mixed,
      pushDelivery: pushDelivery,
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
    await _fs.atomicWrite(
      _layout.hooksConfig(memberHome),
      _jsonPretty(
        CursorHomeBusOverlay.hooksConfig(idleScriptPath: idleScriptPath),
      ),
    );
    await _mergeTeamBusMcp(
      memberHome: memberHome,
      memberId: member.id,
      busIdle: busIdle,
    );
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
