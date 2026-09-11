import 'package:acpd/acpd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_agent_translator.dart';
import 'package:teampilot/services/cli/gemini/capabilities/acp.dart';

void main() {
  const translator = GeminiAcpTranslator();

  test('flag candidates list acp then experimental-acp', () {
    expect(translator.flagCandidates, ['--acp', '--experimental-acp']);
  });

  test('aborted internal error with suppress → cancelled sentinel', () {
    final err = _FakeJsonRpcError(
      code: -32603,
      data: {'details': 'This operation was aborted'},
    );
    expect(
      translator.translateStopError(err, suppressAbort: true),
      acpStopCancelled,
    );
  });

  test('aborted internal error without suppress → surfaced error', () {
    final err = _FakeJsonRpcError(
      code: -32603,
      data: {'details': 'The user aborted a request'},
    );
    final out = translator.translateStopError(err, suppressAbort: false);
    expect(out, isNot(acpStopCancelled));
    expect(out, contains('-32603'));
  });

  test('non-aborted error passes through with code', () {
    final err = _FakeJsonRpcError(code: -32000, data: {'details': 'boom'});
    final out = translator.translateStopError(err, suppressAbort: true);
    expect(out, isNot(acpStopCancelled));
    expect(out, contains('boom'));
  });
}

/// Stands in for a wire-shaped JSON-RPC error using acpd's real [RpcError]
/// type (gemini-cli errors arrive with an unhelpful message; the abort hint
/// lives in `data.details`).
class _FakeJsonRpcError extends RpcError {
  _FakeJsonRpcError({required super.code, super.data}) : super(message: '');
}
