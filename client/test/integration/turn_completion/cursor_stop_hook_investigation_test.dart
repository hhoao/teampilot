import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_layout.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_home_provisioner.dart';
import 'package:teampilot/services/cli/registry/capabilities/runtime_event_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../support/in_memory_filesystem.dart';

/// Investigative: does simple-mode cursor actually install a `stop`
/// agent-status hook, and does the generated script POST to
/// `/agent-status?event=Stop`?
///
/// Finding (2026-08-09): yes — simple-mode provision writes `~/.cursor/hooks.json`
/// with a `stop` entry whose script POSTs `/agent-status?event=Stop`. So the
/// `stop`→done path is wired; the unreliability in interactive mode is that
/// cursor-agent does not emit the `stop` hook per conversation turn (it only
/// fires when the agent loop ends, which an interactive composer session keeps
/// open). The PTY-quiet fallback (ChatCubit._onTurnEnded) therefore remains
/// the reliable simple-mode path, and the declared `requiresPtyFallback=true`
/// stays correct.
///
/// Converged (2026-08-13): hooks are assembled through
/// [HookSeatContextCompleter] + the unified writer (`writeHooks`); the query
/// event name follows Cursor's native lower-camel identity.
void main() {
  test('simple cursor provision writes a stop agent-status hook script', () async {
    final fs = InMemoryFilesystem();
    final layout = CursorHomeLayout(pathContext: fs.pathContext);
    const memberHome = '/home/cur';
    const member = TeamMemberConfig(id: 'solo', name: 'Solo');
    const endpoint = MemberAgentStatusEndpoint(
      url: 'http://127.0.0.1:4321/agent-status',
    );

    await CursorHomeProvisioner(fs: fs, layout: layout).writeHooks(
      memberHome: memberHome,
      entries: CliToolRegistry.builtIn()
          .capability<RuntimeEventCapability>(CliTool.cursor)!
          .managedHookEntries(
            RuntimeEventHookContext(endpoint: endpoint, memberId: member.id),
          ),
      runner: null,
    );

    // hooks.json written under ~/.cursor/hooks.json and contains a `stop` entry.
    final hooksRaw = await fs.readString(layout.hooksConfig(memberHome));
    expect(
      hooksRaw,
      isNotNull,
      reason: 'hooks.json must be written in simple mode',
    );
    final hooks = _decode(hooksRaw!);
    final stopEntries =
        (hooks['hooks'] as Map?)?.cast<String, Object?>()['stop'] as List?;
    expect(stopEntries, isNotNull, reason: 'stop hook must be registered');
    final stopCommand =
        ((stopEntries!.first as Map)['command'] as String?) ?? '';
    expect(
      stopCommand,
      startsWith('bash '),
      reason: 'stop hook runs the forwarding script',
    );

    // The script file exists and POSTs to the /agent-status URL with event=stop.
    final scriptFile = stopCommand
        .replaceFirst("bash '", '')
        .replaceFirst("'", '')
        .trim();
    final script = await fs.readString(scriptFile);
    expect(script, isNotNull, reason: 'stop forwarding script must exist');
    expect(
      script,
      contains('event=stop'),
      reason: 'script targets /agent-status?event=stop',
    );
    expect(
      script,
      contains('127.0.0.1:4321/agent-status'),
      reason: 'script POSTs the endpoint',
    );
  });
}

Map<String, Object?> _decode(String raw) {
  // Minimal JSON decode via dart:convert.
  return (const JsonDecoder().convert(raw) as Map).cast<String, Object?>();
}
