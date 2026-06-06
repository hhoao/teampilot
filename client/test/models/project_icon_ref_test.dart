import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_icon_ref.dart';

void main() {
  test('ProjectIconRef auto omits json', () {
    expect(ProjectIconRef.auto.toJson(), isNull);
  });

  test('ProjectIconRef preset roundtrips json', () {
    const icon = ProjectIconPreset(3);
    final json = icon.toJson() as Map<String, Object?>;
    expect(ProjectIconRef.fromJson(json), icon);
  });

  test('ProjectIconRef custom roundtrips json', () {
    const icon = ProjectIconCustom('icons/p.png');
    final json = icon.toJson() as Map<String, Object?>;
    expect(ProjectIconRef.fromJson(json), icon);
  });

  test('ProjectIconRef from missing json defaults to auto', () {
    expect(ProjectIconRef.fromJson(null), ProjectIconRef.auto);
  });
}
