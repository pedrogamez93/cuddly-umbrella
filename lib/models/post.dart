import 'dart:convert';

class Post {
  final int id;
  final String title;
  final DateTime? publishedAt;
  final List<String> imageUrls;
  final String paragraphHtml;
  final int likesCount;
  final int commentsCount; // <- NUEVO

  Post({
    required this.id,
    required this.title,
    required this.publishedAt,
    required this.imageUrls,
    required this.paragraphHtml,
    required this.likesCount,
    required this.commentsCount, // <- NUEVO
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    final meta = _parseMetaKey(json['meta_key']);
    DateTime? published;
    final raw = json['published_at'];
    if (raw is String && raw.isNotEmpty) {
      try {
        published = DateTime.parse(raw);
      } catch (_) {}
    }

    int _asInt(dynamic v, [int def = 0]) {
      if (v is int) return v;
      return int.tryParse('${v ?? ''}') ?? def;
    }

    return Post(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      title: (json['title'] ?? 'Sin título').toString(),
      publishedAt: published,
      imageUrls: meta.images,
      paragraphHtml: meta.paragraphHtml,
      likesCount: _asInt(json['likes_count']),
      commentsCount: _asInt(json['comments_count']), // <- NUEVO
    );
  }

  static _MetaParsed _parseMetaKey(dynamic metaKey) {
    // meta_key suele venir como String con un JSON de lista de bloques [{cards:[], 'paragraph-text': ''}, ...]
    List<String> images = [];
    String paragraph = 'Sin descripción';

    try {
      final dynamic parsed = metaKey is String ? json.decode(metaKey) : metaKey;
      if (parsed is List) {
        for (final item in parsed) {
          if (item is Map) {
            // Galería
            final cards = item['cards'];
            if (cards is List) {
              for (final c in cards) {
                final rawUrl = (c is Map) ? c['image'] : null;
                if (rawUrl is String && rawUrl.trim().isNotEmpty) {
                  final cleaned =
                      Uri.encodeFull(rawUrl.replaceAll(r'\', '').trim());
                  images.add(cleaned);
                }
              }
            }
            // Párrafo
            final p = item['paragraph-text'];
            if (p is String && p.trim().isNotEmpty) {
              paragraph = p;
            }
          }
        }
      }
    } catch (_) { /* noop */ }

    return _MetaParsed(images: images, paragraphHtml: paragraph);
  }
}

class _MetaParsed {
  final List<String> images;
  final String paragraphHtml;
  _MetaParsed({required this.images, required this.paragraphHtml});
}
