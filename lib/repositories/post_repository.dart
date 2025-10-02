import '../models/post.dart';
import '../services/api_client.dart';

class PostRepository {
  final ApiClient api;
  PostRepository(this.api);

  Future<({List<Post> posts, bool hasMore})> page({
    required int appUserId,
    required int page,
    required String token,
  }) => api.getPosts(appUserId: appUserId, page: page, token: token);

  Future<Set<int>> likedAll({
    required String appUserId,
    required String token,
  }) => api.getAllLikedPostIdsPaged(appUserId: appUserId, token: token);

  Future<Set<int>> savedAll({
    required String appUserId,
    required String token,
  }) => api.getSavedPostIds(appUserId: appUserId, token: token);

  Future<void> like({required String appUserId, required int postId, required String token})
    => api.likePost(appUserId: appUserId, postId: postId, token: token);

  Future<void> unlike({required String appUserId, required int postId, required String token})
    => api.removeLike(appUserId: appUserId, postId: postId, token: token);

  Future<void> save({required String appUserId, required int postId, required String token})
    => api.savePost(appUserId: appUserId, postId: postId, token: token);

  Future<void> unsave({required String appUserId, required int postId, required String token})
    => api.removeSaved(appUserId: appUserId, postId: postId, token: token);
}
