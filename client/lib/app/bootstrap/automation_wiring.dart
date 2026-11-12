import 'dart:async';

import 'package:collection/collection.dart';

import '../../cubits/automation_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../models/cli_preset.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../repositories/automation_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/automation/automation_bus_gateway.dart';
import '../../services/automation/automation_command_executor.dart';
import '../../services/automation/automation_command_runner.dart';
import '../../services/automation/automation_dispatcher.dart';
import '../../services/automation/automation_run_accounting.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/automation/automation_scheduler.dart';
import '../../services/catalog/catalog_mutation_bus.dart';
import '../../services/catalog/catalog_runtime.dart';
import '../../services/catalog/modules/automation_catalog_module.dart';
import '../../services/run/process_run_executor.dart';
import '../../services/run/run_target_resolver.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/workspace_layout.dart';

/// The app-lifetime automation graph driven by the shell.
typedef AutomationWiring = ({
  AutomationCubit automationCubit,
  AutomationScheduler automationScheduler,
  StreamSubscription<CatalogMutationEvent> catalogSubscription,
});

/// Builds the automation repository for [storage]'s home plane.
///
/// Kept separate from [wireAutomationRuntime] because the chat cubit is
/// constructed with the repository long before the scheduler graph exists.
AutomationRepository buildAutomationRepository({required HomeStorage storage}) {
  return AutomationRepository(
    fs: storage.fs,
    layout: WorkspaceLayout(
      teampilotRoot: storage.paths.basePath,
      fs: storage.fs,
    ),
  );
}

/// Builds the command runner, dispatcher, scheduler and cubit that execute
/// automations, then registers the automation catalog module and subscribes
/// the cubit's refresh to catalog-driven automation writes.
///
/// The module is registered here rather than in `CatalogRuntime.assemble`
/// because the repository, scheduler and resolvers are constructed below that
/// call. The registry recomputes routes on every call, so the tools appear as
/// soon as this runs; the bus subscription refreshes the Automations page
/// after catalog-driven writes. [chatCubit] and [sessionRepository] are
/// getters because the shell owns them as `late final` dependencies.
AutomationWiring wireAutomationRuntime({
  required AutomationRepository repository,
  required AutomationScheduleCalculator scheduleCalculator,
  required CatalogRuntime catalogRuntime,
  required ChatCubit Function() chatCubit,
  required SessionRepository Function() sessionRepository,
  required SessionPreferencesCubit sessionPreferences,
  required TeamProfile? Function(String teamId) teamById,
  required CliPreset? Function(String presetId) resolveCliPreset,
  required RuntimeTarget Function() homeTarget,
  required SshProcessSpawner sshSpawner,
}) {
  final chat = chatCubit();
  final sessions = sessionRepository();

  late final AutomationCubit automationCubit;
  void refreshAutomations() {
    if (!automationCubit.isClosed) {
      unawaited(automationCubit.reloadPreservingScope());
    }
  }

  final automationCommandRunner = HostAutomationCommandRunner(
    workspaceById: (workspaceId) => chat.state.workspaces
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull,
    resolver: RunTargetResolver(homeTarget: homeTarget),
    executor: ProcessRunExecutor(sshSpawner: sshSpawner),
  );
  final automationCommandExecutor = AutomationCommandExecutor(
    repository: repository,
    accounting: AutomationRunAccounting(scheduleCalculator),
    runner: automationCommandRunner,
    onAfterRun: refreshAutomations,
  );
  final automationDispatcher = AutomationDispatcher(
    repository: repository,
    scheduleCalculator: scheduleCalculator,
    sessionRepository: sessions,
    busGateway: TabTeamBusGateway(
      memberMaterializer: chat.memberMaterializer,
      sessionRuntime: chat.sessionRuntime,
      tabStore: chat.tabStore,
      activatePersonalAcp: chat.retrySessionLaunch,
      activateMemberSeat: chat.ensureMemberTerminalForView,
    ),
    requestOpenSession: chat.requestOpenSession,
    requestCreateAndOpenSession: chat.requestCreateAndOpenSession,
    workspaceById: (workspaceId) => chat.state.workspaces
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull,
    teamById: teamById,
    resolveCliPreset: resolveCliPreset,
    sessionById: (sessionId, workspaceId) => chat.state.sessions
        .where(
          (s) => s.sessionId == sessionId && s.workspaceId == workspaceId,
        )
        .firstOrNull,
    applySessionTitle: chat.applySessionTitle,
    acpDefaultFor: sessionPreferences.acpDefaultFor,
    runDeliveryInFlight: chat.withOperatorDeliveryInFlight,
  );
  final automationScheduler = AutomationScheduler(
    repository: repository,
    dispatcher: automationDispatcher,
    scheduleCalculator: scheduleCalculator,
    commandExecutor: automationCommandExecutor,
  );
  automationCubit = AutomationCubit(
    repository: repository,
    scheduler: automationScheduler,
    scheduleCalculator: scheduleCalculator,
  );
  chat.bindAutomationsChangeNotifier(refreshAutomations);
  catalogRuntime.registry.register(
    AutomationCatalogModule(
      repository: repository,
      scheduleCalculator: scheduleCalculator,
      bus: catalogRuntime.bus,
      runNow: automationScheduler.runNow,
      teamExists: (teamId) => teamById(teamId) != null,
      presetExists: (presetId) => resolveCliPreset(presetId) != null,
      memberExists: (teamId, memberId) {
        final team = teamById(teamId);
        return team != null &&
            team.members.any((m) => m.id == memberId && m.isValid);
      },
      sessionExists: (sessionId, workspaceId) async {
        final session = await sessions.findById(sessionId);
        return session != null && session.workspaceId == workspaceId;
      },
      workspaceFolders: (workspaceId) => chat.state.workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull
          ?.folders,
    ),
  );
  final automationCatalogSub = catalogRuntime.bus.listen().listen((event) {
    if (event.kind != 'automation') return;
    refreshAutomations();
  });

  return (
    automationCubit: automationCubit,
    automationScheduler: automationScheduler,
    catalogSubscription: automationCatalogSub,
  );
}
