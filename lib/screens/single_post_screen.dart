// lib/screens/single_post_screen.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/comment.dart';
import '../services/comments_api.dart';
import '../widgets/share_content_sheet.dart';
import '../widgets/comments_sheet.dart';
import 'likes_screen.dart';

class SinglePostScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  const SinglePostScreen({super.key, required this.post});

  @override
  State<SinglePostScreen> createState() => _SinglePostScreenState();
}

class _SinglePostScreenState extends State<SinglePostScreen> {
  // ====== API / Const ======
  static const _host = 'somos-api-cms.qa.chileatiende.cl';

  // Likes del post
  // GET https://{host}/api/mobile-app/likes-post?post_id={id}
  // (Se mantiene porque ya lo usas en LikesScreen)
  List<Map<String, dynamic>> likes = [];
  bool isLikesLoading = true;

  // ====== Media ======
  late final List<_MediaItem> media;
  int _currentIndex = 0;
  final Map<String, Future<Uint8List?>> _imageCache = {};

  // ====== Comments (preview con tu API) ======
  final _storage = const FlutterSecureStorage();
  final CommentsApi _api = CommentsApi();
  bool _commentsLoading = false;
  String? _commentsError;
  List<Comment> _comments = [];

  // Datos de sesión (para toggleLike)
  int _appUserId = -1;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    media = _extractMedia(widget.post);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // user_id y email para acciones de comentarios
    _appUserId = int.tryParse(await _storage.read(key: 'user_id') ?? '') ?? -1;
    _userEmail = await _storage.read(key: 'user_email');
    await _fetchLikes();
    await _fetchComments();
  }

  // =================== MEDIA ===================

  List<_MediaItem> _extractMedia(Map<String, dynamic> post) {
    final items = <_MediaItem>[];

    if (post['images'] is List) {
      for (final e in (post['images'] as List)) {
        final s = (e ?? '').toString().trim();
        if (s.isNotEmpty) items.add(_MediaItem.image(_cleanUrl(s)));
      }
      if (items.isNotEmpty) return items;
    }

    final rawMeta = post['meta_key']?.toString();
    if (rawMeta != null && rawMeta.isNotEmpty) {
      List<dynamic>? metaList;
      try {
        metaList = json.decode(rawMeta);
      } catch (_) {
        try {
          metaList = json
              .decode(rawMeta.replaceAll(r'\\', r'\\\\').replaceAll(r'\/', '/'));
        } catch (_) {}
      }
      if (metaList is List) {
        for (var item in metaList) {
          final type = item['type']?.toString();
          if (type == 'image-carousel' && item['cards'] is List) {
            for (final c in (item['cards'] as List)) {
              final img = c['image']?.toString();
              final vid = (c['video'] ?? c['href'])?.toString();
              if (img != null && img.trim().isNotEmpty) {
                items.add(_MediaItem.image(_cleanUrl(img)));
              }
              if (vid != null && vid.trim().isNotEmpty) {
                items.add(_MediaItem.video(_cleanUrl(vid)));
              }
            }
          } else if (type == 'image') {
            final img = item['image']?.toString();
            if (img != null && img.trim().isNotEmpty) {
              items.add(_MediaItem.image(_cleanUrl(img)));
            }
          } else if (type == 'video') {
            final vid = (item['video'] ?? item['href'])?.toString();
            if (vid != null && vid.trim().isNotEmpty) {
              items.add(_MediaItem.video(_cleanUrl(vid)));
            }
          }
        }
      }
    }

    if (items.isEmpty && post['image'] != null) {
      items.add(_MediaItem.image(_cleanUrl(post['image'].toString())));
    }

    return items;
  }

  String _cleanUrl(String raw) =>
      Uri.encodeFull(raw.replaceAll(r'\\', '').replaceAll(r'\/', '/').trim());

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': 'https://chileatiende.gob.cl',
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        },
      );
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _getImage(String url) =>
      _imageCache.putIfAbsent(url, () => _fetchImageBytes(url));

  Widget _mediaWidget(_MediaItem m) {
    if (m.isImage) {
      final url = m.url;
      if (url.isEmpty) {
        return Container(
          color: Colors.grey[300],
          child: const Center(child: Text('Imagen no disponible')),
        );
      }
      return FutureBuilder<Uint8List?>(
        future: _getImage(url),
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 250,
          );
        },
      );
    } else {
      return InkWell(
        onTap: () async {
          final uri = Uri.parse(m.url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          height: 250,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_fill, color: Colors.white, size: 64),
                SizedBox(height: 8),
                Text('Reproducir video', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildGalleryMixed(List<_MediaItem> items) {
    if (items.isEmpty) {
      return Container(
        height: 250,
        color: Colors.grey[300],
        child: const Center(child: Text('Imagen/Video no disponible')),
      );
    }

    return Column(
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: 250,
            viewportFraction: 1.0,
            enableInfiniteScroll: items.length > 1,
            onPageChanged: (index, _) => setState(() => _currentIndex = index),
          ),
          items: items
              .map((m) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _mediaWidget(m),
                  ))
              .toList(),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: items.asMap().entries.map((entry) {
              final active = _currentIndex == entry.key;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 12 : 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? Colors.blueAccent : Colors.grey[400],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  // =================== LIKES (del post) ===================

  Future<void> _fetchLikes() async {
    final postId =
        widget.post['post_id']?.toString() ?? widget.post['id']?.toString() ?? '';
    if (postId.isEmpty) {
      setState(() => isLikesLoading = false);
      return;
    }

    final url = 'https://$_host/api/mobile-app/likes-post?post_id=$postId';
    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          likes = List<Map<String, dynamic>>.from(data['data'] ?? const []);
          isLikesLoading = false;
        });
      } else {
        setState(() => isLikesLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => isLikesLoading = false);
    }
  }

  // =================== COMMENTS (preview con CommentsApi) ===================

  _IdPair _resolveIdsForComments() {
    final p = widget.post;

    final postId = (p['post_id'] ??
            p['id'] ??
            p['postId'] ??
            p['original_content']?['data']?['id'])
        ?.toString();

    final pageId = (p['page_id'] ??
            p['pageId'] ??
            p['page']?['id'] ??
            p['original_content']?['data']?['page_id'])
        ?.toString();

    return _IdPair(postId: postId, pageId: pageId);
  }

  Future<void> _fetchComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
      _comments = [];
    });

    try {
      final ids = _resolveIdsForComments();
      final postId = int.tryParse(ids.postId ?? '');
      final pageId = int.tryParse(ids.pageId ?? '');

      if (postId == null && pageId == null) {
        setState(() {
          _commentsLoading = false;
          _commentsError =
              'No fue posible cargar comentarios: falta el identificador del post/página.';
        });
        return;
      }

      final res = await _api.getComments(
        postId: postId,
        pageId: pageId,
        page: 1,
        perPage: 5, // preview
      );

      if (!mounted) return;
      setState(() {
        _comments = res.data;
        _commentsLoading = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = 'No fue posible cargar comentarios.';
      });
    }
  }

  Future<void> _toggleCommentLike(Comment c) async {
    if (_appUserId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para reaccionar.')),
      );
      return;
    }
    try {
      await _api.toggleLike(appUserId: _appUserId, commentId: c.id);
      // recargamos el preview (misma página)
      await _fetchComments();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible registrar tu reacción.')),
      );
    }
  }

  // =================== UI ===================

  @override
  Widget build(BuildContext context) {
    final displayedTitle = (widget.post['title'] ?? '').toString();
    final postIdStr =
        widget.post['post_id']?.toString() ?? widget.post['id']?.toString() ?? '';
    final postId = int.tryParse(postIdStr);

    return Scaffold(
      appBar: AppBar(
        title: Text(displayedTitle.isEmpty ? 'Detalle' : displayedTitle),
        actions: [
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.share),
            onPressed: () async {
              final pid = postIdStr;
              if (pid.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No se encontró el ID del post.')),
                );
                return;
              }

              final ok = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                builder: (_) => ShareContentSheet(
                  type: 'post',
                  contentId: pid,
                  initialTitle: 'Revisa este post',
                  initialMessage: displayedTitle.isEmpty
                      ? 'Te comparto un post de la app.'
                      : 'Te comparto: "$displayedTitle".',
                ),
              );

              if (ok == true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Compartido con éxito.')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGalleryMixed(media),
                  const SizedBox(height: 16),

                  Text(
                    'Publicado el: ${widget.post['published_at'] ?? ''}',
                    style: const TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () {
                      if (postIdStr.isEmpty) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LikesScreen(postId: postIdStr),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.favorite, color: Colors.red),
                        Text(
                          '${widget.post['likes'] ?? 0} Me gusta',
                          style: const TextStyle(
                            decoration: TextDecoration.underline,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Html(data: widget.post['content'] ?? ''),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Comentarios',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      TextButton.icon(
                        onPressed: postId == null
                            ? null
                            : () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.85,
                                    child: CommentsSheet(
                                      postId: postId,
                                    ),
                                  ),
                                ).then((_) => _fetchComments()); // refresca preview
                              },
                        icon: const Icon(Icons.mode_comment_outlined, size: 18),
                        label: const Text('Ver y comentar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_commentsLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_commentsError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _commentsError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  else if (_comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Sé el primero en comentar…',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _comments.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 12, thickness: 0.6),
                      itemBuilder: (_, i) => _CommentPreviewTile(
                        comment: _comments[i],
                        onToggleLike: () => _toggleCommentLike(_comments[i]),
                        onOpenSheet: () {
                          if (postId == null) return;
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => SizedBox(
                              height: MediaQuery.of(context).size.height * 0.85,
                              child: CommentsSheet(
                                postId: postId,
                              ),
                            ),
                          ).then((_) => _fetchComments());
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =================== modelos/viewmodels locales ===================

class _MediaItem {
  final String kind; // 'image' | 'video'
  final String url;
  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';
  _MediaItem._(this.kind, this.url);
  factory _MediaItem.image(String url) => _MediaItem._('image', url);
  factory _MediaItem.video(String url) => _MediaItem._('video', url);
  @override
  String toString() => '$kind:$url';
}

class _IdPair {
  final String? postId;
  final String? pageId;
  const _IdPair({this.postId, this.pageId});
}

// =================== UI: preview de comentario ===================

class _CommentPreviewTile extends StatelessWidget {
  const _CommentPreviewTile({
    required this.comment,
    required this.onToggleLike,
    required this.onOpenSheet,
  });

  final Comment comment;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenSheet;

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays < 7) return '${diff.inDays} d';
    final m = (diff.inDays / 30).floor();
    if (m < 12) return '${m.clamp(1, 11)} mes${m == 1 ? '' : 'es'}';
    final y = (m / 12).floor();
    return '$y año${y == 1 ? '' : 's'}';
  }

  bool get _hasReplies => (comment.childCommentsCount ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullName = ((comment.names ?? '').trim() + (comment.surnames != null ? ' ${comment.surnames}' : '')).trim();
    final displayName = fullName.isEmpty ? (comment.email ?? 'Usuario') : fullName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blueGrey[100],
              child: Text(
                (displayName.isNotEmpty ? displayName[0] : 'U').toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      _relativeTime(comment.createdAt),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(comment.content),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      InkWell(
                        onTap: onToggleLike,
                        child: Row(
                          children: [
                            const Icon(Icons.thumb_up_off_alt, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${comment.likesCount}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      TextButton.icon(
                        onPressed: onOpenSheet,
                        icon: const Icon(Icons.reply, size: 16),
                        label: const Text('Responder'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_hasReplies)
                        TextButton.icon(
                          onPressed: onOpenSheet,
                          icon: const Icon(Icons.forum_outlined, size: 16),
                          label: Text('${comment.childCommentsCount} resp.'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
