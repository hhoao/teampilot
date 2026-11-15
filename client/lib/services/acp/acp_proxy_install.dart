import '../cli/installer_types.dart';
import '../cli/registry/capabilities/acp_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'acp_proxy_route.dart';

/// Must match `acpProxyVersion` in `client/packages/acp_proxy`.
const acpProxyPinnedVersion = '0.1.0';

const acpProxyReleaseRepository = 'hhoao/teampilot';

/// SHA-256 of the published Linux binaries.
///
/// `x86_64` is the local `dart compile exe` of
/// `client/packages/acp_proxy/bin/teampilot_acp_proxy.dart`. `aarch64` is
/// omitted until an arm build exists. The installer refuses that download
/// instead of trusting an unpinned file.
const acpProxySha256 = <String, String>{
  'x86_64': '0ac627d599cd7ebae39f92e947c41ec51c57d4c68b0ea6768f1a38f5987b29b7',
};

/// CLI ids the detached proxy should listen for, in registry order.
List<String> acpProxyCliIds(CliToolRegistry registry) => [
  for (final definition in registry.withCapability<AcpCapability>())
    definition.id.value,
];

String acpProxyAssetName(String arch) => 'teampilot-acp-proxy-linux-$arch';

String acpProxyAssetUrl({required String version, required String arch}) {
  _requireVersion(version);
  _requireArch(arch);
  return 'https://github.com/$acpProxyReleaseRepository/releases/download/'
      'acp-proxy-v$version/${acpProxyAssetName(arch)}';
}

/// Remote machine card. Install, update, and start are explicit.
enum AcpProxyCardAction { install, update, start, ready }

/// Binary missing → install. Any published version other than the pin →
/// update. Not listening → start. Otherwise the proxy is the one this app
/// will forward to.
AcpProxyCardAction acpProxyCardAction({
  required bool binaryPresent,
  required String? advertisedVersion,
  required String pinnedVersion,
  required bool pidListening,
}) {
  if (!binaryPresent) return AcpProxyCardAction.install;
  if (advertisedVersion != null && advertisedVersion != pinnedVersion) {
    return AcpProxyCardAction.update;
  }
  if (!pidListening) return AcpProxyCardAction.start;
  return AcpProxyCardAction.ready;
}

AcpProxyCardAction acpProxyCardActionForProbe(
  AcpProxyProbeSnapshot snapshot, {
  String pinnedVersion = acpProxyPinnedVersion,
}) {
  String? version;
  final raw = snapshot.advertisementJson;
  if (raw != null) {
    try {
      version = AcpProxyAdvertisementView.parse(raw).version;
    } on FormatException {
      version = '';
    }
  }
  return acpProxyCardAction(
    binaryPresent: snapshot.binaryPresent,
    advertisedVersion: version,
    pinnedVersion: pinnedVersion,
    pidListening: acpProxyPidFileIsListening(snapshot),
  );
}

/// Prints the address file, pid file, TCP table, and the pid's socket links.
///
/// The phone parses this in Dart. The remote shell does not decide the route.
String acpProxyProbeScript() => r'''
set -eu
root="$HOME/.local/share/teampilot"
bin="$root/acp-proxy/teampilot-acp-proxy"
pidfile="$root/acp-proxy/acp-proxy.pid"
ad="$root/acp-proxy.json"
printf '%s\n' '---ACP-PROXY-BINARY---'
if [ -f "$bin" ]; then printf '%s\n' yes; else printf '%s\n' no; fi
printf '%s\n' '---ACP-PROXY-PIDFILE---'
if [ -f "$pidfile" ]; then cat "$pidfile"; fi
printf '%s\n' '---ACP-PROXY-AD---'
if [ -f "$ad" ]; then cat "$ad"; fi
printf '%s\n' '---ACP-PROXY-TCP---'
if [ -r /proc/net/tcp ]; then cat /proc/net/tcp; fi
list_fds() {
  pid="$1"
  if [ -z "$pid" ] || [ ! -d "/proc/$pid/fd" ]; then
    return 0
  fi
  for fd in /proc/"$pid"/fd/*; do
    readlink "$fd" 2>/dev/null || true
  done
}
ad_pid=""
if [ -f "$ad" ]; then
  ad_pid=$(sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ad" | head -n 1)
fi
file_pid=""
if [ -f "$pidfile" ]; then
  file_pid=$(tr -d '[:space:]' < "$pidfile")
fi
printf '%s\n' '---ACP-PROXY-AD-FDS---'
list_fds "$ad_pid"
printf '%s\n' '---ACP-PROXY-PID-FDS---'
list_fds "$file_pid"
''';

