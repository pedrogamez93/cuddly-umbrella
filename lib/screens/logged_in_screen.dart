// lib/screens/logged_in_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/session.dart';
import '../providers/feed_provider.dart';
import '../repositories/post_repository.dart';
import '../services/api_client.dart';
import '../services/appsync_ws.dart';
import '../widgets/post_card.dart';
import '../widgets/comments_sheet.dart'; // para abrir el sheet de comentarios
import 'likes_screen.dart';
import 'login_screen.dart';

class LoggedInScreen extends StatefulWidget {
  const LoggedInScreen({super.key});
  @override
  State<LoggedInScreen> createState() => _LoggedInScreenState();
}

class _LoggedInScreenState extends State<LoggedInScreen> {
  final _storage = const FlutterSecureStorage();
  final _scroll = ScrollController();

  // ✅ el provider vive como campo, NO dentro de build()
  late final FeedProvider _feed = FeedProvider(PostRepository(ApiClient()));

  AppSyncWS? _ws;

  @override
  void initState() {
    super.initState();
    // Asegura locale español para timeago en toda la app
    timeago.setLocaleMessages('es', timeago.EsMessages());
    _scroll.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ws?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300 &&
        _feed.hasMore &&
        !_feed.isFetchingMore) {
      _feed.fetchNext();
    }
  }

  Future<void> _bootstrap() async {
    try {
      final access = await _storage.read(key: 'access_token');
      final userId = await _storage.read(key: 'user_id');

      if (!mounted) return;

      if (access == null || userId == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }

      String? email;
      final authJwt = await _storage.read(key: 'auth_token');
      if (authJwt != null && authJwt.isNotEmpty) {
        final claims = JwtDecoder.decode(authJwt);
        email = (claims['email'] ?? claims['user_email'] ?? claims['upn'])?.toString();
      }
      email ??= await _storage.read(key: 'user_email');

      await _feed.init(Session(accessToken: access, userId: userId, email: email));

      if (email != null) {
       _ws = AppSyncWS(
            wssUrl: 'wss://notificaciones-somos-wss.qa.chileatiende.cl/graphql/realtime',
            host: 'avnaqxexqvabxdndyro3w42zfi.appsync-api.us-east-1.amazonaws.com',
            apiKey: '<APP_SYNC_API_KEY_QA>',
            onNotification: (notif) {
              if (!mounted) return;
              final title = (notif['title'] ?? 'Notificación').toString();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🔔 $title')));
            },
          );
        await _ws!.connectAndSubscribe();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar el feed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _feed,
      child: Consumer<FeedProvider>(
        builder: (ctx, prov, _) {
          return Scaffold(
            appBar: AppBar(
              title: Row(children: const [
                Icon(Icons.home), SizedBox(width: 8), Text('Últimas Noticias'),
              ]),
            ),
            body: prov.isLoading
                ? const Center(child: CircularProgressIndicator())
                : (prov.posts.isEmpty
                    ? _emptyState(context)
                    : RefreshIndicator(
                        onRefresh: prov.refresh,
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: prov.posts.length + (prov.hasMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i >= prov.posts.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final p = prov.posts[i];
                            return PostCard(
                              postId: p.id,
                              title: p.title,
                              publishedAt: p.publishedAt,
                              imageUrls: p.imageUrls,
                              paragraphHtml: p.paragraphHtml,
                              isLiked: prov.liked.contains(p.id),
                              isSaved: prov.saved.contains(p.id),
                              likeCount: prov.likeCount[p.id] ?? p.likesCount,
                              commentCount: p.commentsCount, // <- NUEVO
                              onToggleLike: () => prov.toggleLike(p.id),
                              onToggleSave: () => prov.toggleSaved(p.id),
                              onTapLikes: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LikesScreen(postId: p.id.toString()),
                                  ),
                                );
                              },
                              onTapComments: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.85,
                                    child: CommentsSheet(postId: p.id),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      )),
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Estuviste mucho tiempo sin actividad', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          },
          child: const Text('Ir a login'),
        ),
      ]),
    );
  }
}
