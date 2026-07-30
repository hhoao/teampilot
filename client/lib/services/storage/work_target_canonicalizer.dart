import '../../models/runtime_target.dart';

/// Single choke point: folder/member target ids ↔ execution [RuntimeTarget].
///
/// [RuntimeTarget.localId] means device-native only. When [home] is SSH/WSL,
/// bare `local` is normalized to [home] (dirty Android / SSH-home data).
abstract final class WorkTargetCanonicalizer {
  static String defaultFolderTargetId(RuntimeTarget home) {
    if (home.kind == RuntimeKind.local) return RuntimeTarget.localId;
    return home.id;
  }

  static RuntimeTarget fromId(String id) {
    final trimmed = id.trim();
    return switch (runtimeKindOfId(trimmed)) {
      RuntimeKind.ssh => RuntimeTarget.ssh(
        sshProfileIdOfId(trimmed) ?? '',
        label: '',
      ),
      RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(trimmed) ?? ''),
      RuntimeKind.local => RuntimeTarget.local(),
    };
  }

  static RuntimeTarget resolve(String targetId, {required RuntimeTarget home}) {
    final trimmed = targetId.trim();
    if (trimmed.isEmpty || trimmed == RuntimeTarget.localId) {
      if (home.kind != RuntimeKind.local) return home;
      return RuntimeTarget.local();
    }
    return fromId(trimmed);
  }
}
