import '../../../../models/team_config.dart';
import '../../../team_bus/bus_awareness_prompt.dart';

const opencodeAwarenessPluginFileName = 'teampilot-bus-awareness.js';

/// OpenCode has no SessionStart hook. Inject the mixed TeamBus protocol into
/// the system prompt on every LLM request via experimental.chat.system.transform.
const opencodeAwarenessPluginSource = r'''
export const TeampilotBusAwareness = async (input, options) => {
  const prompt = String(options?.prompt ?? "");
  return {
    "experimental.chat.system.transform": async (_input, output) => {
      if (!prompt) return;
      const system = output?.system;
      if (!Array.isArray(system)) return;
      if (system.includes(prompt)) return;
      system.unshift(prompt);
    },
  };
};
''';

/// Merges the TeamBus awareness plugin into opencode.json `plugin`.
Map<String, Object?> mergeOpencodeBusAwarenessPlugin(
  Map<String, Object?> config,
  String prompt,
) {
  final pluginPath = './$opencodeAwarenessPluginFileName';
  final entry = <Object?>[
    pluginPath,
    <String, Object?>{'prompt': prompt},
  ];
  final plugins = List<Object?>.from((config['plugin'] as List?) ?? const [])
    ..removeWhere(
      (e) =>
          (e is String && e == pluginPath) ||
          (e is List && e.isNotEmpty && e[0] == pluginPath),
    );
  plugins.add(entry);
  return {...config, 'plugin': plugins};
}

String opencodeBusAwarenessPrompt({
  required TeamMemberConfig member,
}) => BusAwarenessPrompt.additionalContext(
  member: member,
  pushDelivery: false,
);
