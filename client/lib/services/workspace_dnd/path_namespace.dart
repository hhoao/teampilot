import '../storage/runtime_storage_context.dart';

/// The path *style* a namespace uses when rendering an absolute path.
enum PathStyle {
  /// `/home/user/x` — POSIX forward slashes.
  posix,

  /// `C:\Users\x` — Windows drive + backslashes.
  windows,
}

/// Where a filesystem path lives, for drag-and-drop projection.
///
/// A [PathNamespace] answers two questions a dropped file must survive:
/// *which machine* the path belongs to ([hostId]) and *how absolute paths are
/// spelled* there ([style]). The drag payload captures the source namespace;
/// the drop target (a terminal) carries its own. [PathProjection] compares them
/// to decide whether a path can be re-expressed locally (same host, maybe a
/// different style) or must go through a cross-namespace strategy.
///
/// `hostId` is intentionally coarse today (`local` vs `ssh`): TeamPilot runs a
/// single active SSH remote at a time, so two SSH namespaces are treated as the
/// same host. The field is a string so finer per-folder machine identity (see
/// the multi-folder workspace design) can slot in without touching callers.
class PathNamespace {
  const PathNamespace({required this.hostId, required this.style});

  /// Local machine, POSIX paths (Linux/macOS desktop, or a WSL CLI view).
  const PathNamespace.localPosix() : hostId = _localHost, style = PathStyle.posix;

  /// Local machine, Windows paths (native Windows desktop).
  const PathNamespace.localWindows()
    : hostId = _localHost,
      style = PathStyle.windows;

  /// A remote SSH host. POSIX by assumption (TeamPilot's remotes are Unix).
  const PathNamespace.ssh() : hostId = _sshHost, style = PathStyle.posix;

  static const _localHost = 'local';
  static const _sshHost = 'ssh';

  /// Coarse machine identity. Two namespaces with the same [hostId] live on the
  /// same machine, so a path can be re-projected between them without transfer.
  final String hostId;

  final PathStyle style;

  bool get isLocal => hostId == _localHost;
  bool get isSsh => hostId == _sshHost;

  /// True when both namespaces denote the same machine (path can be projected
  /// locally); false means a cross-namespace transfer would be required.
  bool sameHostAs(PathNamespace other) => hostId == other.hostId;

  /// The namespace the file tree / app filesystem currently lives in, derived
  /// from the installed [RuntimeStorageContext] backend.
  static PathNamespace ofCurrentStorage() {
    if (!RuntimeStorageContext.isInstalled) {
      return const PathNamespace.localPosix();
    }
    switch (RuntimeStorageContext.current.mode) {
      case StorageBackendMode.ssh:
        return const PathNamespace.ssh();
      case StorageBackendMode.wsl:
        // WSL app data is viewed through `\\wsl$` UNC paths on the host, but the
        // file tree surfaces them as POSIX; treat the source as local POSIX.
        return const PathNamespace.localPosix();
      case StorageBackendMode.native:
        return RuntimeStorageContext.current.usesPosixPaths
            ? const PathNamespace.localPosix()
            : const PathNamespace.localWindows();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PathNamespace &&
      other.hostId == hostId &&
      other.style == style;

  @override
  int get hashCode => Object.hash(hostId, style);

  @override
  String toString() => 'PathNamespace($hostId, ${style.name})';
}
