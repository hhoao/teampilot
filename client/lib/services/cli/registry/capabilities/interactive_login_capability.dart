import 'package:flutter/widgets.dart';

import '../../../../models/app_provider_config.dart';
import '../cli_capability.dart';

/// Provider auth that has to run in an **embedded interactive terminal**.
///
/// Some CLIs expose no non-interactive login command (CodeBuddy:
/// login lives in the TUI `/login` flow). Their provider capability declares
/// this interface; the provider credential bar then opens
/// [buildLoginDialog] instead of calling `execute(login)` directly, and runs
/// `execute(login)` afterwards to record the completed sign-in.
abstract interface class InteractiveCliLoginCapability implements CliCapability {
  /// Binary started inside the login terminal (bare name is fine; the
  /// transport starter resolves PATH / `.cmd` shims).
  String get loginExecutableName;

  /// Extra argv for the login terminal. Usually empty.
  List<String> get loginArguments;

  /// Builds the modal login terminal. Resolves `true` when the user finishes,
  /// `false`/null when they cancel.
  Widget buildLoginDialog(
    BuildContext context, {
    required AppProviderConfig provider,
    required String executable,
  });
}
