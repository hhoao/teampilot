import 'dart:convert';

import '../../../../models/team_config.dart';
import '../../../session/member_role_provision.dart';
import '../capabilities/config_profile_capability.dart';
import 'cursor_team_bus_plugin.dart';

/// Cursor CLI launch profile.
///
/// Isolates per-session config/auth/permissions under a dedicated
/// `$CURSOR_CONFIG_DIR` (auth itself is global/keychain, shared across config
/// dirs, so members reuse the same Cursor login without re-authenticating).
///
/// In **mixed mode** also provisions a per-member plugin (passed to the CLI via
/// `--plugin-dir`, relayed through [pluginDirEnvKey]) that carries the
/// teammate-bus MCP server, the idle stop hook, and the member's role rule —
/// because Cursor does not read hooks/rules/MCP from `$CURSOR_CONFIG_DIR`.
final class CursorConfigProfileCapability implements ConfigProfileCapability {
  const CursorConfigProfileCapability();

  static const toolId = 'cursor';

  /// Launch-only env key relaying the per-member plugin dir to the adapter
  /// (stripped before the PTY spawns; see `LaunchCommandBuilder`).
  static const pluginDirEnvKey = 'TEAMPILOT_CURSOR_PLUGIN_DIR';

  static const _pluginDirName = 'teampilot-bus-plugin';

  @override
  Future<void> ensureSessionProfile(ConfigProfileSessionContext ctx) async {}

  @override
  Future<ConfigProfileLaunchContribution> contributeLaunch(
    ConfigProfileLaunchContext ctx,
  ) async {
    final paths = ctx.paths;
    final cursorDir = paths.sessionToolDir(
      ctx.scope.teamId,
      ctx.scope.sessionId,
      toolId,
    );
    await paths.fs.ensureDir(cursorDir);

    final environment = <String, String>{'CURSOR_CONFIG_DIR': cursorDir};
    final warnings = <String>[];

    final mixed = ctx.team?.teamMode == TeamMode.mixed;
    final member = ctx.member;
    final port = CursorTeamBusPlugin.parseBusPort(ctx.busIdleUrl);
    if (mixed && member != null && member.isValid) {
      if (port == null) {
        warnings.add('cursor_bus_idle_url_missing');
      } else {
        final pluginDir = await _provisionBusPlugin(
          ctx: ctx,
          cursorDir: cursorDir,
          member: member,
          port: port,
        );
        environment[pluginDirEnvKey] = pluginDir;
      }
    }

    return ConfigProfileLaunchContribution(
      environment: environment,
      warnings: warnings,
    );
  }

  Future<String> _provisionBusPlugin({
    required ConfigProfileLaunchContext ctx,
    required String cursorDir,
    required TeamMemberConfig member,
    required int port,
  }) async {
    final fs = ctx.paths.fs;
    final join = ctx.paths.pathContext.join;
    final pluginDir = join(cursorDir, _pluginDirName);

    final idleScriptPath = join(
      pluginDir,
      CursorTeamBusPlugin.hooksDirName,
      CursorTeamBusPlugin.idleScriptFileName,
    );

    await fs.atomicWrite(
      join(
        pluginDir,
        CursorTeamBusPlugin.manifestDirName,
        CursorTeamBusPlugin.manifestFileName,
      ),
      _jsonPretty(
        CursorTeamBusPlugin.manifest(memberId: member.id, port: port),
      ),
    );
    await fs.atomicWrite(
      idleScriptPath,
      CursorTeamBusPlugin.idleScript(memberId: member.id, port: port),
    );
    await fs.atomicWrite(
      join(
        pluginDir,
        CursorTeamBusPlugin.hooksDirName,
        CursorTeamBusPlugin.hooksFileName,
      ),
      _jsonPretty(
        CursorTeamBusPlugin.hooksConfig(idleScriptPath: idleScriptPath),
      ),
    );

    final rolePrompt = MemberRoleProvision.composeRolePrompt(
      member: member,
      forceTeamLeadDelegateMode: ctx.team?.forceTeamLeadDelegateMode ?? false,
      mixed: true,
    ).trim();
    await fs.atomicWrite(
      join(
        pluginDir,
        CursorTeamBusPlugin.rulesDirName,
        CursorTeamBusPlugin.roleRuleFileName,
      ),
      _roleRule(rolePrompt),
    );

    return pluginDir;
  }

  /// Wraps the composed role prompt as an always-apply Cursor rule (`.mdc`).
  static String _roleRule(String body) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('alwaysApply: true')
      ..writeln('---')
      ..writeln();
    if (body.isNotEmpty) buffer.writeln(body);
    return buffer.toString();
  }

  static String _jsonPretty(Map<String, Object?> value) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  }
}
