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
}

class _FakeRuntimeTargetRegistry implements RuntimeTargetRegistry {
  final Map<String, RuntimeTarget> _targets = {
    'local': RuntimeTarget.local(),
    'ssh:p1': RuntimeTarget.ssh('p1', label: 'one'),
    'ssh:p2': RuntimeTarget.ssh('p2', label: 'two'),
  };

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
