import 'api_config.dart';

/// Resolves stored media references (profile photos, venue images, ...) to a
/// URL that is reachable from the current client.
///
/// The backend may persist an absolute URL built from whatever host served the
/// upload (e.g. an ngrok tunnel, `localhost`, or a production domain) or a
/// relative `/media/...` path. Rebuilding the URL against the client's own
/// configured origin means images keep working regardless of how they were
/// stored or which host the app is currently talking to.
class MediaConfig {
  MediaConfig._();

  /// API base with the trailing `/api` segment removed, e.g.
  /// `http://localhost:8000` or `https://api.Rivalink.et`.
  static String get origin {
    var base = ApiConfig.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    const suffix = '/api';
    if (base.endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
    }
    return base;
  }

  /// Returns a reachable absolute URL, or `null` when there is nothing to show.
  static String? resolve(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;

    final mediaIndex = value.indexOf('/media/');
    if (mediaIndex >= 0) {
      return '$origin${value.substring(mediaIndex)}';
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    if (value.startsWith('/')) return '$origin$value';
    return '$origin/$value';
  }
}
