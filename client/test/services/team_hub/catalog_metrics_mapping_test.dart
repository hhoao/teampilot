import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_team.dart';

void main() {
  test('maps and round-trips team catalog metrics', () {
    final team = DiscoverableTeam.fromJson(const {
      'key': 'acme/teams/research',
      'name': 'Research',
      'description': 'Research team',
      'category': 'Research',
      'updatedAt': 1700000000000,
      'metrics': {
        'adoptionCount': 1200,
        'rating': 4.75,
        'ratingCount': 42,
        'updatedAtMs': 1700000000001,
        'publishedAtMs': 1690000000000,
      },
    });

    expect(team.metrics.adoptionCount, 1200);
    expect(team.metrics.rating, 4.75);
    expect(team.metrics.ratingCount, 42);
    expect(team.metrics.updatedAtMs, 1700000000001);
    expect(team.metrics.publishedAtMs, 1690000000000);
    expect(
      DiscoverableTeam.fromJson(team.toJson()).metrics.adoptionCount,
      1200,
    );
  });

  test(
    'omitted team metrics preserve missing values instead of local counts',
    () {
      final team = DiscoverableTeam.fromJson(const {
        'key': 'acme/teams/research',
        'name': 'Research',
        'description': 'Research team',
        'category': 'Research',
        'updatedAt': 1700000000000,
      });

      expect(team.metrics, isA<CatalogMetrics>());
      expect(team.metrics.adoptionCount, isNull);
      expect(team.metrics.rating, isNull);
      expect(team.metrics.ratingCount, isNull);
      expect(team.metrics.updatedAtMs, isNull);
      expect(team.metrics.publishedAtMs, isNull);
      expect(team.toJson().containsKey('metrics'), isFalse);
    },
  );
}
