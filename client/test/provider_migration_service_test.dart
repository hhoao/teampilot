import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider_migration_service.dart';

void main() {
  test('legacy provider migration is disabled', () async {
    final service = ProviderMigrationService();

    expect(await service.migrateIfNeeded(), isFalse);
  });
}
