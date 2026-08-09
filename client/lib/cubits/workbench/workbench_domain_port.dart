// lib/cubits/workbench/workbench_domain_port.dart
import 'workbench_tab.dart';

/// Teardown port: called by [WorkbenchCubit] when a tab is removed from the
/// bar so the owning domain can dispose its runtime. Implemented by the
/// bridge / coordinator wired in `app_shell.dart`.
abstract class WorkbenchDomainPort {
  Future<void> onTabRemoved(String workspaceId, WorkbenchTabId id);
}
