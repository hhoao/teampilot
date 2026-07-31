import 'termux_remote_detect.dart';

/// How to obtain a working `npm` on a remote Unix host when none is on PATH.
///
/// Strategies are composed in order by [UnixNodeBootstrapComposer]: each may
/// early-exit with status 0 when it fully handles the host.
abstract interface class UnixNodeBootstrapStrategy {
  /// POSIX shell body (no shebang). May `exit 0` when this strategy applies.
  String buildScript();
}

/// Termux / Android: use `pkg install nodejs` (bionic). Official glibc Node
/// tarballs and `tar -xJf` (needs xz) fail on this platform.
final class TermuxPkgNodeBootstrap implements UnixNodeBootstrapStrategy {
  const TermuxPkgNodeBootstrap();

  @override
  String buildScript() =>
      '''
${TermuxRemoteDetect.ensurePrefixAndFlagShell}
if [ "\$is_termux" -eq 1 ]; then
  ${TermuxRemoteDetect.exportPrefixPathShell}
  if ! command -v npm >/dev/null 2>&1; then
    echo "Installing Node.js via Termux pkg (official Node builds are not compatible with Android)..." >&2
    if ! command -v pkg >/dev/null 2>&1; then
      echo "Termux pkg not found. Open Termux and run: pkg install nodejs" >&2
      exit 5
    fi
    pkg install -y nodejs
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm still not found after pkg install nodejs" >&2
    exit 5
  fi
  npm_path="\$(command -v npm)"
  node_path="\$(command -v node)"
  npx_path="\$(command -v npx 2>/dev/null || true)"
  ln -sfn "\$npm_path" "\$HOME/.local/bin/npm"
  ln -sfn "\$node_path" "\$HOME/.local/bin/node"
  if [ -n "\$npx_path" ]; then
    ln -sfn "\$npx_path" "\$HOME/.local/bin/npx"
  fi
  npm --version
  exit 0
fi
''';
}

/// Download official (or legacy glibc-2.17) Node tarball into TeamPilot toolchain.
final class GlibcNodeTarballBootstrap implements UnixNodeBootstrapStrategy {
  const GlibcNodeTarballBootstrap({
    required this.version,
    required this.legacyGlibcVersion,
    required this.toolchainBase,
  });

  final String version;
  final String legacyGlibcVersion;
  final String toolchainBase;

  @override
  String buildScript() {
    final base = toolchainBase;
    return '''
glibc_major=""
glibc_minor=""
if [ "\$platform" = "linux" ]; then
  glibc_line="\$(ldd --version 2>&1 | head -n 1 || true)"
  glibc_major="\$(printf '%s\\n' "\$glibc_line" | sed -n 's/.* \\([0-9][0-9]*\\)\\.\\([0-9][0-9]*\\).*/\\1/p')"
  glibc_minor="\$(printf '%s\\n' "\$glibc_line" | sed -n 's/.* \\([0-9][0-9]*\\)\\.\\([0-9][0-9]*\\).*/\\2/p')"
fi

use_glibc217=0
version="$version"
dist_kind="official"
if [ "\$platform" = "linux" ] && [ "\$node_arch" = "x64" ]; then
  if [ -z "\$glibc_major" ] || [ -z "\$glibc_minor" ] \\
    || [ "\$glibc_major" -lt 2 ] \\
    || { [ "\$glibc_major" -eq 2 ] && [ "\$glibc_minor" -lt 28 ]; }
  then
    use_glibc217=1
    version="$legacyGlibcVersion"
    dist_kind="unofficial-glibc-217"
    echo "Host glibc \${glibc_major:-?}.\${glibc_minor:-?} < 2.28; using Node \$version (glibc-217 build)" >&2
  fi
fi

base="$base"
target="\$base/\$version"
if [ "\$use_glibc217" -eq 1 ]; then
  archive="node-\$version-linux-x64-glibc-217.tar.xz"
  extract_dir="node-\$version-linux-x64-glibc-217"
else
  archive="node-\$version-\$platform-\$node_arch.tar.xz"
  extract_dir="node-\$version-\$platform-\$node_arch"
fi
mkdir -p "\$base"
tmp="\$(mktemp -d)"
cleanup() { rm -rf "\$tmp"; }
trap cleanup EXIT
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "curl or wget is required to download Node.js" >&2
  exit 3
fi
download_ok=0
if [ "\$use_glibc217" -eq 1 ]; then
  urls="https://unofficial-builds.nodejs.org/download/release/\$version/\$archive"
else
  urls="https://nodejs.org/dist/\$version/\$archive https://npmmirror.com/mirrors/node/\$version/\$archive"
fi
for url in \$urls
do
  for attempt in 1 2 3 4 5; do
    echo "Downloading Node.js from \$url (attempt \$attempt)" >&2
    rm -f "\$tmp/\$archive"
    if command -v curl >/dev/null 2>&1; then
      if curl -fsSL --connect-timeout 30 --max-time 600 \\
        "\$url" -o "\$tmp/\$archive"; then
        download_ok=1
        break
      fi
    else
      if wget -q --timeout=30 -O "\$tmp/\$archive" "\$url"; then
        download_ok=1
        break
      fi
    fi
    sleep 2
  done
  if [ "\$download_ok" -eq 1 ]; then
    break
  fi
done
if [ "\$download_ok" -ne 1 ]; then
  echo "Failed to download Node.js archive after retries (\$dist_kind)" >&2
  exit 18
fi
tar -xJf "\$tmp/\$archive" -C "\$tmp"
rm -rf "\$target"
mv "\$tmp/\$extract_dir" "\$target"
if ! "\$target/bin/node" --version >/dev/null 2>&1; then
  echo "Bootstrapped Node binary is not runnable on this host:" >&2
  "\$target/bin/node" --version >&2 || true
  rm -rf "\$target"
  exit 4
fi
ln -sfn "\$target" "\$base/current"
ln -sfn "\$target/bin/node" "\$HOME/.local/bin/node"
ln -sfn "\$target/bin/npm" "\$HOME/.local/bin/npm"
ln -sfn "\$target/bin/npx" "\$HOME/.local/bin/npx"
PATH="\$target/bin:\$HOME/.local/bin:\$PATH" npm --version
''';
  }
}

/// Builds the full remote/local Unix Node bootstrap script from strategies.
abstract final class UnixNodeBootstrapComposer {
  UnixNodeBootstrapComposer._();

  static String compose({
    required String version,
    required String legacyGlibcVersion,
    required String toolchainBase,
    List<UnixNodeBootstrapStrategy>? strategies,
  }) {
    final ordered =
        strategies ??
        [
          const TermuxPkgNodeBootstrap(),
          GlibcNodeTarballBootstrap(
            version: version,
            legacyGlibcVersion: legacyGlibcVersion,
            toolchainBase: toolchainBase,
          ),
        ];

    final body = ordered.map((s) => s.buildScript()).join('\n');
    return '''
set -e
os="\$(uname -s)"
arch="\$(uname -m)"
case "\$os" in
  Linux) platform="linux" ;;
  Darwin) platform="darwin" ;;
  *) echo "Unsupported OS: \$os" >&2; exit 2 ;;
esac
case "\$arch" in
  x86_64|amd64) node_arch="x64" ;;
  aarch64|arm64) node_arch="arm64" ;;
  *) echo "Unsupported architecture: \$arch" >&2; exit 2 ;;
esac

mkdir -p "\$HOME/.local/bin"

$body
''';
  }
}
