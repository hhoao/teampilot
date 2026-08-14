import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_registry.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/hook/glue_script_builder.dart';

class _FakeWriter implements HookCapability {
  const _FakeWriter();
  @override
  String? nativeEvent(HookEvent event) =>
      event == HookEvent.stop ? 'Stop' : null;
  @override
  bool supportsEvent(HookEvent event) => nativeEvent(event) != null;
  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => false;
  @override
  bool get supportsPolicy => true;
  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    final warnings = <String>[];
    for (final entry in entries) {
      if (nativeEvent(entry.event) == null) {
        warnings.add('unsupported_${entry.id}');
      }
    }
    return HookWriteResult(
      configFragments: const {'config': {'hooks': []}},
      scripts: const [
        GeneratedScript(fileName: 'a.sh', content: 'echo hi'),
      ],
      warnings: warnings,
    );
  }
}

void main() {
  const writer = _FakeWriter();

  test('supportsEvent reflects nativeEvent', () {
    expect(writer.supportsEvent(HookEvent.stop), isTrue);
    expect(writer.supportsEvent(HookEvent.preToolUse), isFalse);
  });

  test('render is a pure function returning fragments and scripts', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(
      entries: const [entry],
      ctx: const HookRenderContext(
        hooksDir: '/x/hooks',
        runner: null,
        glueBuilder: GlueScriptBuilder(),
      ),
    );
    expect(result.configFragments['config'], {'hooks': []});
    expect(result.scripts.single.fileName, 'a.sh');
    expect(result.warnings, isEmpty);
  });

  test('unsupported events produce warnings', () {
    const entry = HookEntry(
      id: 'h1',
      source: HookSource.userLibrary,
      event: HookEvent.preToolUse,
      action: CommandHookAction.raw('echo hi'),
    );
    final result = writer.render(
      entries: const [entry],
      ctx: const HookRenderContext(
        hooksDir: '/x/hooks',
        runner: null,
        glueBuilder: GlueScriptBuilder(),
      ),
    );
    expect(result.warnings, ['unsupported_h1']);
  });
}
