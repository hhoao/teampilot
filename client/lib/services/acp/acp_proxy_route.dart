import 'dart:convert';

/// SSH exec stays in use. [reason] is a stable token, not user-facing copy.
const acpProxyRouteMissing = 'missing';
const acpProxyRouteUnreadable = 'unreadable';
const acpProxyRouteVersion = 'version';
const acpProxyRouteNoPort = 'no-port';
const acpProxyRouteNotListening = 'not-listening';
const acpProxyRouteProbeFailed = 'probe-failed';

/// How one remote ACP launch reaches the CLI.
sealed class AcpProxyRoute {
  const AcpProxyRoute();
}

/// Raw ACP over SSH `forwardLocal` to `127.0.0.1:[port]`.
final class AcpProxyForwardRoute extends AcpProxyRoute {
  const AcpProxyForwardRoute(this.port);

  final int port;
}

/// Today's SSH exec. This turn is not kept alive.
final class AcpProxyExecRoute extends AcpProxyRoute {
  const AcpProxyExecRoute(this.reason);

  final String reason;
}

/// Reads one `acp-proxy.json` body. Only schema v1 on `127.0.0.1` is accepted.
class AcpProxyAdvertisementView {
  const AcpProxyAdvertisementView({
    required this.version,
    required this.pid,
    required this.ports,
  });

  final String version;
  final int pid;
  final Map<String, int> ports;

  factory AcpProxyAdvertisementView.parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException(
        'acp-proxy advertisement must be a JSON object',
      );
    }
    final json = Map<String, Object?>.from(decoded);
    if (json['v'] != 1) {
      throw const FormatException('acp-proxy advertisement v must be 1');
    }
    if (json['bind'] != '127.0.0.1') {
      throw const FormatException(
        'acp-proxy advertisement bind must be 127.0.0.1',
      );
    }
    final version = json['version'];
    if (version is! String || version.isEmpty) {
      throw const FormatException(
        'acp-proxy advertisement version must be a string',
      );
    }
    final pid = json['pid'];
    if (pid is! int || pid <= 0) {
      throw const FormatException(
        'acp-proxy advertisement pid must be a positive int',
      );
    }
    final clis = json['clis'];
    if (clis is! Map) {
      throw const FormatException(
        'acp-proxy advertisement clis must be an object',
      );
    }
    final ports = <String, int>{};
    for (final entry in clis.entries) {
      final cli = entry.key;
      if (cli is! String || cli.isEmpty) {
        throw const FormatException(
          'acp-proxy advertisement cli id must be a non-empty string',
        );
      }
      final body = entry.value;
      if (body is! Map) {
        throw FormatException(
          'acp-proxy advertisement cli $cli must be an object',
        );
      }
      final port = body['port'];
      if (port is! int || port <= 0 || port > 65535) {
        throw FormatException(
          'acp-proxy advertisement cli $cli port must be a positive int',
        );
      }
      ports[cli] = port;
    }
    return AcpProxyAdvertisementView(version: version, pid: pid, ports: ports);
  }
}

/// Chooses forward vs exec for one CLI. Does not install or start anything.
///
/// A version other than [pinnedVersion] is exec even when [pidListening] is
/// true: an old proxy must not serve this app.
AcpProxyRoute decideAcpProxyRoute({
  required String? advertisementJson,
  required String pinnedVersion,
  required String cliId,
  required bool pidListening,
}) {
  final raw = advertisementJson?.trim() ?? '';
  if (raw.isEmpty) return const AcpProxyExecRoute(acpProxyRouteMissing);
  final AcpProxyAdvertisementView ad;
  try {
    ad = AcpProxyAdvertisementView.parse(raw);
  } on FormatException {
    return const AcpProxyExecRoute(acpProxyRouteUnreadable);
  }
  if (ad.version != pinnedVersion) {
    return const AcpProxyExecRoute(acpProxyRouteVersion);
  }
  final port = ad.ports[cliId];
  if (port == null) return const AcpProxyExecRoute(acpProxyRouteNoPort);
  if (!pidListening) {
    return const AcpProxyExecRoute(acpProxyRouteNotListening);
  }
  return AcpProxyForwardRoute(port);
}

/// Inode of a `127.0.0.1:[port]` TCP listener in `/proc/net/tcp`, if any.
///
/// Established sockets and other addresses are ignored. Linux prints the
/// loopback address as little-endian `0100007F`.
int? procNetTcpListenInode(String tcpTable, int port) {
  if (port <= 0 || port > 65535) return null;
  final local =
      '0100007F:${port.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  for (final line in tcpTable.split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 10) continue;
    if (fields[1].toUpperCase() != local) continue;
    if (fields[3].toUpperCase() != '0A') continue;
    return int.tryParse(fields[9]);
  }
  return null;
}

