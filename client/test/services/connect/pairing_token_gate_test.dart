import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/pairing_token_gate.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);

  test('mints a single-use base64url token', () {
    final gate = PairingTokenGate();
    final token = gate.mint(now: now);

    expect(token, hasLength(43));
    expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(gate.consume(token, now), isTrue);
    expect(gate.consume(token, now), isFalse);
  });

  test('rejects expired, invalidated, and superseded tokens', () {
    final gate = PairingTokenGate();
    final first = gate.mint(now: now, ttl: const Duration(minutes: 1));
    expect(gate.consume(first, now.add(const Duration(minutes: 2))), isFalse);

    final second = gate.mint(now: now);
    gate.invalidate();
    expect(gate.consume(second, now), isFalse);

    final old = gate.mint(now: now);
    final latest = gate.mint(now: now);
    expect(gate.consume(old, now), isFalse);
    expect(gate.consume(latest, now), isTrue);
  });
}
