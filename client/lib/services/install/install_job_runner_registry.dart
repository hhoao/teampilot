import '../../models/install_job/install_job_key.dart';
import 'install_job_runner.dart';

final class InstallJobRunnerRegistry {
  InstallJobRunnerRegistry({required List<InstallJobRunner> runners})
    : _runners = List.unmodifiable(runners);

  final List<InstallJobRunner> _runners;

  InstallJobRunner? resolve(InstallJobKey key) {
    for (final runner in _runners) {
      if (runner.supports(key)) {
        return runner;
      }
    }
    return null;
  }
}
