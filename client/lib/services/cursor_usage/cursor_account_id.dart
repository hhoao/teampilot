import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Cursor hashes the JWT `sub` into a stable account id; the same formula is
/// used by `CursorUsageAuthResolver` so discovered entries keep their identity
/// across restarts.
String cursorAccountIdFor(String sub) =>
    sha256.convert(utf8.encode(sub)).toString().substring(0, 16);
