/// Upstream facts about the OpenCode Go layer.
///
/// OpenCode Go and the free Zen layer are **separate upstream providers**: the
/// Go plan is reached through `zen/go/v1` with its own auth entry, while Zen is
/// the built-in `opencode` provider. TeamPilot still keeps them as one catalog
/// row named "OpenCode"; this file is the single place that knows how the paid
/// layer is addressed, so the config writer and the presets cannot drift.
abstract final class OpencodeGoLayer {
  OpencodeGoLayer._();

  /// `opencode.json` provider key / `model` prefix for the paid layer.
  static const namespace = 'opencode-go';

  static const baseUrl = 'https://opencode.ai/zen/go/v1';

  static const npm = '@ai-sdk/openai-compatible';

  static const apiKeyUrl = 'https://opencode.ai/console/go';

  static bool isNamespace(String id) => id.trim() == namespace;
}
