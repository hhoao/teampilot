import 'provider_presets_part1.dart';
import 'provider_presets_part2.dart';
import 'provider_presets_part3.dart';
import 'provider_presets_part4.dart';
import '../../../models/app_provider_config.dart';

/// Built-in Claude CLI provider presets (CCSwitch catalog).
class ClaudeProviderPresets {
  const ClaudeProviderPresets._();

  static const all = <AppProviderPreset>[
    ...claudeProviderPresetsPart1,
    ...claudeProviderPresetsPart2,
    ...claudeProviderPresetsPart3,
    ...claudeProviderPresetsPart4,
  ];

  static AppProviderPreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
