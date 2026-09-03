import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/ai_feature_settings_cubit.dart';
import '../../../cubits/app_provider_cubit.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../models/landing_launch_context.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/ai_feature_setting.dart';
import '../../../models/simple_launch_identity.dart';
import '../../../models/workspace.dart';
import '../../../services/ai/ai_feature_setting_resolver.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/team_generation/team_generation_coordinator.dart';
import '../../../utils/logging/logger.dart';

/// Generation-mode landing submit: preflight → create job → open the visible
/// purpose-tagged builder session.
///
/// Returns true when the builder opened (the landing input clears only then;
/// on preflight failure the text is preserved and the localized error shows).
Future<bool> submitWorkspaceLandingGeneration(
  BuildContext context,
  Workspace workspace, {
  required LandingLaunchContext launch,
  required String message,
  String? workingDirectory,
}) async {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return false;

  final coordinator = context.read<TeamGenerationCoordinator?>();
  if (coordinator == null) {
    appLogger.w(
      '[team-generation] landing submit rejected: coordinator not wired',
    );
    context.read<ChatCubit>().failSessionConnect(
      'pending',
      AppLocalizations.of(context).teamGenerateErrorUnavailable,
    );
    return false;
  }

  final generatorSetting = context
      .read<AiFeatureSettingsCubit>()
      .state
      .settingFor(AiFeatureId.teamGenerate);
  final appProviders = context.read<AppProviderCubit>().state;
  final registry = CliToolRegistryScope.of(context);
  final presets = context.read<CliPresetsCubit>().state.presets;
  final generatorConfigured = aiFeatureIsConfigured(
    stored: generatorSetting,
    registry: registry,
    appProviders: appProviders,
    globalPresets: presets,
  );
  final resolvedGenerator = generatorConfigured
      ? resolveAiFeatureSetting(
          stored: generatorSetting,
          appProviders: appProviders,
          registry: registry,
          globalPresets: presets,
        )
      : null;
  final preflight = await coordinator.preflight(
    workspace: workspace,
    originalPrompt: trimmed,
    generatorCli: resolvedGenerator?.cli,
  );
  if (preflight.issues.isNotEmpty) {
    if (context.mounted) {
      showWorkspaceLandingGenerationPreflight(context, preflight.issues);
    }
    return false;
  }

  final generatorIdentity = SimpleLaunchIdentity.resolve(
    cli: resolvedGenerator!.cli,
    provider: resolvedGenerator.providerId,
    model: resolvedGenerator.model,
    effort: resolvedGenerator.effort,
    expertKey: 'teampilot/builtin/team-builder',
    presetId: resolvedGenerator.activePresetId,
  );

  try {
    final result = await coordinator.start(
      workspace: workspace,
      originalPrompt: trimmed,
      generatorIdentity: generatorIdentity,
      projectFolderPath: launch.projectFolderPath ?? workspace.firstFolderPath,
      workingDirectoryPath:
          workingDirectory ??
          launch.workingDirectoryPath ??
          workspace.firstFolderPath,
      folderIds: [for (final f in workspace.folders) f.path],
      targetIds: [for (final f in workspace.folders) f.targetId],
    );
    if (context.mounted) {
      context.read<WorkbenchCubit>().openSession(
        workspace.workspaceId,
        result.builderSessionId,
      );
    }
    return true;
  } on Object catch (error, stackTrace) {
    ChatCubit? chatCubit;
    String? userMessage;
    if (context.mounted) {
      chatCubit = context.read<ChatCubit>();
      userMessage = AppLocalizations.of(context).teamGenerateErrorStartFailed;
    }
    reportTeamGenerationStartFailure(
      chatCubit: chatCubit,
      userMessage: userMessage,
      sessionId: error is TeamGenerationStartException
          ? error.builderSessionId
          : 'pending',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}

typedef TeamGenerationDiagnosticLogger =
    void Function(Object error, StackTrace stackTrace);

void reportTeamGenerationStartFailure({
  required ChatCubit? chatCubit,
  required String? userMessage,
  String sessionId = 'pending',
  required Object error,
  required StackTrace stackTrace,
  TeamGenerationDiagnosticLogger? diagnosticLogger,
}) {
  (diagnosticLogger ?? _logTeamGenerationStartFailure)(error, stackTrace);
  if (chatCubit == null || userMessage == null) return;
  chatCubit.failSessionConnect(sessionId, userMessage);
}

void _logTeamGenerationStartFailure(Object error, StackTrace stackTrace) {
  appLogger.e(
    '[team-generation] landing start failed',
    error: error,
    stackTrace: stackTrace,
  );
}

/// Localized preflight surface shown above the landing input on issues.
void showWorkspaceLandingGenerationPreflight(
  BuildContext context,
  List<TeamGenerationPreflightIssue> issues,
) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        issues
            .map(
              (issue) => teamGenerationPreflightIssueMessage(
                AppLocalizations.of(context),
                issue.code,
              ),
            )
            .join('\n'),
      ),
    ),
  );
}

String teamGenerationPreflightIssueMessage(
  AppLocalizations l10n,
  String code,
) => switch (code) {
  'description_required' => l10n.teamGenerateErrorDescriptionRequired,
  'generator_not_configured' => l10n.teamGenerateErrorAiNotConfigured,
  'model_pool_empty' => l10n.teamGenerateErrorPoolEmpty,
  'generator_launch_unsupported' ||
  'generator_session_unsupported' ||
  'generator_skill_unsupported' ||
  'generator_mcp_unsupported' ||
  'pool_launch_unsupported' ||
  'pool_session_unsupported' => l10n.teamGenerateErrorGeneratorUnsupported,
  'native_pool_cli_mismatch' ||
  'native_team_unsupported' => l10n.teamGenerateErrorNativeUnsupported,
  _ => l10n.teamGenerateErrorStartFailed,
};
