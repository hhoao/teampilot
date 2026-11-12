import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/grok/capabilities/hook_writer.dart';
import 'package:teampilot/services/cli/grok/capabilities/mcp.dart';
import 'package:teampilot/services/cli/grok/capabilities/usage/session_usage.dart';
import 'package:teampilot/services/cli/grok/grok_constants.dart';
import 'package:teampilot/services/cli/grok/provider/grok_auth_store.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';
import 'package:toml/toml.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  group('MCP', () {
    test('merges server tables without clobbering unrelated config', () async {
      final fs = InMemoryFilesystem();
      await fs.atomicWrite(
        '/cfg/config.toml',
        '[models]\ndefault = "grok-4.6"\n\n'
            '[mcp_servers.keep]\ncommand = "keep"\n',
      );

      await const GrokMcpCapability().write(
        fs: fs,
        configDir: '/cfg',
        servers: const [
          StdioMcpServer(
            name: 'bus',
            command: 'npx',
            args: ['teampilot-bus'],
            env: {'TOKEN': 'x'},
          ),
          RemoteMcpServer(name: 'remote', url: 'https://example.test/mcp'),
          RemoteMcpServer(
            name: 'auth',
            url: 'https://example.test/auth',
            bearerTokenEnvVar: 'TOKEN',
          ),
        ],
      );

      final map = TomlDocument.parse(
        (await fs.readString('/cfg/config.toml'))!,
      ).toMap();
      expect((map['models'] as Map)['default'], 'grok-4.6');
      final servers = map['mcp_servers'] as Map;
      expect((servers['keep'] as Map)['command'], 'keep');
      expect((servers['bus'] as Map)['command'], 'npx');
      expect((servers['bus'] as Map)['args'], ['teampilot-bus']);
      expect((servers['remote'] as Map)['url'], 'https://example.test/mcp');
      expect((servers['auth'] as Map)['headers'], {
        'Authorization': r'Bearer ${TOKEN}',
      });
    });
  });

  group('hooks', () {
    test('renders a hooks fragment and uses Grok decision output', () {
      final result = const GrokHookWriter().render(
        entries: [
          HookEntry(
            id: 'h1',
            source: HookSource.userLibrary,
            event: HookEvent.preToolUse,
            matcher: 'Bash',
            action: const CommandHookAction.raw('echo hi'),
            policy: HookPolicy.allow,
          ),
        ],
        ctx: const HookRenderContext(
          hooksDir: '/cfg/hooks',
          runner: null,
          glueBuilder: GlueScriptBuilder(),
        ),
      );

      expect(result.configFragments, {
        'hooks/teampilot.json': {
          'hooks': {
            'PreToolUse': [
              {
                'matcher': 'Bash',
                'hooks': [
                  {
                    'type': 'command',
                    'command': '/cfg/hooks/teampilot-hook-h1.sh',
                    'timeout': 5,
                  },
                ],
              },
            ],
          },
        },
      });
      expect(result.scripts.single.content, contains('{"decision":"allow"}'));
      expect(result.warnings, isEmpty);
    });

    test('maps the supported Grok event names', () {
      const writer = GrokHookWriter();
      expect(writer.nativeEvent(HookEvent.sessionStart), 'SessionStart');
      expect(writer.nativeEvent(HookEvent.preToolUse), 'PreToolUse');
      expect(writer.nativeEvent(HookEvent.postToolUse), 'PostToolUse');
      expect(writer.nativeEvent(HookEvent.subagentStop), 'SubagentStop');
      expect(writer.nativeEvent(HookEvent.permissionRequest), isNull);
    });
  });

  group('auth store', () {
    test(
      'seeds the session copy and respects a session-refreshed token',
      () async {
        final fs = InMemoryFilesystem();
        final store = GrokAuthStore(
          fs: fs,
          basePath: '/tp',
          pathContext: fs.pathContext,
          machineHome: '/home/test',
        );
        await fs.ensureDir('/tp/providers/grok/xai');
        await fs.atomicWrite('/tp/providers/grok/xai/auth.json', 'provider');

        Future<bool> seed() => store.seedSessionAuth(
          providerId: 'xai',
          sessionFs: fs,
          sessionPathContext: fs.pathContext,
          sessionConfigDir: '/session/grok',
        );

        expect(await seed(), isTrue);
        expect(await fs.readString('/session/grok/auth.json'), 'provider');

        // The session refreshes its own token; an unchanged provider store must
        // not overwrite it on reconnect.
        await fs.atomicWrite('/session/grok/auth.json', 'refreshed');
        expect(await seed(), isTrue);
        expect(await fs.readString('/session/grok/auth.json'), 'refreshed');

        // A re-login changes the provider source fingerprint, so the seat is
        // reseeded.
        await fs.atomicWrite('/tp/providers/grok/xai/auth.json', 'relogin');
        expect(await seed(), isTrue);
        expect(await fs.readString('/session/grok/auth.json'), 'relogin');
      },
    );

    test(
      'falls back to the machine login only when no provider row exists',
      () async {
        final fs = InMemoryFilesystem();
        final store = GrokAuthStore(
          fs: fs,
          basePath: '/tp',
          pathContext: fs.pathContext,
          machineHome: '/home/test',
        );
        await fs.ensureDir('/home/test/.grok');
        await fs.atomicWrite('/home/test/.grok/auth.json', 'machine');

        expect(
          await store.seedSessionAuth(
            providerId: 'xai',
            sessionFs: fs,
            sessionPathContext: fs.pathContext,
            sessionConfigDir: '/session/grok',
          ),
          isTrue,
        );
        expect(await fs.readString('/session/grok/auth.json'), 'machine');

        // A provider row that exists without auth must not silently borrow the
        // machine account.
        await fs.ensureDir('/tp/providers/grok/xai');
        await fs.atomicWrite('/session/grok/auth.json', 'old');
        await fs.removeRecursive('/session/grok');
        expect(
          await store.seedSessionAuth(
            providerId: 'xai',
            sessionFs: fs,
            sessionPathContext: fs.pathContext,
            sessionConfigDir: '/session/grok',
          ),
          isFalse,
        );
        expect((await fs.stat('/session/grok/auth.json')).exists, isFalse);
      },
    );
  });

  group('usage', () {
    UsageScanContext ctx() => UsageScanContext(
      fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      cli: CliTool.grok,
      env: const {GrokConstants.homeEnvKey: '/runtime/grok'},
      transcriptRoots: const [],
      taskId: 'task-1',
      nativeSessionId: 'native-1',
      sessionId: 's1',
      memberId: 'dev',
      teamId: 'team1',
      workingDirectory: '/home/me/proj',
      appDataRoot: '/tp',
    );

    test('discovers and scans GROK_HOME/acp-usage.jsonl', () async {
      final context = ctx();
      await context.fs.writeString(
        '/runtime/grok/acp-usage.jsonl',
        '${[
          jsonEncode({'sessionId': 's1', 'used': 0, 'size': 100, 'sequence': 1}),
          jsonEncode({'sessionId': 's1', 'used': 42, 'size': 100, 'sequence': 2000000, 'model': 'grok-4.6'}),
        ].join('\n')}\n',
      );

      const capability = GrokSessionUsageCapability();
      final source = (await capability.discoverUsageSources(context)).single;
      expect(source.kind, UsageSourceKind.jsonl);
      expect(source.path, '/runtime/grok/acp-usage.jsonl');

      final result = await capability.scanUsageSource(
        ctx: context,
        source: source,
        cursor: null,
      );
      expect(result.events, hasLength(1));
      final event = result.events.single;
      expect(event.cli, CliTool.grok);
      expect(event.model, 'grok-4.6');
      expect(event.inputTokens, 42);
      expect(event.inputSemantics, UsageInputSemantics.total);
      expect(event.timestampMs, 2000);
      expect(event.sessionId, 's1');
      expect(event.memberId, 'dev');
      expect(event.teamId, 'team1');
    });

    test('returns no source when the session usage log is absent', () async {
      final context = ctx();
      expect(
        await const GrokSessionUsageCapability().discoverUsageSources(context),
        isEmpty,
      );
    });
  });
}
