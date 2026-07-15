import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';

class RosterMachine {
  const RosterMachine({
    required this.machine,
    required this.machineKind,
    required this.machineId,
  });

  final String machine;
  final String machineKind;
  final String machineId;
}

RosterMachine rosterMachineFromTarget(
  RuntimeTarget target, {
  SshProfile? profile,
}) {
  final kind = target.kind.name;
  final id = target.id;
  final machine = switch (target.kind) {
    RuntimeKind.local => 'local',
    RuntimeKind.wsl => id,
    RuntimeKind.ssh =>
      (profile != null && profile.hostIdentifier.trim().isNotEmpty)
          ? profile.hostIdentifier
          : id,
  };
  return RosterMachine(machine: machine, machineKind: kind, machineId: id);
}
