import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider_usage/adapters/official_subscription_parse.dart';

void main() {
  test('formatOfficialPercent rounds to at most one decimal place', () {
    expect(formatOfficialPercent(70), '70');
    expect(formatOfficialPercent(70.5), '70.5');
    expect(formatOfficialPercent(70.04), '70');
    expect(formatOfficialPercent(70.05), '70.1');
    expect(formatOfficialPercent(29.999999999999994), '30');
    expect(formatOfficialPercent(0.123456789), '0.1');
  });
}
