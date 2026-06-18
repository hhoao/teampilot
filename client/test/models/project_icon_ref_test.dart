import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_icon_ref.dart';

void main() {
  test('WorkspaceIconRef auto omits json', () {
    expect(WorkspaceIconRef.auto.toJson(), isNull);
  });

  test('WorkspaceIconRef preset roundtrips json', () {
    const icon = WorkspaceIconPreset(3);
    final json = icon.toJson() as Map<String, Object?>;
    expect(WorkspaceIconRef.fromJson(json), icon);
  });

  test('WorkspaceIconRef custom roundtrips json', () {
    const icon = WorkspaceIconCustom('icons/p.png');
    final json = icon.toJson() as Map<String, Object?>;
    expect(WorkspaceIconRef.fromJson(json), icon);
  });

  test('WorkspaceIconRef from missing json defaults to auto', () {
    expect(WorkspaceIconRef.fromJson(null), WorkspaceIconRef.auto);
  });
}
