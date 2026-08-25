import 'dart:convert';
import 'dart:math';

class PairingTokenGate {
  String? _token;
  DateTime? _expiresAt;
  var _used = false;

  String mint({
    required DateTime now,
    Duration ttl = const Duration(minutes: 10),
  }) {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    _token = base64Url.encode(bytes).replaceAll('=', '');
    _expiresAt = now.add(ttl);
    _used = false;
    return _token!;
  }

  bool consume(String token, DateTime now) {
    final expected = _token;
    final expiry = _expiresAt;
    if (expected == null || expiry == null || _used || now.isAfter(expiry)) {
      return false;
    }
    if (!_constantTimeEquals(expected, token)) return false;
    _used = true;
    return true;
  }

  void invalidate() {
    _token = null;
    _expiresAt = null;
    _used = true;
  }

  bool get hasActiveToken => _token != null && _expiresAt != null && !_used;
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
