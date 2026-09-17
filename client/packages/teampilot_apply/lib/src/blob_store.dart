import 'apply_plan.dart';

abstract class BlobStore {
  Future<void> put(String sha256, List<int> bytes);
  Future<bool> has(String sha256);
  Future<List<int>> open(String sha256);
}

final class MemoryBlobStore implements BlobStore {
  MemoryBlobStore();

  final _bytes = <String, List<int>>{};

  @override
  Future<void> put(String sha256, List<int> bytes) async {
    final actual = contentSha256Hex(bytes);
    if (actual != sha256) {
      throw StateError('blob sha256 mismatch: expected $sha256 got $actual');
    }
    _bytes.putIfAbsent(sha256, () => List<int>.from(bytes));
  }

  @override
  Future<bool> has(String sha256) async => _bytes.containsKey(sha256);

  @override
  Future<List<int>> open(String sha256) async {
    final bytes = _bytes[sha256];
    if (bytes == null) throw StateError('missing blob $sha256');
    return List<int>.from(bytes);
  }
}