/// Whether [fdLinks] (`readlink` of `/proc/<pid>/fd/*`) includes [inode].
bool processFdLinksOwnSocket(Iterable<String> fdLinks, int inode) {
  final needle = 'socket:[$inode]';
  for (final link in fdLinks) {
    if (link.trim() == needle) return true;
  }
  return false;
}

/// Parsed remote probe. Empty advertisement means the file was absent.
class AcpProxyProbeSnapshot {
  const AcpProxyProbeSnapshot({
    required this.binaryPresent,
    required this.pidFile,
    required this.advertisementJson,
    required this.tcpTable,
    required this.advertisementFdLinks,
    required this.pidFileFdLinks,
  });

  final bool binaryPresent;
  final String pidFile;
  final String? advertisementJson;
  final String tcpTable;
  final List<String> advertisementFdLinks;
  final List<String> pidFileFdLinks;
}

/// Splits the remote probe script's marked sections.
AcpProxyProbeSnapshot parseAcpProxyProbe(String output) {
  final sections = _sections(output);
  final ad = sections['---ACP-PROXY-AD---']?.trim() ?? '';
  return AcpProxyProbeSnapshot(
    binaryPresent: (sections['---ACP-PROXY-BINARY---']?.trim() ?? '') == 'yes',
    pidFile: sections['---ACP-PROXY-PIDFILE---']?.trim() ?? '',
    advertisementJson: ad.isEmpty ? null : ad,
    tcpTable: sections['---ACP-PROXY-TCP---'] ?? '',
    advertisementFdLinks: _lines(sections['---ACP-PROXY-AD-FDS---']),
    pidFileFdLinks: _lines(sections['---ACP-PROXY-PID-FDS---']),
  );
}

/// Route decision from one probe. The advertised pid must own the CLI port.
AcpProxyRoute decideAcpProxyRouteFromProbe({
  required String output,
  required String pinnedVersion,
  required String cliId,
}) {
  final snapshot = parseAcpProxyProbe(output);
  final raw = snapshot.advertisementJson;
  if (raw == null) {
    return decideAcpProxyRoute(
      advertisementJson: null,
      pinnedVersion: pinnedVersion,
      cliId: cliId,
      pidListening: false,
    );
  }
  AcpProxyAdvertisementView? ad;
  try {
    ad = AcpProxyAdvertisementView.parse(raw);
  } on FormatException {
    ad = null;
  }
  final port = ad?.ports[cliId];
  final inode = port == null
      ? null
      : procNetTcpListenInode(snapshot.tcpTable, port);
  final listening =
      ad != null &&
      inode != null &&
      processFdLinksOwnSocket(snapshot.advertisementFdLinks, inode);
  return decideAcpProxyRoute(
    advertisementJson: raw,
    pinnedVersion: pinnedVersion,
    cliId: cliId,
    pidListening: listening,
  );
}

/// Positive pid from a pid file body, or null.
int? acpProxyPidFileValue(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final pid = int.tryParse(text);
  if (pid == null || pid <= 0) return null;
  return pid;
}

/// Whether [pidFile] owns a listen socket for every advertised CLI port.
///
/// Update refuses to signal a pid that is not the listener. A missing
/// advertisement or pid file is not listening.
bool acpProxyPidFileIsListening(AcpProxyProbeSnapshot snapshot) {
  final pid = acpProxyPidFileValue(snapshot.pidFile);
  final raw = snapshot.advertisementJson;
  if (pid == null || raw == null) return false;
  final AcpProxyAdvertisementView ad;
  try {
    ad = AcpProxyAdvertisementView.parse(raw);
  } on FormatException {
    return false;
  }
  if (ad.pid != pid || ad.ports.isEmpty) return false;
  for (final port in ad.ports.values) {
    final inode = procNetTcpListenInode(snapshot.tcpTable, port);
    if (inode == null) return false;
    if (!processFdLinksOwnSocket(snapshot.pidFileFdLinks, inode)) return false;
  }
  return true;
}

Map<String, String> _sections(String output) {
  const markers = [
    '---ACP-PROXY-BINARY---',
    '---ACP-PROXY-PIDFILE---',
    '---ACP-PROXY-AD---',
    '---ACP-PROXY-TCP---',
    '---ACP-PROXY-AD-FDS---',
    '---ACP-PROXY-PID-FDS---',
  ];
  final found = <String, int>{};
  for (final marker in markers) {
    final index = output.indexOf(marker);
    if (index >= 0) found[marker] = index;
  }
  final ordered = found.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final sections = <String, String>{};
  for (var i = 0; i < ordered.length; i++) {
    final start = ordered[i].value + ordered[i].key.length;
    final end = i + 1 < ordered.length ? ordered[i + 1].value : output.length;
    sections[ordered[i].key] = output.substring(start, end);
  }
  return sections;
}

List<String> _lines(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return [
    for (final line in raw.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
}