/// Download, check SHA-256, place the binary, then `--detach` with one
/// `--cli` per id. Other architectures fail before `curl`.
String buildAcpProxyInstallScript({
  required List<String> cliIds,
  String version = acpProxyPinnedVersion,
  Map<String, String> sha256ByArch = acpProxySha256,
}) {
  return '''
set -eu
arch=\$(uname -m)
case "\$arch" in
${_archBranch('x86_64', version: version, sha256ByArch: sha256ByArch)}
${_archBranch('aarch64', version: version, sha256ByArch: sha256ByArch)}
  *)
    echo "unsupported architecture: \$arch" >&2
    exit 1
    ;;
esac
${_placeBinaryShell()}
${_launchShell(cliIds)}
''';
}

/// Stops only `acp-proxy.pid`. A different listener fails the update and is
/// left running. Then the binary is replaced and the proxy is started again.
String buildAcpProxyUpdateScript({
  required List<String> cliIds,
  String version = acpProxyPinnedVersion,
  Map<String, String> sha256ByArch = acpProxySha256,
}) {
  return '''
set -eu
root="\$HOME/.local/share/teampilot"
pidfile="\$root/acp-proxy/acp-proxy.pid"
ad="\$root/acp-proxy.json"
expected=""
if [ -f "\$pidfile" ]; then
  expected=\$(tr -d '[:space:]' < "\$pidfile")
fi
if [ -f "\$ad" ] && [ -r /proc/net/tcp ]; then
  ports=\$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p' "\$ad")
  for port in \$ports; do
    hex=\$(printf '%04X' "\$port")
    want="0100007F:\$hex"
    inode=\$(awk -v want="\$want" '\$2==want && \$4=="0A" {print \$10; exit}' /proc/net/tcp)
    if [ -z "\$inode" ]; then
      continue
    fi
    listener=""
    for fd in /proc/[0-9]*/fd/*; do
      link=\$(readlink "\$fd" 2>/dev/null || true)
      if [ "\$link" = "socket:[\$inode]" ]; then
        listener=\${fd#/proc/}
        listener=\${listener%%/*}
        break
      fi
    done
    if [ -n "\$listener" ] && [ "\$listener" != "\$expected" ]; then
      echo "port listener \$listener is not acp-proxy.pid \$expected" >&2
      exit 1
    fi
  done
fi
if [ -n "\$expected" ] && [ -d "/proc/\$expected" ]; then
  kill -TERM "\$expected"
  i=0
  while [ -d "/proc/\$expected" ] && [ "\$i" -lt 20 ]; do
    sleep 1
    i=\$((i + 1))
  done
  if [ -d "/proc/\$expected" ]; then
    echo "pid \$expected did not exit" >&2
    exit 1
  fi
fi
arch=\$(uname -m)
case "\$arch" in
${_archBranch('x86_64', version: version, sha256ByArch: sha256ByArch)}
${_archBranch('aarch64', version: version, sha256ByArch: sha256ByArch)}
  *)
    echo "unsupported architecture: \$arch" >&2
    exit 1
    ;;
esac
${_placeBinaryShell()}
${_launchShell(cliIds)}
''';
}

/// Starts the binary already on disk. Does not download.
String buildAcpProxyStartScript({required List<String> cliIds}) {
  final launch = _launchShell(cliIds);
  return '''
set -eu
root="\$HOME/.local/share/teampilot"
bin="\$root/acp-proxy/teampilot-acp-proxy"
if [ ! -f "\$bin" ]; then
  echo 'acp proxy binary is missing' >&2
  exit 1
fi
chmod +x "\$bin"
$launch
''';
}

/// Stops the pid file's process and deletes the proxy directory and address
/// file. Session end does not call this.
String buildAcpProxyRemoveScript() => r'''
set -eu
root="$HOME/.local/share/teampilot"
pidfile="$root/acp-proxy/acp-proxy.pid"
if [ -f "$pidfile" ]; then
  pid=$(tr -d '[:space:]' < "$pidfile")
  if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
    kill -TERM "$pid" || true
    i=0
    while [ -d "/proc/$pid" ] && [ "$i" -lt 20 ]; do
      sleep 1
      i=$((i + 1))
    done
  fi
fi
rm -rf "$root/acp-proxy"
rm -f "$root/acp-proxy.json"
''';

