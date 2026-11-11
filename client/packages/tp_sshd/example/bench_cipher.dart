// Benchmark: OpenSSH ChaCha20-Poly1305 packet cost — the transport's
// per-packet crypto, isolated from sockets and SFTP.
//
// OpenSSHChaCha20Poly1305 is fully backed by the libcrypto FFI shim
// (dartssh2 native/tp_sshd_crypto.c via NativeCrypto), so this measures
// the FFI path end to end (FFI crossing + EVP ChaCha20 + donna Poly1305).
//
// Historical pure-Dart (PointyCastle) baseline, measured 2026-09-10
// before the swap: ~40 MB/s on 4 KiB packets, ~58 MB/s on 32 KiB packets.
// Acceptance target for the FFI path: >= 500 MB/s on 32 KiB packets.
library;

import 'dart:typed_data';

import 'package:dartssh2/src/utils/openssh_chacha20_poly1305.dart';

Future<void> main() async {
  final cipher = OpenSSHChaCha20Poly1305(
    Uint8List.fromList(List.generate(64, (i) => i)),
  );

  // The wire packet size the transport actually moves bulk data with:
  // payload up to 32 KiB + length/padding header.
  for (final size in [4 * 1024, 32 * 1024]) {
    final packet = Uint8List(size + 16);

    // JIT warmup.
    for (var i = 0; i < 100; i++) {
      cipher.encryptPacket(packet, i);
    }

    const rounds = 3000;
    final watch = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      cipher.encryptPacket(packet, i);
    }
    watch.stop();

    final seconds = watch.elapsedMicroseconds / 1e6;
    final mbps = (rounds * packet.length / 1e6) / seconds;
    print(
      'encrypt ${size ~/ 1024} KiB packets: ${mbps.toStringAsFixed(1)} MB/s '
      '(${(watch.elapsedMicroseconds / rounds).toStringAsFixed(1)} µs/packet)',
    );
  }
}
