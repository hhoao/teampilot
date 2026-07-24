import '../../cubits/workbench/workbench_tab.dart';

/// 1-based strip ordinal (Alt+1…9 / Alt+0 → 10). Null when empty or OOB.
WorkbenchTabId? workbenchTabAt(List<WorkbenchTabId> order, int oneBasedOrdinal) {
  if (oneBasedOrdinal < 1 || oneBasedOrdinal > 10) return null;
  final index = oneBasedOrdinal - 1;
  if (index >= order.length) return null;
  return order[index];
}

/// Next tab in [order], wrapping. Null when empty.
///
/// Unknown / null [active] starts at the first tab.
WorkbenchTabId? workbenchNextTab(
  List<WorkbenchTabId> order,
  WorkbenchTabId? active,
) {
  if (order.isEmpty) return null;
  final index = active == null ? -1 : order.indexOf(active);
  if (index < 0) return order.first;
  return order[(index + 1) % order.length];
}

/// Previous tab in [order], wrapping. Null when empty.
///
/// Unknown / null [active] starts at the last tab.
WorkbenchTabId? workbenchPrevTab(
  List<WorkbenchTabId> order,
  WorkbenchTabId? active,
) {
  if (order.isEmpty) return null;
  final index = active == null ? -1 : order.indexOf(active);
  if (index < 0) return order.last;
  return order[(index - 1 + order.length) % order.length];
}
