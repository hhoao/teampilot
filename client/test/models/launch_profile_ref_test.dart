import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_profile_ref.dart';

void main() {
  test('encode/decode a bare identity id', () {
    const li = LaunchProfileRef('coding');
    expect(li.encode(), 'coding');
    expect(LaunchProfileRef.decode('coding'), li);
  });

  test('decode trims and rejects empty', () {
    expect(LaunchProfileRef.decode('  squad '), const LaunchProfileRef('squad'));
    expect(LaunchProfileRef.decode(''), isNull);
    expect(LaunchProfileRef.decode(null), isNull);
  });
}
