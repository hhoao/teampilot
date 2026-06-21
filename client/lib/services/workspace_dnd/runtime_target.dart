import 'path_namespace.dart';

/// The execution namespace a terminal session lives in — the machine and path
/// style of the process running inside its PTY. A drop target reads this to
/// know how to project a dragged path so the CLI on the other end can resolve
/// it. Set as a first-class property of a `TerminalSession` at connect time
/// (the forward sibling of `FilePathLinkProvider`, which maps the reverse way).
class RuntimeTarget {
  const RuntimeTarget({required this.namespace, this.workingDirectory = ''});

  /// Local PTY running a native (Linux/macOS) CLI.
  const RuntimeTarget.localPosix({this.workingDirectory = ''})
    : namespace = const PathNamespace.localPosix();

  /// Local PTY running a native Windows CLI.
  const RuntimeTarget.localWindows({this.workingDirectory = ''})
    : namespace = const PathNamespace.localWindows();

  /// Local PTY wrapping `wsl.exe`: a CLI that sees `/mnt/<drive>` POSIX paths.
  const RuntimeTarget.wsl({this.workingDirectory = ''})
    : namespace = const PathNamespace.localPosix();

  /// CLI running on a remote SSH host.
  const RuntimeTarget.ssh({this.workingDirectory = ''})
    : namespace = const PathNamespace.ssh();

  final PathNamespace namespace;

  /// The CLI's working directory in [namespace], when known (unused by v1
  /// projection but available for relative-path rendering later).
  final String workingDirectory;

  @override
  String toString() => 'RuntimeTarget($namespace, cwd=$workingDirectory)';
}
