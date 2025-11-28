class Story {
  final int id;
  final String title;
  final bool featured;
  final int likesCount;
  final int commentsCount;
  final int viewsCount;
  final String? publishedAt;
  final String? expiresAt;
  bool liked; // campo auxiliar para UI

  Story({
    required this.id,
    required this.title,
    required this.featured,
    required this.likesCount,
    required this.commentsCount,
    required this.viewsCount,
    this.publishedAt,
    this.expiresAt,
    this.liked = false,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'],
      title: json['title'] ?? '',
      featured: json['featured'] ?? false,
      likesCount: json['likes_count'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
      viewsCount: json['views_count'] ?? 0,
      publishedAt: json['published_at'],
      expiresAt: json['expires_at'],
      liked: json['liked'] ?? false,
    );
  }
}
