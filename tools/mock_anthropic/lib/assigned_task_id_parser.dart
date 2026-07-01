/// Extracts a claimed task id from an inbound Anthropic `/v1/messages` body.
///
/// L2 integration tests script `update_task` after `wait_for_message` returns
/// ASSIGNED TASK; the task id is only known at runtime from the tool result.
String? extractAssignedTaskIdFromAnthropicRequest(
  Map<String, Object?>? body,
) {
  if (body == null) return null;
  return _scanValue(body['messages']);
}

final _claimedTaskHeader = RegExp(
  r'---\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s*\[claimed\]',
  caseSensitive: false,
);

String? _scanValue(Object? value) {
  if (value is String) {
    if (!value.contains('ASSIGNED TASK')) return null;
    return _claimedTaskHeader.firstMatch(value)?.group(1);
  }
  if (value is List<Object?>) {
    for (final item in value) {
      final id = _scanValue(item);
      if (id != null) return id;
    }
    return null;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final id = _scanValue(entry.value);
      if (id != null) return id;
    }
  }
  return null;
}
