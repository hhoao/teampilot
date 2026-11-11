import 'package:logger/logger.dart';

enum AppLogLevel { debug, info, warning, error }

extension AppLogLevelX on AppLogLevel {
  String get directoryName => switch (this) {
    AppLogLevel.debug => 'debug',
    AppLogLevel.info => 'info',
    AppLogLevel.warning => 'warn',
    AppLogLevel.error => 'error',
  };

  Level toLoggerLevel() => switch (this) {
    AppLogLevel.debug => Level.debug,
    AppLogLevel.info => Level.info,
    AppLogLevel.warning => Level.warning,
    AppLogLevel.error => Level.error,
  };
}

AppLogLevel? appLogLevelFromViewerLabel(String label) {
  return switch (label) {
    'DEBUG' => AppLogLevel.debug,
    'INFO' => AppLogLevel.info,
    'WARNING' => AppLogLevel.warning,
    'ERROR' => AppLogLevel.error,
    _ => null,
  };
}

AppLogLevel fullTimelineLogLevel({required bool includeDebug}) =>
    includeDebug ? AppLogLevel.debug : AppLogLevel.info;
