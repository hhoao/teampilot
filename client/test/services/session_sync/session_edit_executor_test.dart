import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session_sync/session_edit_executor.dart';

void main() {
  test('delegates only to a connected client that owns the seat', () {
    expect(
      resolveEditExecutor(isClient: true, authorityOwnsSeat: true),
      EditExecutor.authority,
    );
    expect(
      resolveEditExecutor(isClient: true, authorityOwnsSeat: false),
      EditExecutor.local,
      reason: 'a phone-owned SSH seat has no desktop runtime to rewind',
    );
    expect(
      resolveEditExecutor(isClient: false, authorityOwnsSeat: true),
      EditExecutor.local,
    );
    expect(
      resolveEditExecutor(isClient: false, authorityOwnsSeat: false),
      EditExecutor.local,
    );
  });
}
