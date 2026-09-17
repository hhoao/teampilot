enum SessionInitStage { layout, contribute, project, apply, afterApply, spawn }

final class SessionInitException implements Exception {
  SessionInitException(this.stage, {this.path, this.cause, this.message});
  final SessionInitStage stage;
  final String? path;
  final Object? cause;
  final String? message;
  @override
  String toString() => 'SessionInitException($stage, path: $path, $message)';
}
