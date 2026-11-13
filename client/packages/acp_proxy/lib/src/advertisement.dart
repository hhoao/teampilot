import 'dart:convert';
import 'dart:io';

const _schemaVersion = 1;
const _bind = '127.0.0.1';
const _fileName = 'acp-proxy.json';

/// Address file a phone reads before deciding to forward ACP over SSH.
///
/// Only schema v1 bound to `127.0.0.1` is accepted. Ports are the loopback
/// listeners for each CLI id.
class AcpProxyAdvertisement {
  const AcpProxyAdvertisement({
    required this.version,
    required this.pid,
    required this.ports,
  });

  final String version;
  final int pid;
  final Map<String, int> ports;

  factory AcpProxyAdvertisement.parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException(
        'acp-proxy advertisement must be a JSON object',
      );
    }
    final json = Map<String, Object?>.from(decoded);
    if (json['v'] is! int || json['v'] != _schemaVersion) {
      throw const FormatException('acp-proxy advertisement v must be 1');
    }
    if (json['bind'] != _bind) {
      throw const FormatException(
        'acp-proxy advertisement bind must be 127.0.0.1',
      );
    }
    final version = json['version'];
    if (version is! String) {
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
      if (port is! int || port <= 0) {
        throw FormatException(
          'acp-proxy advertisement cli $cli port must be a positive int',
        );
      }
      ports[cli] = port;
    }
    return AcpProxyAdvertisement(version: version, pid: pid, ports: ports);
  }
}

/// Advertisement file `<root>/acp-proxy.json`.
File acpProxyAdvertisementFile(Directory root) {
  return File('${root.path}/$_fileName');
}

/// Writes the advertisement by renaming `acp-proxy.json.tmp` over the file.
Future<void> writeAcpProxyAdvertisement(
  Directory root,
  AcpProxyAdvertisement ad,
) async {
  final destination = acpProxyAdvertisementFile(root);
  final temporary = File('${destination.path}.tmp');
  final encoded = jsonEncode({
    'v': _schemaVersion,
    'version': ad.version,
    'bind': _bind,
    'pid': ad.pid,
    'clis': {
      for (final entry in ad.ports.entries) entry.key: {'port': entry.value},
    },
  });
  await temporary.writeAsString(encoded, flush: true);
  await temporary.rename(destination.path);
}
