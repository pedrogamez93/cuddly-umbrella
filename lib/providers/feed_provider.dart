import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../models/session.dart';
import '../repositories/post_repository.dart';

class FeedProvider extends ChangeNotifier {
  final PostRepository repo;
  FeedProvider(this.repo);

  final posts = <Post>[];
  final liked = <int>{};
  final saved = <int>{};
  final likeCount = <int, int>{};

  bool isLoading = false;
  bool isFetchingMore = false;
  bool hasMore = true;
  int _page = 1;
  late Session _session;

  Future<void> init(Session session) async {
  _session = session;
  isLoading = true;
  notifyListeners();
  try {
    // likes/guardados (no críticos)
    try {
      final results = await Future.wait([
        repo.likedAll(appUserId: _session.userId, token: _session.accessToken),
        repo.savedAll(appUserId: _session.userId, token: _session.accessToken),
      ]);
      liked..clear()..addAll(results[0] as Set<int>);
      saved..clear()..addAll(results[1] as Set<int>);
    } catch (_) {
      liked.clear();
      saved.clear();
    }

    // posts (crítico)
    final pageRes = await repo.page(
      appUserId: int.parse(_session.userId),
      page: 1,
      token: _session.accessToken,
    );
    posts..clear()..addAll(pageRes.posts);
    likeCount
      ..clear()
      ..addEntries(posts.map((p) => MapEntry(p.id, p.likesCount)));
    hasMore = pageRes.hasMore;
    _page = 1;
  } finally {
    isLoading = false;
    notifyListeners();
  }
}


  Future<void> refresh() async => init(_session);

  Future<void> fetchNext() async {
    if (isFetchingMore || !hasMore) return;
    isFetchingMore = true;
    notifyListeners();
    try {
      _page += 1;
      final pageRes = await repo.page(
        appUserId: int.parse(_session.userId),
        page: _page,
        token: _session.accessToken,
      );
      posts.addAll(pageRes.posts);
      for (final p in pageRes.posts) {
        likeCount.putIfAbsent(p.id, () => p.likesCount);
      }
      hasMore = pageRes.hasMore;
    } finally {
      isFetchingMore = false;
      notifyListeners();
    }
  }

  Future<void> toggleLike(int postId) async {
    final isLiked = liked.contains(postId);
    // optimistic
    if (isLiked) {
      liked.remove(postId);
      likeCount[postId] = (likeCount[postId] ?? 1) - 1;
    } else {
      liked.add(postId);
      likeCount[postId] = (likeCount[postId] ?? 0) + 1;
    }
    notifyListeners();

    try {
      if (isLiked) {
        await repo.unlike(appUserId: _session.userId, postId: postId, token: _session.accessToken);
      } else {
        await repo.like(appUserId: _session.userId, postId: postId, token: _session.accessToken);
      }
    } catch (_) {
      // rollback on failure
      if (isLiked) {
        liked.add(postId);
        likeCount[postId] = (likeCount[postId] ?? 0) + 1;
      } else {
        liked.remove(postId);
        likeCount[postId] = (likeCount[postId] ?? 1) - 1;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> toggleSaved(int postId) async {
    final isSaved = saved.contains(postId);
    // optimistic
    if (isSaved) {
      saved.remove(postId);
    } else {
      saved.add(postId);
    }
    notifyListeners();
    try {
      if (isSaved) {
        await repo.unsave(appUserId: _session.userId, postId: postId, token: _session.accessToken);
      } else {
        await repo.save(appUserId: _session.userId, postId: postId, token: _session.accessToken);
      }
    } catch (_) {
      // rollback
      if (isSaved) saved.add(postId); else saved.remove(postId);
      notifyListeners();
      rethrow;
    }
  }
}
