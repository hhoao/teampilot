import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/compose_stop_visibility.dart';

void main() {
  test('shouldShowComposeStop requires working and support', () {
    expect(
      shouldShowComposeStop(
        memberWorking: true,
        supportsTurnInterrupt: true,
        composeTextEmpty: true,
      ),
      isTrue,
    );
    expect(
      shouldShowComposeStop(
        memberWorking: false,
        supportsTurnInterrupt: true,
        composeTextEmpty: true,
      ),
      isFalse,
    );
    expect(
      shouldShowComposeStop(
        memberWorking: true,
        supportsTurnInterrupt: false,
        composeTextEmpty: true,
      ),
      isFalse,
    );
  });

  test('shouldShowComposeStop requires empty text', () {
    expect(
      shouldShowComposeStop(
        memberWorking: true,
        supportsTurnInterrupt: true,
        composeTextEmpty: false,
      ),
      isFalse,
    );
    expect(
      shouldShowComposeStop(
        memberWorking: true,
        supportsTurnInterrupt: true,
        composeTextEmpty: true,
      ),
      isTrue,
    );
  });

  test('shouldShowComposeStop hides once the user stopped even if still working', () {
    expect(
      shouldShowComposeStop(
        memberWorking: true,
        supportsTurnInterrupt: true,
        composeTextEmpty: true,
        userStoppedTurn: true,
      ),
      isFalse,
    );
  });

  test('shouldShowComposeStop shows during starting even when not working yet', () {
    expect(
      shouldShowComposeStop(
        memberWorking: false,
        supportsTurnInterrupt: true,
        composeTextEmpty: true,
        turnStarting: true,
      ),
      isTrue,
    );
    expect(
      shouldShowComposeStop(
        memberWorking: false,
        supportsTurnInterrupt: true,
        composeTextEmpty: true,
        turnStarting: true,
        userStoppedTurn: true,
      ),
      isFalse,
    );
  });
}
