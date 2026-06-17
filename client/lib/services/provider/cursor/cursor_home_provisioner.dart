import 'dart:convert';

import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../../session/member_role_provision.dart';
import 'cursor_cli_config_policy.dart';
import 'cursor_home_bus_overlay.dart';
import 'cursor_home_layout.dart';
import 'cursor_provider_credentials_service.dart';

/// Merges provider auth and mixed-mode team-bus overlay into a member fake HOME.
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
    required int? busPort,
    required bool forceTeamLeadDelegateMode,
    required bool mixed,
  }) async {
    await _ensureCursorDirs(memberHome);

    final id = providerId?.trim();
    if (id != null && id.isNotEmpty) {
      await _credentials?.syncAuthToMemberHome(id, memberHome);
    }

    if (!mixed || !member.isValid) return;

    await _mergeTeamBusPermissions(memberHome);

    if (busPort == null) return;

    await _writeBusOverlay(
      memberHome: memberHome,
      member: member,
      port: busPort,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
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

  Future<void> _mergeTeamBusPermissions(String memberHome) async {
    final path = _layout.cliConfig(memberHome);
    final raw = await _fs.readString(path);
    final existing = raw != null
        ? CursorCliConfigPolicy.parseConfigJson(raw)
        : null;
    final merged = CursorCliConfigPolicy.applyMixedTeamSessionPolicy(
      existing ?? const {},
    );
    await _fs.atomicWrite(path, _jsonPretty(merged));
  }

  Future<void> _writeBusOverlay({
    required String memberHome,
    required TeamMemberConfig member,
    required int port,
    required bool forceTeamLeadDelegateMode,
  }) async {
    final idleScriptPath = _layout.idleScript(memberHome);

    final rolePrompt = MemberRoleProvision.composeRolePrompt(
      member: member,
      forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
      mixed: true,
      // cursor 的 MCP 工具调用 ~60s 硬限 → 不能阻塞在 wait_for_message；走门铃 push。
      pushDelivery: true,
    ).trim();

    await _fs.atomicWrite(
      _layout.roleRule(memberHome),
      CursorHomeBusOverlay.roleRule(rolePrompt),
    );
    await _fs.atomicWrite(
      idleScriptPath,
      CursorHomeBusOverlay.idleScript(memberId: member.id, port: port),
    );
    await _fs.atomicWrite(
      _layout.hooksConfig(memberHome),
      _jsonPretty(
        CursorHomeBusOverlay.hooksConfig(idleScriptPath: idleScriptPath),
      ),
    );
    await _fs.atomicWrite(
      _layout.mcpConfig(memberHome),
      CursorHomeBusOverlay.buildMcpJson(memberId: member.id, port: port),
    );
  }

  static String _jsonPretty(Map<String, Object?> value) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  }
}
