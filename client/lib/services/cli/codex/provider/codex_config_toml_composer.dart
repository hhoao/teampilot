import '../../../../models/app_provider_config.dart';
import 'codex_context_window_toml.dart';
import 'codex_effort_toml.dart';
import 'codex_project_trust_toml.dart';
import 'codex_team_bus_overlay.dart';
import '../../../provider/tool_config_generator.dart';

/// Builds the effective `config.toml` body for a Codex session `CODEX_HOME`.
final class CodexConfigTomlComposer {
  const CodexConfigTomlComposer({ToolConfigGenerator? generator})
    : _generator = generator ?? const ToolConfigGenerator();

  final ToolConfigGenerator _generator;

  String compose({
    required AppProviderConfig provider,
    String? busOverlayToml,
    Iterable<String> trustedProjectDirectories = const [],
    String? reasoningEffortOverride,
    int? contextWindowOverride,
    bool usesPosixPaths = false,
  }) {
    var base = _generator.buildCodexConfigToml(provider).trim();
    final effortOverride = reasoningEffortOverride?.trim() ?? '';
    if (effortOverride.isNotEmpty) {
      base = CodexEffortToml.applyReasoningEffort(base, effortOverride);
    }
    if (contextWindowOverride != null) {
      base = CodexContextWindowToml.applyContextWindow(
        base,
        contextWindowOverride,
      );
    }
    final overlay = busOverlayToml?.trim() ?? '';
    final withOverlay = overlay.isEmpty
        ? base
        : base.isEmpty
        ? overlay
        : CodexTeamBusOverlay.containsOverlay(base)
        ? base
        : '$base\n\n$overlay';
    return CodexProjectTrustToml.applyTrustedDirectories(
      withOverlay,
      trustedProjectDirectories,
      usesPosixPaths: usesPosixPaths,
    );
  }
}
