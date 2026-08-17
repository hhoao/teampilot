import '../../../../models/team_config.dart';

/// A requested launch capability could not be assembled safely.
final class CliLaunchCapabilityException implements Exception {
  const CliLaunchCapabilityException({
    required this.cli,
    required this.capabilityKey,
    required this.reason,
    this.exclusiveGroup,
    this.conflictingCapabilityKey,
  });

  final CliTool cli;
  final String capabilityKey;
  final String reason;
  final String? exclusiveGroup;
  final String? conflictingCapabilityKey;

  /// Alias useful at boundaries that describe exceptions by message.
  String get message => reason;

  @override
  String toString() {
    return 'CliLaunchCapabilityException('
        '${cli.value}, $capabilityKey): $reason';
  }
}
