import 'cli_launch_arg_contribution.dart';
import 'cli_launch_arg_provider.dart';
import 'cli_launch_context.dart';

/// Normalized workspace access inputs shared by CLI-specific encodings.
final class WorkspaceAccess {
  WorkspaceAccess({
    required this.workingDirectory,
    required List<String> additionalDirectories,
  }) : additionalDirectories = List.unmodifiable(additionalDirectories);

  final String? workingDirectory;
  final List<String> additionalDirectories;

  bool get isEmpty => workingDirectory == null && additionalDirectories.isEmpty;

  factory WorkspaceAccess.fromContext(CliLaunchContext context) {
    final workingDirectory = _normalizeOptionalPath(
      context.workingDirectory,
      useWslPaths: context.useWslPaths,
    );
    final additionalDirectories = [
      for (final directory in context.additionalDirectories)
        if (_normalizeOptionalPath(directory, useWslPaths: context.useWslPaths)
            case final normalized?)
          normalized,
    ];

    return WorkspaceAccess(
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
    );
  }
}

String? _normalizeOptionalPath(String? path, {required bool useWslPaths}) {
  final trimmed = path?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return normalizePathForCli(trimmed, useWslPaths: useWslPaths);
}

/// Base contract for CLI-specific encodings of workspace access.
abstract base class WorkspaceAccessArgProvider implements CliLaunchArgProvider {
  const WorkspaceAccessArgProvider();

  /// Encodes the normalized primary and additional workspace directories.
  Iterable<CliLaunchArgContribution> buildWorkspaceAccessArgs(
    CliLaunchContext context,
    WorkspaceAccess access,
  );

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final access = WorkspaceAccess.fromContext(context);
    if (access.isEmpty) return;
    yield* buildWorkspaceAccessArgs(context, access);
  }
}
