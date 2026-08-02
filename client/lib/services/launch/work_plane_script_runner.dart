import '../../models/ssh_profile.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/ssh_run_result.dart';
import '../ssh/ssh_storage_io.dart';

/// Runs a POSIX shell script on the session work plane.
///
/// Local/WSL callers leave this null and use [Filesystem] APIs instead.
/// SSH/Termux work planes inject [SshWorkPlaneScriptRunner] so multi-op
/// setup stays one remote round-trip.
abstract interface class WorkPlaneScriptRunner {
  Future<void> runScript(
    String script, {
    required String operation,
    Duration? timeout,
  });
}

/// Storage-plane SSH exec used by manifest flush and post-flush hooks.
final class SshWorkPlaneScriptRunner implements WorkPlaneScriptRunner {
  const SshWorkPlaneScriptRunner({
    required this.sshClientFactory,
    required this.profile,
  });

  final SshClientFactory sshClientFactory;
  final SshProfile profile;

  /// Returns a runner when [sshProfileId] resolves; otherwise `null` (local FS).
  static SshWorkPlaneScriptRunner? tryCreate({
    required String? sshProfileId,
    required SshClientFactory? sshClientFactory,
    required SshProfile? Function(String profileId)? profileById,
  }) {
    final id = sshProfileId?.trim() ?? '';
    if (id.isEmpty || sshClientFactory == null || profileById == null) {
      return null;
    }
    final profile = profileById(id);
    if (profile == null) return null;
    return SshWorkPlaneScriptRunner(
      sshClientFactory: sshClientFactory,
      profile: profile,
    );
  }

  @override
  Future<void> runScript(
    String script, {
    required String operation,
    Duration? timeout,
  }) async {
    final result = await sshClientFactory.runOnStorage(
      profile,
      script,
      timeout: timeout ?? SshStorageIo.provisionPhaseTimeout,
    );
    if (sshRunFailed(result)) {
      final detail = sshRunOutputDetail(result);
      throw StateError(
        '$operation failed on ${profile.host}: $detail',
      );
    }
  }
}
