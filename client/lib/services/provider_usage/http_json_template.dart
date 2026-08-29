import 'dart:convert';

/// Expands `{name}` and `{jwt.sub}` placeholders for http-json credential values.
String expandHttpJsonTemplate(String template, Map<String, String> values) {
  final expanded = template.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (match) {
    final name = match.group(1)!;
    if (name == 'jwt.sub') {
      return _jwtSub(values['accessToken']) ?? '';
    }
    return values[name] ?? '';
  });
  return _normalizeColons(expanded);
}

/// Fills missing or empty [accountId] from the JWT `sub` claim in [accessToken].
Map<String, String> fillAccountIdFromJwt(Map<String, String> values) {
  final accountId = values['accountId'];
  if (accountId != null && accountId.isNotEmpty) {
    return Map<String, String>.from(values);
  }
  final sub = _jwtSub(values['accessToken']);
  if (sub == null || sub.isEmpty) {
    return Map<String, String>.from(values);
  }
  return {...values, 'accountId': sub};
}

String _normalizeColons(String value) {
  var result = value.replaceAll(RegExp(r'=:+'), '=');
  result = result.replaceFirst(RegExp(r'^:+'), '');
  result = result.replaceFirst(RegExp(r':+$'), '');
  return result;
}

String? _jwtSub(String? accessToken) {
  if (accessToken == null || accessToken.isEmpty) {
    return null;
  }
  final parts = accessToken.split('.');
  if (parts.length < 2) {
    return null;
  }
  try {
    final payloadJson = utf8.decode(
      base64Url.decode(_padBase64Url(parts[1])),
    );
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    final sub = payload['sub'];
    if (sub is! String || sub.isEmpty) {
      return null;
    }
    final pipe = sub.lastIndexOf('|');
    return pipe >= 0 ? sub.substring(pipe + 1) : sub;
  } catch (_) {
    return null;
  }
}

String _padBase64Url(String input) {
  final mod = input.length % 4;
  if (mod == 0) {
    return input;
  }
  return input + '=' * (4 - mod);
}
