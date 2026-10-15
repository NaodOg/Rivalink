import 'package:http_parser/http_parser.dart';

/// Best-effort MIME type for an image path, based on its file extension.
///
/// `http.MultipartFile.fromPath` defaults to `application/octet-stream`, which
/// the backend's image validator rejects, so callers must pass an explicit
/// image content type when uploading.
MediaType imageMediaType(String path) {
  final ext = path.split('.').last.toLowerCase();
  switch (ext) {
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    case 'gif':
      return MediaType('image', 'gif');
    case 'jpg':
    case 'jpeg':
    default:
      return MediaType('image', 'jpeg');
  }
}
