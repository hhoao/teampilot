import '../storage/remote_file_store.dart';
import 'host_run_request.dart';

enum HostTtyScriptFlavor { gnu, bsd }

/// Wraps a login CLI so its stdout is a TTY (line-buffered).
abstract final class HostTtyWrap {
  static HostRunRequest apply(
    HostRunRequest request, {
    required HostTtyScriptFlavor flavor,
  }) {
    if (!request.allocateTty) return request;
    return switch (flavor) {
      HostTtyScriptFlavor.gnu => _gnu(request),
      HostTtyScriptFlavor.bsd => _bsd(request),
    };
  }

  static HostRunRequest _gnu(HostRunRequest request) {
    final inner = [
      RemoteFileStore.shellSingleQuote(request.executable),
      ...request.arguments.map(RemoteFileStore.shellSingleQuote),
    ].join(' ');
    return HostRunRequest(
      executable: 'script',
      arguments: ['-qefc', inner, '/dev/null'],
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      includeParentEnvironment: request.includeParentEnvironment,
    );
  }

  static HostRunRequest _bsd(HostRunRequest request) {
    return HostRunRequest(
      executable: 'script',
      arguments: ['-q', '/dev/null', request.executable, ...request.arguments],
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      includeParentEnvironment: request.includeParentEnvironment,
    );
  }
}
