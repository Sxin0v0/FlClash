import 'release_asset.dart';

const _builtReleaseVersion = String.fromEnvironment('APP_RELEASE_VERSION');

final _customVersion = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)-quickchain\.(\d+)$');
final _nativeVersion = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$');

List<int>? _versionParts(String version, {bool customOnly = false}) {
  final custom = _customVersion.firstMatch(version);
  if (custom != null) {
    return List.generate(4, (index) => int.parse(custom[index + 1]!));
  }
  if (customOnly) return null;
  final native = _nativeVersion.firstMatch(version);
  if (native == null) return null;
  return [...List.generate(3, (index) => int.parse(native[index + 1]!)), 0];
}

/// Compare the upstream version first, then the numeric custom revision.
int compareQuickChainVersions(String left, String right) {
  final a = _versionParts(left);
  final b = _versionParts(right);
  if (a == null || b == null) {
    throw FormatException('Unrecognized Quick Chain version: $left / $right');
  }
  for (var index = 0; index < a.length; index++) {
    final order = a[index].compareTo(b[index]);
    if (order != 0) return order;
  }
  return 0;
}

/// Native Windows version resources cannot carry the custom suffix.
String currentQuickChainVersion(String nativeVersion) =>
    _versionParts(_builtReleaseVersion, customOnly: true) == null
    ? nativeVersion
    : _builtReleaseVersion;

/// Never offer an upstream binary, a draft, or an incomplete release.
Map<String, dynamic>? newestQuickChainRelease(Iterable<dynamic> releases) {
  Map<String, dynamic>? newest;
  for (final release in releases) {
    if (release is! Map<String, dynamic> || release['draft'] == true) continue;
    final tag = release['tag_name'];
    if (tag is! String || _versionParts(tag, customOnly: true) == null) {
      continue;
    }
    final assets = release['assets'];
    if (assets is! List) continue;
    final names = {
      for (final asset in assets)
        if (asset is Map &&
            asset['state'] != 'starter' &&
            asset['name'] is String)
          asset['name'] as String,
    };
    final version = releaseVersionOfTag(tag);
    final setup = releaseAssetName(
      version: version,
      os: ReleaseOs.windows,
      arch: ReleaseArch.amd64,
      form: ReleaseForm.setup,
      extension: 'exe',
    );
    final portable = releaseAssetName(
      version: version,
      os: ReleaseOs.windows,
      arch: ReleaseArch.amd64,
      form: ReleaseForm.portable,
      extension: 'zip',
    );
    if (!names.containsAll([setup, portable, updateChecksumsName(tag)])) {
      continue;
    }
    if (newest == null ||
        compareQuickChainVersions(tag, newest['tag_name'] as String) > 0) {
      newest = release;
    }
  }
  return newest;
}
