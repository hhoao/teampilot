import '../../models/install_job/install_job_context.dart';
import '../../models/install_job/install_job_key.dart';
import '../../models/install_job/install_job_spec.dart';

abstract interface class InstallJobRunner {
  InstallJobKind get kind;

  bool supports(InstallJobKey key);

  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx);
}
