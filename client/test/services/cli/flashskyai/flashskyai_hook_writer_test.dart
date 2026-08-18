import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

void main() {
  const writer = FlashskyaiHookWriter();
  const context = HookRenderContext(
    hooksDir: '/runtime/flashskyai/hooks',
    runner: null,
    glueBuilder: GlueScriptBuilder(),
  );

  test('FlashskyAI registry uses its target-specific hook capability', () {
    expect(
      CliToolRegistry.builtIn().capability<HookCapability>(CliTool.flashskyai),
      isA<FlashskyaiHookWriter>(),
    );
  });

  test('materializes neutral bus idle as command exit-2 hook output', () {
    const entry = HookEntry(
      id: 'teampilot-bus-idle-stop',
      source: HookSource.managed,
      event: HookEvent.stop,
      action: HttpHookAction(
        url: 'http://127.0.0.1:54321/idle',
        headers: {'X-Teampilot-Member': 'm1'},
      ),
      timeout: Duration(seconds: 5),
      blockOnDecision: true,
    );

    final result = writer.render(entries: const [entry], ctx: context);

    expect(result.scripts.single.fileName, 'teammate-bus-stop-idle.sh');
    expect(result.scripts.single.content, contains('exit 2'));
    final settings = result.configFragments['settings.json']! as Map;
    final stop = settings['hooks'] as Map;
    final hooks = (stop['Stop'] as List).single as Map;
    final hook = (hooks['hooks'] as List).single as Map;
    expect(hook['type'], 'command');
    expect(hook['command'], contains('teammate-bus-stop-idle.sh'));
  });

  test('does not route flashskyai bus idle through Claude HTTP rendering', () {
    const entry = HookEntry(
      id: 'teampilot-bus-idle-stop',
      source: HookSource.managed,
      event: HookEvent.stop,
      action: HttpHookAction(url: 'http://127.0.0.1:54321/idle'),
      blockOnDecision: true,
    );

    final result = writer.render(entries: const [entry], ctx: context);
    final settings = result.configFragments['settings.json']! as Map;
    final hooks = (settings['hooks'] as Map)['Stop'] as List;
    expect([
      for (final group in hooks)
        for (final hook in (group as Map)['hooks'] as List)
          if ((hook as Map)['type'] == 'http') hook,
    ], isEmpty);
  });
}
