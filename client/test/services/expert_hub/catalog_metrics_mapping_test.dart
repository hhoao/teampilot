import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_member.dart';

void main() {
  test('maps and round-trips expert catalog metrics', () {
    final member = DiscoverableMember.fromJson(const {
      'key': 'acme/experts/reviewer',
      'name': 'Reviewer',
      'description': 'Reviews code',
      'category': 'Engineering',
      'source': 'registry',
      'member': {'name': 'reviewer'},
      'metrics': {
        'adoptionCount': 321,
        'rating': 4.5,
        'ratingCount': 18,
        'updatedAtMs': 1700000000001,
        'publishedAtMs': 1690000000000,
      },
    });

    expect(member.metrics.adoptionCount, 321);
    expect(member.metrics.rating, 4.5);
    expect(member.metrics.ratingCount, 18);
    expect(member.metrics.updatedAtMs, 1700000000001);
    expect(member.metrics.publishedAtMs, 1690000000000);
    expect(
      DiscoverableMember.fromJson(member.toJson()).metrics.ratingCount,
      18,
    );
  });

  test('omitted expert metrics preserve null catalog data', () {
    final member = DiscoverableMember.fromJson(const {
      'key': 'acme/experts/reviewer',
      'name': 'Reviewer',
      'description': 'Reviews code',
      'category': 'Engineering',
      'source': 'registry',
      'member': {'name': 'reviewer'},
    });

    expect(member.metrics, isA<CatalogMetrics>());
    expect(member.metrics.adoptionCount, isNull);
    expect(member.metrics.rating, isNull);
    expect(member.metrics.ratingCount, isNull);
    expect(member.metrics.updatedAtMs, isNull);
    expect(member.metrics.publishedAtMs, isNull);
    expect(member.toJson().containsKey('metrics'), isFalse);
  });
}
