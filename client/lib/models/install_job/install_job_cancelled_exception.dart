import 'install_job_key.dart';

final class InstallJobCancelledException implements Exception {
  const InstallJobCancelledException(this.key);
  final InstallJobKey key;
  @override
  String toString() => 'Install job cancelled: ${key.activityId}';
}
