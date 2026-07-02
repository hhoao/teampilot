import '../../models/automation.dart';

/// Outcome of [AutomationDispatcher.dispatch] for scheduler bookkeeping.
class AutomationDispatchResult {
  const AutomationDispatchResult({
    required this.run,
    required this.automation,
  });

  final AutomationRun run;
  final Automation automation;
}