enum AcpProxyRemoteAction { install, update, start, remove }

/// Runs one proxy maintenance script over the caller's SSH runner.
class AcpProxyRemoteInstaller {
  const AcpProxyRemoteInstaller({
    required this.cliIds,
    this.version = acpProxyPinnedVersion,
    this.sha256ByArch = acpProxySha256,
  });

  final List<String> cliIds;
  final String version;
  final Map<String, String> sha256ByArch;

  Future<CliInstallResult> run(
    AcpProxyRemoteAction action,
    Future<CliInstallerCommandResult> Function(String script) execute, {
    void Function(CliInstallPhase phase)? report,
  }) async {
    final script = switch (action) {
      AcpProxyRemoteAction.install => buildAcpProxyInstallScript(
        cliIds: cliIds,
        version: version,
        sha256ByArch: sha256ByArch,
      ),
      AcpProxyRemoteAction.update => buildAcpProxyUpdateScript(
        cliIds: cliIds,
        version: version,
        sha256ByArch: sha256ByArch,
      ),
      AcpProxyRemoteAction.start => buildAcpProxyStartScript(cliIds: cliIds),
      AcpProxyRemoteAction.remove => buildAcpProxyRemoveScript(),
    };
    report?.call(
      action == AcpProxyRemoteAction.start
          ? CliInstallPhase.locatingExecutable
          : CliInstallPhase.downloading,
    );
    final result = await execute(script);
    if (result.exitCode != 0) {
      final detail = result.stderr.trim().isEmpty
          ? result.stdout.trim()
          : result.stderr.trim();
      return CliInstallResult(
        success: false,
        message: detail.isEmpty ? 'ACP proxy ${action.name} failed.' : detail,
      );
    }
    report?.call(CliInstallPhase.locatingExecutable);
    return CliInstallResult(
      success: true,
      message: 'ACP proxy ${action.name} finished.',
    );
  }
}

String _archBranch(
  String arch, {
  required String version,
  required Map<String, String> sha256ByArch,
}) {
  final sha = sha256ByArch[arch];
  final pinned = sha != null && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha);
  if (!pinned) {
    return '''
  $arch)
    echo 'checksum is not pinned for $arch' >&2
    exit 1
    ;;''';
  }
  final url = acpProxyAssetUrl(version: version, arch: arch);
  return '''
  $arch)
    url='$url'
    sha='$sha'
    ;;''';
}

String _placeBinaryShell() => r'''
if [ "${#sha}" -ne 64 ]; then
  echo "checksum is not pinned for $arch" >&2
  exit 1
fi
command -v curl >/dev/null 2>&1 || { echo 'curl is required' >&2; exit 1; }
root="$HOME/.local/share/teampilot"
dir="$root/acp-proxy"
mkdir -p "$dir"
tmp=$(mktemp "$dir/teampilot-acp-proxy.XXXXXX")
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp"
if command -v sha256sum >/dev/null 2>&1; then
  echo "$sha  $tmp" | sha256sum -c -
elif command -v shasum >/dev/null 2>&1; then
  echo "$sha  $tmp" | shasum -a 256 -c -
else
  echo 'sha256sum or shasum is required' >&2
  exit 1
fi
chmod +x "$tmp"
bin="$dir/teampilot-acp-proxy"
mv -f "$tmp" "$bin"
trap - EXIT
''';

String _launchShell(List<String> cliIds) {
  if (cliIds.isEmpty) {
    throw ArgumentError('ACP proxy launch needs at least one --cli');
  }
  final flags = <String>[];
  for (final id in cliIds) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(id)) {
      throw FormatException('unsafe cli id: $id');
    }
    flags.add("--cli '$id'");
  }
  return '''
"\$bin" --root "\$root" --detach ${flags.join(' ')}
''';
}

void _requireVersion(String version) {
  if (!RegExp(r'^[0-9]+(\.[0-9]+)*$').hasMatch(version)) {
    throw FormatException('unsafe acp proxy version: $version');
  }
}

void _requireArch(String arch) {
  if (arch != 'x86_64' && arch != 'aarch64') {
    throw FormatException('unsupported acp proxy arch: $arch');
  }
}
