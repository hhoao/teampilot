import 'dart:io';

import '../../../storage/home_storage.dart';
import '../../installer_types.dart';
import '../../registry/installer/acp_adapter_installer.dart';
import '../../registry/installer/binary_archive_installer.dart';
import '../../registry/installer/installer_context.dart';

/// Pinned Antigravity ACP adapter release (`agy_acp_server`).
const antigravityAcpVersion = '1.4.3';

/// Asset key for the pinned release, e.g. `linux-x86_64`.
///
/// Anything that is not `arm64` maps to the x86_64 asset: the adapter is the
/// same binary for both macOS/Linux/Windows x86_64 hosts and no other arch
/// exists in the catalog.
String antigravityAcpAssetKey({required String os, required String arch}) {
  final a = arch == 'arm64' ? 'aarch64' : 'x86_64';
  return '$os-$a';
}

/// Published SHA-256 per asset key (from the 1.4.3 release listing).
const antigravityAcpSha256 = <String, String>{
  'darwin-aarch64':
      'c57db0a9b8b712daa9c3c17cdb990a61842ea569f279e8bd79d7aa85a303b20b',
  'darwin-x86_64':
      '9392dbbdad7f0663dbfb5a0bf641297b0cf80d2ee9cd2d49a616bbbc7378731d',
  'linux-x86_64':
      '0634ce5306ba92c932945455e7a83fda78e2d99c33fa8aa6ee0566206a382714',
  'linux-aarch64':
      '05c153443b0b1175151c760eeddea538950bc9843e317d54786a1f03670182bc',
  'windows-x86_64':
      '54c2e16378d9a4952e1da70e355f3c33c4f284308d6de48ab3e6e34a127bd325',
  'windows-aarch64':
      'fcd46431ad33d3b510ce0b98fe7b43d095bd8b3f1c363ee2d57faa7ee981c7bb',
};

/// Download URL for [assetKey].
///
/// The release host uses `macos` for Darwin assets and the plain OS name
/// (`linux` / `windows`) otherwise — not the `darwin` prefix from the key.
String antigravityAcpArchiveUrl(String assetKey) {
  final folder = assetKey.startsWith('darwin')
      ? 'macos'
      : assetKey.split('-').first;
  return 'https://dl.google.com/agy-extensions/releases/$folder/'
      'agy-acp-server-$antigravityAcpVersion-$assetKey.zip';
}

/// Downloads the pinned Antigravity ACP adapter archive into app data.
///
/// Local installs only: the adapter is a host executable, so an SSH target
/// would need a remote download path that does not exist yet. Readiness UI and
/// install jobs depend on [AcpAdapterInstaller] only.
final class AntigravityAcpAdapterInstaller implements AcpAdapterInstaller {
  const AntigravityAcpAdapterInstaller({this.storage, this.binary});

  /// Install-job target id (kept distinct from any `CliTool.value`).
  static const jobTarget = 'adapter:antigravity-acp';

  final HomeStorage? storage;
  final BinaryArchiveInstaller? binary;

  @override
  String get adapterJobTarget => jobTarget;

  @override
  String get executableName => _exeName();

  @override
  String get displayName => 'Antigravity ACP adapter';

  @override
  bool get supportsInstaller => true;

  String _installDir(HomeStorage s) => s.fs.pathContext.join(
    s.appDataRoot,
    'toolchain',
    'antigravity-acp',
    antigravityAcpVersion,
  );

  /// Probe 1.4.3: the adapter is a Dart `.par` on Unix and a `.exe` on Windows.
  String _exeName() =>
      Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par';

  /// Sidecar the adapter loads next to itself; `session/new` fails without it.
  String _sidecarName() => Platform.isWindows
      ? 'localharness_external.exe'
      : 'localharness_external';

  @override
  Future<String?> resolveInstalledPath() async {
    final s = storage;
    if (s == null) return null;
    final path = s.fs.pathContext.join(_installDir(s), _exeName());
    return (await s.fs.stat(path)).isFile ? path : null;
  }

  @override
  Future<String?> latestVersion() async => antigravityAcpVersion;

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    final s = storage;
    final installer = binary;
    if (s == null || installer == null) {
      return const CliInstallResult(
        success: false,
        message: 'Antigravity adapter installer is not configured.',
      );
    }
    if (context.mode == CliInstallMode.ssh) {
      return const CliInstallResult(
        success: false,
        message: 'Remote Antigravity adapter install is not available yet.',
      );
    }
    final asset = antigravityAcpAssetKey(
      os: context.host.isWindows
          ? 'windows'
          : (Platform.isMacOS ? 'darwin' : 'linux'),
      arch: Platform.version.contains('arm64') ? 'arm64' : 'x64',
    );
    context.host.report(CliInstallPhase.installingCli);
    final path = await installer.install(
      archiveUri: Uri.parse(antigravityAcpArchiveUrl(asset)),
      sha256: antigravityAcpSha256[asset]!,
      destDir: _installDir(s),
      executableName: _exeName(),
      // Probe 1.4.3: every platform needs the sidecar next to the .par.
      extraExecutables: [_sidecarName()],
      onProgress: (received, total) => context.host.report(
        CliInstallPhase.installingCli,
        detail: total == null ? '$received bytes' : '$received/$total',
      ),
      isCancelled: () => context.host.isCancelled,
    );
    return CliInstallResult(
      success: true,
      message: 'Antigravity ACP adapter installed.',
      executablePath: path,
    );
  }
}
