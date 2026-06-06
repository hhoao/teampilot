/// Bundled geometric project avatars.
const kProjectGeometryIconAssets = <String>[
  'assets/geometry/img1.svg',
  'assets/geometry/img2.svg',
  'assets/geometry/img3.svg',
  'assets/geometry/img4.svg',
  'assets/geometry/img5.svg',
  'assets/geometry/img6.svg',
  'assets/geometry/img7.svg',
  'assets/geometry/img8.svg',
  'assets/geometry/img9.svg',
  'assets/geometry/img10.svg',
  'assets/geometry/img11.svg',
  'assets/geometry/img12.svg',
  'assets/geometry/img13.svg',
  'assets/geometry/img14.svg',
  'assets/geometry/img15.svg',
  'assets/geometry/img16.svg',
  'assets/geometry/img17.svg',
  'assets/geometry/img18.svg',
  'assets/geometry/img19.svg',
  'assets/geometry/img20.svg',
  'assets/geometry/img21.svg',
  'assets/geometry/img22.svg',
  'assets/geometry/img23.svg',
  'assets/geometry/img24.svg',
];

int projectGeometryIndexForProjectId(String projectId) {
  final assets = kProjectGeometryIconAssets;
  if (assets.isEmpty) return 0;
  return projectId.hashCode.abs() % assets.length;
}

String projectGeometryAssetForProjectId(String projectId) {
  return kProjectGeometryIconAssets[projectGeometryIndexForProjectId(projectId)];
}

String projectGeometryAssetForIndex(int index, {required String projectId}) {
  final assets = kProjectGeometryIconAssets;
  if (assets.isEmpty) return 'assets/geometry/img1.svg';
  if (index >= 0 && index < assets.length) return assets[index];
  return projectGeometryAssetForProjectId(projectId);
}
