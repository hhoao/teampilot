import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_rpc_error.dart';

void main() {
  test('prefers data.message over generic Internal error', () {
    const error = RpcError(
      code: -32603,
      message: 'Internal error',
      data: {'message': 'Failed to initialize session services'},
    );
    expect(
      acpRpcErrorUserDetail(error),
      'Failed to initialize session services',
    );
  });

  test('reads Gemini-shaped data.details', () {
    const error = RpcError(
      code: -32603,
      message: 'Internal error',
      data: {'details': 'model overloaded'},
    );
    expect(acpRpcErrorUserDetail(error), 'model overloaded');
  });

  test('uses specific RpcError.message when data is empty', () {
    const error = RpcError(code: -32000, message: 'auth required');
    expect(acpRpcErrorUserDetail(error), 'auth required');
  });

  test('returns null for generic Internal error with no data', () {
    const error = RpcError(code: -32603, message: 'Internal error');
    expect(acpRpcErrorUserDetail(error), isNull);
  });

  test('appends detail to localized prefix', () {
    expect(
      acpSessionOpenFailedCopy(
        prefix: "Couldn't open the Cursor session.",
        detail: 'Failed to initialize session services',
      ),
      "Couldn't open the Cursor session: Failed to initialize session services",
    );
    expect(
      acpSessionOpenFailedCopy(
        prefix: '无法打开 Cursor 会话。',
        detail: 'Failed to initialize session services',
      ),
      '无法打开 Cursor 会话: Failed to initialize session services',
    );
  });

  test('keeps prefix when detail is missing', () {
    expect(
      acpSessionOpenFailedCopy(
        prefix: "Couldn't open the Cursor session.",
        detail: null,
      ),
      "Couldn't open the Cursor session.",
    );
  });
}
