// lib/models/comment.dart

class Comment {
  final int id;
  final String content;
  final String? run;
  final String? names;
  final String? surnames;
  final String? email;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int likesCount;
  final int? childCommentsCount;

  Comment({
    required this.id,
    required this.content,
    this.run,
    this.names,
    this.surnames,
    this.email,
    required this.createdAt,
    required this.updatedAt,
    required this.likesCount,
    this.childCommentsCount,
  });

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['id'] is int ? j['id'] : int.parse(j['id'].toString()),
        content: (j['content'] ?? '').toString(),
        run: j['run'] as String?,
        names: j['names'] as String?,
        surnames: j['surnames'] as String?,
        email: j['email'] as String?,
        createdAt: DateTime.parse(j['created_at']),
        updatedAt: DateTime.parse(j['updated_at']),
        likesCount: (j['likes_count'] ?? 0) as int,
        childCommentsCount: j['child_comments_count'] as int?,
      );
}
