import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseTitle,
    required this.publishedAt,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.hasUpdate,
    required this.isSupportedPlatform,
    required this.message,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseTitle;
  final String publishedAt;
  final String releaseUrl;
  final String downloadUrl;
  final bool hasUpdate;
  final bool isSupportedPlatform;
  final String message;
}

class AppUpdateService {
  const AppUpdateService({
    required this.githubOwner,
    required this.githubRepo,
  });

  final String githubOwner;
  final String githubRepo;

  Future<AppUpdateInfo> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();
    if (!_isSupportedPlatform) {
      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        releaseTitle: '',
        publishedAt: '',
        releaseUrl: '',
        downloadUrl: '',
        hasUpdate: false,
        isSupportedPlatform: false,
        message: 'Updates are supported on Android and Windows only.',
      );
    }

    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest',
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'NeverMiss-Alarm-Updater');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'GitHub API request failed (${response.statusCode}).',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Unexpected GitHub release payload.');
      }
      final payload = decoded.map((k, v) => MapEntry(k.toString(), v));
      final tagName = (payload['tag_name'] as String? ?? '').trim();
      final latestVersion = _normalizeVersion(tagName);
      final releaseTitle = (payload['name'] as String? ?? tagName).trim();
      final publishedAt = (payload['published_at'] as String? ?? '').trim();
      final releaseUrl = (payload['html_url'] as String? ?? '').trim();
      final assets = payload['assets'];
      final downloadUrl = _selectAssetDownloadUrl(assets) ?? releaseUrl;
      if (latestVersion.isEmpty) {
        throw const FormatException('Release tag is missing a semantic version.');
      }

      final hasUpdate = _compareSemVer(latestVersion, currentVersion) > 0;
      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseTitle: releaseTitle,
        publishedAt: publishedAt,
        releaseUrl: releaseUrl,
        downloadUrl: downloadUrl,
        hasUpdate: hasUpdate,
        isSupportedPlatform: true,
        message: hasUpdate ? 'Update available.' : 'You are up to date.',
      );
    } finally {
      client.close(force: true);
    }
  }

  bool get _isSupportedPlatform => Platform.isAndroid || Platform.isWindows;

  static String _normalizeVersion(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');
    final match = RegExp(r'^\d+\.\d+\.\d+').firstMatch(cleaned);
    return match?.group(0) ?? '';
  }

  static int _compareSemVer(String left, String right) {
    List<int> parse(String value) {
      final normalized = _normalizeVersion(value);
      final chunks = normalized.split('.');
      return <int>[
        chunks.isNotEmpty ? int.tryParse(chunks[0]) ?? 0 : 0,
        chunks.length > 1 ? int.tryParse(chunks[1]) ?? 0 : 0,
        chunks.length > 2 ? int.tryParse(chunks[2]) ?? 0 : 0,
      ];
    }

    final l = parse(left);
    final r = parse(right);
    for (var i = 0; i < 3; i++) {
      if (l[i] > r[i]) {
        return 1;
      }
      if (l[i] < r[i]) {
        return -1;
      }
    }
    return 0;
  }

  String? _selectAssetDownloadUrl(Object? assetsRaw) {
    if (assetsRaw is! List) {
      return null;
    }

    String? pickByExtension(List<Map<String, dynamic>> assets, List<String> extensions) {
      for (final ext in extensions) {
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase().trim();
          final url = (asset['browser_download_url'] as String? ?? '').trim();
          if (name.endsWith(ext) && url.isNotEmpty) {
            return url;
          }
        }
      }
      return null;
    }

    final assets = assetsRaw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
    if (assets.isEmpty) {
      return null;
    }

    if (Platform.isAndroid) {
      return pickByExtension(assets, const <String>['.apk']);
    }
    if (Platform.isWindows) {
      return pickByExtension(assets, const <String>['.exe', '.msi', '.zip']);
    }
    return null;
  }
}
