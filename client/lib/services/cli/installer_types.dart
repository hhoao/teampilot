import '../../models/ssh_profile.dart';

enum CliInstallMode { local, ssh }

enum CliInstallPhase {
  checkingNpm,
  bootstrappingNode,
  installingCli,
  locatingExecutable,
}

class CliInstallProgress {
  const CliInstallProgress({required this.phase, this.detail});

  final CliInstallPhase phase;
  final String? detail;
}

class CliInstallerCommand {
  const CliInstallerCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get commandLine => [
    executable,
    ...arguments.map(_shellQuoteIfNeeded),
  ].join(' ');

  static String _shellQuoteIfNeeded(String value) {
    if (value.isEmpty) return "''";
    if (!value.contains(RegExp(r'\s'))) return value;
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}

class CliInstallerCommandResult {
  const CliInstallerCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String get output {
    final text = [stdout.trim(), stderr.trim()]
        .where((value) => value.isNotEmpty)
        .join('\n');
    return text;
  }
}

class CliInstallResult {
  const CliInstallResult({
    required this.success,
    required this.message,
    this.executablePath,
  });

  final bool success;
  final String message;
  final String? executablePath;
}

typedef LocalCliInstallRunner =
    Future<CliInstallerCommandResult> Function(CliInstallerCommand command);
typedef SshCliInstallRunner =
    Future<CliInstallerCommandResult> Function(
      SshProfile profile,
      CliInstallerCommand command,
    );

typedef CliInstallProgressCallback = void Function(CliInstallProgress progress);

String? firstInstallerOutputLine(CliInstallerCommandResult result) {
  if (result.exitCode != 0) return null;
  final line = result.stdout.split('\n').first.trim();
  return line.isEmpty ? null : line;
}

String installerFailureMessage(String title, CliInstallerCommandResult result) {
  final output = result.output;
  if (output.isEmpty) return '$title (exit ${result.exitCode}).';
  return '$title (exit ${result.exitCode}): $output';
}
