import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/ai_feature_settings_cubit.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../models/landing_launch_context.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../models/ai_feature_setting.dart';
import '../../../models/workspace.dart';
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
      'Team generation workflow is unavailable. Restart TeamPilot and try again.',
    );
    return false;
  }

  final preflight = await coordinator.preflight(
    workspace: workspace,
    originalPrompt: trimmed,
  );
  if (preflight.issues.isNotEmpty) {
    if (context.mounted) {
      showWorkspaceLandingGenerationPreflight(context, preflight.issues);
    }
    return false;
  }

  final generatorSetting = context
      .read<AiFeatureSettingsCubit>()
      .state
      .settingFor(AiFeatureId.teamGenerate);
  try {
    final result = await coordinator.start(
      workspace: workspace,
      originalPrompt: trimmed,
      generatorPresetId: generatorSetting?.activePresetId ?? '',
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
    appLogger.e(
      '[team-generation] landing start failed',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      context.read<ChatCubit>().failSessionConnect(
        'pending',
        'Team generation could not start: $error',
      );
    }
    return false;
  }
}

/// Localized preflight surface shown above the landing input on issues.
void showWorkspaceLandingGenerationPreflight(
  BuildContext context,
  List<TeamGenerationPreflightIssue> issues,
) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        'generation preflight: ${issues.map((issue) => issue.code).join(', ')}',
      ),
    ),
  );
}
