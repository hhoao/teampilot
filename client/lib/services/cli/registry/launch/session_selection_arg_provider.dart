import 'cli_launch_arg_contribution.dart';
import 'cli_launch_arg_provider.dart';
import 'cli_launch_context.dart';

/// The semantic session choice requested by a launch context.
enum SessionSelectionKind { resume, fixed }

/// A normalized session selection. A resume id takes precedence over a fixed
/// id when both are present in the launch context.
final class SessionSelection {
  const SessionSelection({required this.kind, required this.id});

  final SessionSelectionKind kind;
  final String id;

  static SessionSelection? fromContext(CliLaunchContext context) {
    final resume = context.resumeSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      return SessionSelection(kind: SessionSelectionKind.resume, id: resume);
    }

    final fixed = context.fixedSessionId?.trim() ?? '';
    if (fixed.isNotEmpty) {
      return SessionSelection(kind: SessionSelectionKind.fixed, id: fixed);
    }

    return null;
  }
}

/// Base contract for CLI-specific encodings of session selection.
abstract base class SessionSelectionArgProvider
    implements CliLaunchArgProvider {
  const SessionSelectionArgProvider();

  /// Encodes [selection] using the CLI's own session flags or subcommand.
  Iterable<CliLaunchArgContribution> buildSessionSelectionArgs(
    CliLaunchContext context,
    SessionSelection selection,
  );

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final selection = SessionSelection.fromContext(context);
    if (selection == null) return;
    yield* buildSessionSelectionArgs(context, selection);
  }
}
