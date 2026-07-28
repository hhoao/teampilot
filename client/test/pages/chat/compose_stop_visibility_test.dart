import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/compose_stop_visibility.dart';

void main() {
  test('shouldShowComposeStop requires working and support', () {
    expect(
      shouldShowComposeStop(
        memberWorking: true,
        supportsTurnInterrupt: true,
      ),
      isTrue,
    );
    expect(
      shouldShowComposeStop(
        memberWorking: false,
        supportsTurnInterrupt: true,
      ),
      isFalse,
    );
    expect(
      shouldShowComposeStop(
        memberWorking: true,
        supportsTurnInterrupt: false,
      ),
      isFalse,
    );
  });
}
