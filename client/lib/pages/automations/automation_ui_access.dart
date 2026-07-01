import '../../repositories/automation_repository.dart';
import '../../services/storage/app_storage.dart';
import '../../services/storage/workspace_layout.dart';

/// Resolves [AutomationRepository] from app storage until [AutomationCubit]
/// is wired in [app_shell.dart].
AutomationRepository resolveAutomationRepository() {
  return AutomationRepository(
    fs: AppStorage.fs,
    layout: WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath),
  );
}
