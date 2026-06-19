import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../cli_capability.dart';

/// Where effort is configured in TeamPilot UI.
enum EffortPickerPlacement {
  hidden,
  team,
  member,
  provider,
}

/// Inputs for catalog filtering and launch resolution.
class EffortResolveContext {
  const EffortResolveContext({
    this.team,
    this.member,
    this.provider,
    this.model = '',
  });

  final TeamProfile? team;
  final TeamMemberConfig? member;
  final AppProviderConfig? provider;
  final String model;
}

/// Per-CLI reasoning effort / effortLevel support (Claude `effortLevel`, Codex
/// `model_reasoning_effort`, …).
abstract interface class CliEffortCapability implements CliCapability {
  EffortPickerPlacement teamPickerPlacement();

  EffortPickerPlacement memberPickerPlacement({
    AppProviderConfig? provider,
  });

  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider);

  bool isApplicable({required String model});

  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  });

  String defaultEffort({
    required String model,
    AppProviderConfig? provider,
  });
}

String resolveContextModel(EffortResolveContext context) {
  final explicit = context.model.trim();
  if (explicit.isNotEmpty) return explicit;
  final memberModel = context.member?.model.trim() ?? '';
  if (memberModel.isNotEmpty) return memberModel;
  return context.provider?.defaultModel.trim() ?? '';
}

/// Launch precedence: member → team → provider config → capability default.
String resolveLaunchEffort({
  required CliEffortCapability capability,
  required CliTool cli,
  required EffortResolveContext context,
}) {
  final model = resolveContextModel(context);
  if (!capability.isApplicable(model: model)) return '';

  final memberEffort = context.member?.effort.trim() ?? '';
  if (memberEffort.isNotEmpty &&
      capability.memberPickerPlacement(provider: context.provider) !=
          EffortPickerPlacement.hidden) {
    return memberEffort;
  }

  final teamEffort = context.team?.effortForCli(cli).trim() ?? '';
  if (teamEffort.isNotEmpty &&
      capability.teamPickerPlacement() != EffortPickerPlacement.hidden) {
    return teamEffort;
  }

  final provider = context.provider;
  final providerEffort = _providerConfiguredEffort(provider);
  if (provider != null &&
      providerEffort.isNotEmpty &&
      capability.providerPickerPlacement(provider) !=
          EffortPickerPlacement.hidden) {
    return providerEffort;
  }

  return capability.defaultEffort(model: model, provider: context.provider);
}

String _providerConfiguredEffort(AppProviderConfig? provider) {
  if (provider == null) return '';
  final fromConfig = provider.config['model_reasoning_effort']?.toString().trim();
  if (fromConfig != null && fromConfig.isNotEmpty) return fromConfig;
  final reasoningEffort =
      provider.config['reasoningEffort']?.toString().trim();
  if (reasoningEffort != null && reasoningEffort.isNotEmpty) {
    return reasoningEffort;
  }
  final effort = provider.config['effort']?.toString().trim();
  if (effort != null && effort.isNotEmpty) return effort;
  return '';
}
