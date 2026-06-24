import '../../models/team_config.dart';
import '../io/filesystem.dart';
import 'materialization_manifest.dart';

/// One locally-generated credential file destined for `providers/{tool}/` on the
/// work machine. [relativePath] is relative to that tool dir; [content] may embed
/// absolute paths (e.g. a key file location) that must be rebased to the remote.
class CredentialFile {
  const CredentialFile({required this.relativePath, required this.content});
  final String relativePath;
  final String content;
}

/// Materializes locally-generated credentials onto a remote work machine
/// (P3c §3.4), **per-target opt-in, default off**. Credentials are still
/// generated locally; when opted in, files are written under
/// `<machineRoot>/providers/{tool}/` and any embedded absolute path under the
/// local root is rebased to `<machineRoot>` (today's link targets are local
/// absolute paths that don't resolve cross-machine). Rotation (changed bytes) is
/// detected via [MaterializationManifest] and re-pushed.
class RemoteCredentialMaterializer {
  RemoteCredentialMaterializer({required this.manifest});

  final MaterializationManifest manifest;

  Future<void> materialize({
    required CliTool cli,
    required Filesystem workFs,
    required String machineRoot,
    required String localRoot,
    required bool optIn,
    required List<CredentialFile> localCredentials,
  }) async {
    if (!optIn) return; // default off — no key leaves the local machine

    final hashes = await manifest.load();
    for (final cred in localCredentials) {
      // Rebase any embedded local-root absolute path to the work machine root.
      final rewritten = cred.content.replaceAll(localRoot, machineRoot);
      final key = 'providers/${cli.value}/${cred.relativePath}';
      final hash = manifest.hashOf(rewritten.codeUnits);
      if (hashes[key] == hash) continue; // unchanged → skip
      await workFs.writeString(
        workFs.pathContext.join(machineRoot, key),
        rewritten,
      );
      hashes[key] = hash;
    }
    await manifest.save(hashes);
  }
}
