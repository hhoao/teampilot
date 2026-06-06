import 'package:flutter/material.dart';

import '../../../../models/app_provider_config.dart';
import '../../../../models/project_profile.dart';
import '../../../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../../../services/cli/registry/cli_tool_registry.dart';
import '../../../../services/provider/claude/claude_official_provider.dart';
import '../../../../utils/app_provider_model_candidates.dart';

bool projectCliSupportsProviderCatalog(
  CliTool cli,
  CliToolRegistry registry,
) =>
    registry.capability<ProviderCatalogCapability>(cli) != null;

String projectCliProviderId(ProjectProfile profile, CliTool cli) {
  final fromMap = profile.providerIdsByTool[cli.value]?.trim() ?? '';
  if (fromMap.isNotEmpty) return fromMap;
  if (profile.cli == cli) return profile.agent.provider.trim();
  return '';
}

String projectCliModelId(ProjectProfile profile, CliTool cli) {
  final fromMap = profile.modelsByTool[cli.value]?.trim() ?? '';
  if (fromMap.isNotEmpty) return fromMap;
  if (profile.cli == cli) return profile.agent.model.trim();
  return '';
}

bool projectCliIsConfigured(
  ProjectProfile profile,
  CliTool cli, {
  AppProviderConfig? selectedProvider,
  bool supportsProviderCatalog = true,
}) {
  if (!supportsProviderCatalog) return true;
  final providerId = projectCliProviderId(profile, cli);
  if (providerId.isEmpty) return false;
  if (selectedProvider != null && isOfficialClaudeProvider(selectedProvider)) {
    return true;
  }
  return projectCliModelId(profile, cli).isNotEmpty;
}

AppProviderConfig? projectCliSelectedProvider(
  ProjectProfile profile,
  CliTool cli,
  Iterable<AppProviderConfig> providers,
) {
  final id = projectCliProviderId(profile, cli);
  if (id.isEmpty) return null;
  for (final provider in providers) {
    if (provider.id == id) return provider;
  }
  return null;
}

List<String> projectCliModelCandidates({
  required AppProviderConfig? appProvider,
  required String currentModel,
}) {
  if (appProvider == null) {
    final trimmed = currentModel.trim();
    return trimmed.isEmpty ? <String>[] : [trimmed];
  }
  return collectClaudeModelCandidates(
    appProvider,
    currentModel: currentModel,
  );
}

/// Default model when the user picks a different provider in the configure dialog.
String projectCliDefaultModelForProvider(AppProviderConfig? provider) {
  if (provider == null) return '';
  if (isOfficialClaudeProvider(provider)) return '';
  final defaultModel = provider.defaultModel.trim();
  if (defaultModel.isNotEmpty) return defaultModel;
  final names = projectCliModelCandidates(
    appProvider: provider,
    currentModel: '',
  );
  return names.isNotEmpty ? names.first : '';
}

IconData cliToolIcon(CliTool cli) => switch (cli) {
  CliTool.flashskyai => Icons.bolt_outlined,
  CliTool.claude => Icons.terminal_outlined,
  CliTool.codex => Icons.integration_instructions_outlined,
  CliTool.opencode => Icons.code_outlined,
  CliTool.cursor => Icons.mouse_outlined,
};
