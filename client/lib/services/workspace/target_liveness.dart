import '../../models/runtime_target.dart';
import '../../repositories/ssh_profile_repository.dart';

abstract class TargetLiveness {
  Future<bool> isAlive(String targetId);
}

class DefaultTargetLiveness implements TargetLiveness {
  DefaultTargetLiveness({
    required SshProfileRepository sshProfiles,
    bool Function()? hasTermuxConfig,
  }) : _sshProfiles = sshProfiles,
       _hasTermuxConfig = hasTermuxConfig;

  final SshProfileRepository _sshProfiles;
  final bool Function()? _hasTermuxConfig;

  @override
  Future<bool> isAlive(String targetId) async {
    final id = targetId.trim();
    if (id.isEmpty) return false;
    switch (runtimeKindOfId(id)) {
      case RuntimeKind.local:
        return true;
      case RuntimeKind.wsl:
        // Future: probe distro list; until then assume alive if well-formed.
        return wslDistroOfId(id)?.isNotEmpty == true;
      case RuntimeKind.ssh:
        final profileId = sshProfileIdOfId(id);
        if (profileId == null || profileId.isEmpty) return false;
        return (await _sshProfiles.findById(profileId)) != null;
      case RuntimeKind.termux:
        if (!id.startsWith('termux:')) return false;
        return _hasTermuxConfig?.call() ?? true;
    }
  }
}
