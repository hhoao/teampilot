import 'install_job_key.dart';

enum InstallJobPhase {
  queued,
  running,
  cancelling,
  succeeded,
  failed,
  cancelled,
}

final class InstallJobSnapshot {
  const InstallJobSnapshot({
    required this.key,
    required this.phase,
    this.subtitle,
    this.fraction,
  });

  final InstallJobKey key;
  final InstallJobPhase phase;
  final String? subtitle;
  final double? fraction;
}
