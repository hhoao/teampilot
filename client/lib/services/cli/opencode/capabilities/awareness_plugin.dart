import '../../../../models/team_config.dart';
import '../../../chat/team_bus/bus_awareness_prompt.dart';
import '../opencode_config.dart';

const opencodeAwarenessPluginFileName = 'teampilot-bus-awareness.js';

/// OpenCode has no SessionStart hook. Inject the mixed TeamBus protocol into
/// the system prompt on every LLM request via the v2 `context` session hook.
const opencodeAwarenessPluginSource = r'''
import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "teampilot.bus-awareness",
  async setup(ctx) {
    const prompt = String(ctx.options?.prompt ?? "");
    if (!prompt) return;
    await ctx.session.hook("context", (event) => {
      const system = event?.system;
      if (!Array.isArray(system)) return;
      if (system.includes(prompt)) return;
      system.unshift(prompt);
    });
  },
});
''';

/// Merges the TeamBus awareness plugin into opencode.json `plugins`.
Map<String, Object?> mergeOpencodeBusAwarenessPlugin(
  Map<String, Object?> config,
  String prompt,
) {
  return mergeOpencodePluginEntries(config, [
    opencodePluginObject(
      package: './$opencodeAwarenessPluginFileName',
      options: <String, Object?>{'prompt': prompt},
    ),
  ]);
}

String opencodeBusAwarenessPrompt({required TeamMemberConfig member}) =>
    BusAwarenessPrompt.additionalContext(member: member, pushDelivery: false);
