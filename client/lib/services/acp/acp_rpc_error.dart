import 'package:acpd/acpd.dart';

/// Canonical JSON-RPC 2.0 messages that carry no agent-specific reason.
const _genericJsonRpcMessages = {
  'Parse error',
  'Invalid Request',
  'Method not found',
  'Invalid params',
  'Internal error',
};

/// Human-readable reason from [error], preferring nested `data` over the
/// generic JSON-RPC [RpcError.message].
///
/// Cursor puts the useful text in `data.message`; Gemini uses `data.details`.
/// Returns null when nothing more specific than "Internal error" is present.
String? acpRpcErrorUserDetail(RpcError error) {
  final fromData = _detailFromData(error.data);
  if (fromData != null && !_isGenericJsonRpcMessage(fromData)) {
    return fromData;
  }
  final message = error.message.trim();
  if (message.isEmpty || _isGenericJsonRpcMessage(message)) return null;
  return message;
}

/// Localized [prefix] plus optional agent [detail], stripping trailing
/// sentence punctuation from the prefix so EN period / ZH `。` do not sit
/// in front of a colon.
String acpSessionOpenFailedCopy({required String prefix, String? detail}) {
  final reason = detail?.trim() ?? '';
  if (reason.isEmpty) return prefix;
  final base = prefix.trim().replaceFirst(RegExp(r'[。.]+$'), '');
  return '$base: $reason';
}

bool _isGenericJsonRpcMessage(String text) =>
    _genericJsonRpcMessages.contains(text.trim());

String? _detailFromData(Object? data) {
  if (data == null) return null;
  if (data is String) {
    final trimmed = data.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (data is Map) {
    for (final key in const ['message', 'details', 'reason', 'error']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    final nested = data['error'];
    if (nested is Map) return _detailFromData(nested);
  }
  return null;
}
