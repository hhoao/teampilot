import '../../models/install_job/install_job_key.dart';
import '../../models/progress_activity.dart';

ProgressActivityKind activityKindForInstall(InstallJobKind kind) =>
    switch (kind) {
      InstallJobKind.cliExecutable => ProgressActivityKind.cliProvision,
      InstallJobKind.toolchain => ProgressActivityKind.cliProvision,
      InstallJobKind.packAcquire => ProgressActivityKind.packAcquire,
      InstallJobKind.hubClone => ProgressActivityKind.hubClone,
      InstallJobKind.fileTreeImport => ProgressActivityKind.fileTreeImport,
      InstallJobKind.appUpdate => ProgressActivityKind.appUpdate,
    };
