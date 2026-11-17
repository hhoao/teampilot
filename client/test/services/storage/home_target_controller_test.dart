import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';

void main() {
  test('select(currentId) is a no-op — no registry churn, no reload', () async {
    final fakeRegistry = _FakeRuntimeTargetRegistry();
    var switches = 0;
    var current = RuntimeTarget.ssh('p1', label: 'one');
    final controller = HomeTargetController(
      registry: fakeRegistry,
      current: () => current,
      switchTo: (id) async {
        switches++;
        current = fakeRegistry.targetById(id)!;
      },
    );

    await controller.select(controller.currentId);
    expect(switches, 0);

    await controller.select('ssh:p2');
    expect(switches, 1);
    expect(controller.currentId, 'ssh:p2');
  });

  test('listSelectable is the A-source home palette; listWorkspaceTargets is '
      'the B-source workload catalog', () async {
    final homeRegistry = _FakeRuntimeTargetRegistry(
      targets: {
        'local': RuntimeTarget.local(),
        'ssh:home': RuntimeTarget.ssh('home', label: 'home host'),
      },
    );
    final workloadRegistry = _FakeRuntimeTargetRegistry(
      targets: {
        'local': RuntimeTarget.local(),
        'ssh:work1': RuntimeTarget.ssh('work1', label: 'workload 1'),
        'ssh:work2': RuntimeTarget.ssh('work2', label: 'workload 2'),
      },
    );
    final controller = HomeTargetController(
      registry: homeRegistry,
      workloadRegistry: workloadRegistry,
      current: () => RuntimeTarget.local(),
      switchTo: (_) async {},
    );

    final home = (await controller.listSelectable()).map((t) => t.id).toSet();
    expect(home, {'local', 'ssh:home'});
    expect(home, isNot(contains('ssh:work1')));

    final workload =
        (await controller.listWorkspaceTargets()).map((t) => t.id).toSet();
    expect(workload, {'local', 'ssh:work1', 'ssh:work2'});
    expect(workload, isNot(contains('ssh:home')));
  });

  test('listWorkspaceTargets falls back to the home palette when no workload '
      'registry is wired (tests / embedded harnesses)', () async {
    final registry = _FakeRuntimeTargetRegistry();
    final controller = HomeTargetController(
      registry: registry,
      current: () => RuntimeTarget.local(),
      switchTo: (_) async {},
    );
    expect(
      (await controller.listWorkspaceTargets()).map((t) => t.id).toSet(),
      (await controller.listSelectable()).map((t) => t.id).toSet(),
    );
  });
}

class _FakeRuntimeTargetRegistry implements RuntimeTargetRegistry {
  _FakeRuntimeTargetRegistry({Map<String, RuntimeTarget>? targets})
      : _targets = targets ??
            {
              'local': RuntimeTarget.local(),
              'ssh:p1': RuntimeTarget.ssh('p1', label: 'one'),
              'ssh:p2': RuntimeTarget.ssh('p2', label: 'two'),
            };

  final Map<String, RuntimeTarget> _targets;

  RuntimeTarget? targetById(String id) => _targets[id];

  @override
  final bool isAndroid = false;

  @override
  final bool isWindows = false;

  @override
  Future<RuntimeTarget?> findById(String targetId, {String wslDistro = ''}) =>
      Future.value(_targets[targetId]);

  @override
  Future<List<RuntimeTarget>> listTargets({String wslDistro = ''}) =>
      Future.value(_targets.values.toList());
}
