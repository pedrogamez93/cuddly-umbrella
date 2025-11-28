// lib/widgets/post_card.dart
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

enum MediaType { image, video, youtube }

class MediaItem {
  final MediaType type;
  final String url;
  final String? thumbnail;
  final String? description;

  const MediaItem._(this.type, this.url, {this.thumbnail, this.description});

  factory MediaItem.image(String url, {String? description}) =>
      MediaItem._(MediaType.image, url, description: description);

  factory MediaItem.video(String url, {String? thumbnail, String? description}) =>
      MediaItem._(MediaType.video, url, thumbnail: thumbnail, description: description);

  factory MediaItem.youtube(String url, {String? thumbnail, String? description}) =>
      MediaItem._(MediaType.youtube, url, thumbnail: thumbnail, description: description);
}

class PostCard extends StatefulWidget {
  final int postId;
  final String title;
  final DateTime? publishedAt;

  // Original (solo imágenes)
  final List<String> imageUrls;

  // Opcionales (si luego el modelo los trae)
  final List<String>? videoUrls;   // mp4/m3u8
  final List<String>? youtubeUrls; // youtu.be / youtube.com/watch

  final String paragraphHtml;
  final bool isLiked;
  final bool isSaved;
  final int likeCount;
  final int commentCount;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleSave;
  final VoidCallback onTapLikes;
  final VoidCallback onTapComments;

  // 👇 NUEVO: callback para el botón compartir
  final VoidCallback? onTapShare;

  const PostCard({
    super.key,
    required this.postId,
    required this.title,
    required this.publishedAt,
    required this.imageUrls,
    this.videoUrls,
    this.youtubeUrls,
    required this.paragraphHtml,
    required this.isLiked,
    required this.isSaved,
    required this.likeCount,
    required this.commentCount,
    required this.onToggleLike,
    required this.onToggleSave,
    required this.onTapLikes,
    required this.onTapComments,
    this.onTapShare, // 👈 NUEVO
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  int _current = 0;
  late final List<MediaItem> _media;

  bool _looksLikeYouTube(String u) {
    final s = u.toLowerCase();
    return s.contains('youtube.com/watch') || s.contains('youtu.be/');
  }

  bool _looksLikeVideo(String u) {
    final s = u.toLowerCase();
    return s.endsWith('.mp4') ||
        s.endsWith('.m3u8') ||
        s.endsWith('.mov') ||
        s.endsWith('.webm') ||
        s.endsWith('.m4v');
  }

  bool _looksLikeImage(String u) {
    final s = u.toLowerCase();
    return s.endsWith('.jpg') ||
        s.endsWith('.jpeg') ||
        s.endsWith('.png') ||
        s.endsWith('.webp') ||
        s.endsWith('.gif') ||
        s.contains('=image'); // por si el backend agrega querys
  }

  @override
  void initState() {
    super.initState();
    _media = _buildMedia();
    debugPrint('[PostCard] init postId=${widget.postId} '
        'imgs=${widget.imageUrls.length} vids=${widget.videoUrls?.length ?? 0} yt=${widget.youtubeUrls?.length ?? 0} '
        'mediaTotal=${_media.length}');
  }

  List<MediaItem> _buildMedia() {
    final out = <MediaItem>[];

    // 1) Re-clasificar lo que venga en imageUrls (algunas URLs no son imagen real)
    for (final raw in widget.imageUrls) {
      final u = raw.trim();
      if (u.isEmpty) continue;
      if (_looksLikeYouTube(u)) {
        out.add(MediaItem.youtube(u));
      } else if (_looksLikeVideo(u)) {
        out.add(MediaItem.video(u));
      } else if (_looksLikeImage(u)) {
        out.add(MediaItem.image(u));
      } else {
        // desconocido -> tratar como imagen (pero se manejará gracefully si falla)
        out.add(MediaItem.image(u));
      }
    }

    // 2) Agregar listas opcionales si existen
    for (final v in (widget.videoUrls ?? const [])) {
      final u = v.trim();
      if (u.isNotEmpty) out.add(MediaItem.video(u));
    }
    for (final y in (widget.youtubeUrls ?? const [])) {
      final u = y.trim();
      if (u.isNotEmpty) out.add(MediaItem.youtube(u));
    }

    return out;
  }

  @override
  void dispose() {
    debugPrint('[PostCard] dispose postId=${widget.postId}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeText = widget.publishedAt != null
        ? timeago.format(widget.publishedAt!, locale: 'es')
        : 'Fecha desconocida';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.access_time, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Text(timeText, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            ]),
            const SizedBox(height: 8),

            // ======= Media (imagen/video/youtube) =======
            if (_media.isEmpty)
              _placeholderBox()
            else if (_media.length == 1)
              // Para evitar "size.isFinite" garantizamos altura finita
              SizedBox(
                height: 250,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildSingle(_media.first),
                ),
              )
            else
              Column(
                children: [
                  CarouselSlider(
                    options: CarouselOptions(
                      height: 250,
                      viewportFraction: 1.0,
                      enableInfiniteScroll: false,
                      enlargeCenterPage: false,
                      onPageChanged: (i, reason) {
                        debugPrint('[PostCard] carousel pageChanged: $i, reason=$reason');
                        setState(() => _current = i);
                      },
                    ),
                    items: _media.map((m) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildSingle(m),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_media.length, (i) {
                      final active = _current == i;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: active ? 12 : 8, height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? Colors.blueAccent : Colors.grey[400],
                        ),
                      );
                    }),
                  ),
                ],
              ),

            const SizedBox(height: 8),

            // ======= Acciones ======= (like, likes, comentarios, compartir, guardar)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  IconButton(
                    icon: Icon(
                      widget.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: widget.isLiked ? Colors.red : Colors.black,
                    ),
                    onPressed: () {
                      debugPrint('[PostCard] toggleLike postId=${widget.postId}');
                      widget.onToggleLike();
                    },
                  ),
                  // Likes
                  GestureDetector(
                    onTap: () {
                      debugPrint('[PostCard] onTapLikes postId=${widget.postId}');
                      widget.onTapLikes();
                    },
                    child: Text(
                      '${widget.likeCount} Me gusta',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Comentarios
                  InkWell(
                    onTap: () {
                      debugPrint('[PostCard] onTapComments postId=${widget.postId}');
                      widget.onTapComments();
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.mode_comment_outlined, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.commentCount}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 👇 NUEVO: Compartir (tipo Instagram, al lado de comentarios)
                  if (widget.onTapShare != null)
                    InkWell(
                      onTap: () {
                        debugPrint('[PostCard] onTapShare postId=${widget.postId}');
                        widget.onTapShare!.call();
                      },
                      child: Row(
                        children: const [
                          Icon(Icons.send_outlined, size: 20),
                          SizedBox(width: 6),
                         
                        ],
                      ),
                    ),
                ]),
                IconButton(
                  icon: Icon(
                    widget.isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: widget.isSaved ? Colors.amber : Colors.black,
                  ),
                  onPressed: () {
                    debugPrint('[PostCard] toggleSave postId=${widget.postId}');
                    widget.onToggleSave();
                  },
                ),
              ],
            ),

            // ======= Contenido (HTML) =======
            Html(
              data: widget.paragraphHtml,
              style: {
                "p": Style(fontSize: FontSize(14), textAlign: TextAlign.justify),
                "a": Style(textDecoration: TextDecoration.underline),
              },
              onLinkTap: (url, attrs, el) async {
                if (url == null) return;
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // --------- helpers de media ----------
  Widget _buildSingle(MediaItem m) {
    switch (m.type) {
      case MediaType.image:
        return _cachedImage(m.url, description: m.description);
      case MediaType.video:
        return _NetworkVideoPlayer(url: m.url, thumbnail: m.thumbnail);
      case MediaType.youtube:
        return _YouTubePlayerBox(url: m.url);
    }
  }

  Widget _placeholderBox() {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(child: Icon(Icons.image_outlined, size: 40, color: Colors.black38)),
    );
  }

  Widget _cachedImage(String url, {String? description}) {
    final safe = Uri.encodeFull(url.toString().replaceAll(r'\', ''));
    return Stack(
      children: [
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: safe,
            httpHeaders: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/115 Safari/537.36',
              'Referer': 'https://chileatiende.gob.cl',
              'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
            },
            fit: BoxFit.cover,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
            errorWidget: (_, __, err) {
              debugPrint('[PostCard] cachedImage error ($safe): $err');
              return _placeholderBox();
            },
          ),
        ),
        if ((description ?? '').isNotEmpty)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(8),
              child: Text(
                description!,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}

// ======================= VIDEO MP4 / HLS =======================
class _NetworkVideoPlayer extends StatefulWidget {
  final String url;
  final String? thumbnail;

  const _NetworkVideoPlayer({Key? key, required this.url, this.thumbnail}) : super(key: key);

  @override
  State<_NetworkVideoPlayer> createState() => _NetworkVideoPlayerState();
}

class _NetworkVideoPlayerState extends State<_NetworkVideoPlayer> {
  VideoPlayerController? _vp;
  ChewieController? _chewie;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  Future<void> _initControllers() async {
    try {
      final isHls = widget.url.toLowerCase().endsWith('.m3u8');
      debugPrint('[_NetworkVideoPlayer] init url=${widget.url} hls=$isHls');

      // Si tu entorno prefiere .network en vez de .networkUrl, cambia aquí:
      _vp = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _vp!.initialize();

      _chewie = ChewieController(
        videoPlayerController: _vp!,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blueAccent,
          handleColor: Colors.blueAccent,
          bufferedColor: Colors.white54,
          backgroundColor: Colors.white24,
        ),
      );

      if (mounted) setState(() {});
      debugPrint('[_NetworkVideoPlayer] initialized ok (${_vp!.value.size})');
    } catch (e, st) {
      debugPrint('[_NetworkVideoPlayer] ERROR init: $e\n$st');
      setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    debugPrint('[_NetworkVideoPlayer] dispose url=${widget.url}');
    _chewie?.dispose();
    _vp?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError) {
      return _VideoErrorBox(url: widget.url);
    }
    if (_vp == null || !_vp!.value.isInitialized || _chewie == null) {
      return Stack(
        children: [
          if (widget.thumbnail != null && widget.thumbnail!.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: widget.thumbnail!,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final aspect = _vp!.value.aspectRatio == 0 ? 16 / 9 : _vp!.value.aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Chewie(controller: _chewie!),
      ),
    );
  }
}

class _VideoErrorBox extends StatelessWidget {
  final String url;
  const _VideoErrorBox({Key? key, required this.url}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 40, color: Colors.redAccent),
          const SizedBox(height: 8),
          const Text('No se pudo reproducir el video', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 4),
          Text(url, style: const TextStyle(fontSize: 10, color: Colors.black38), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ===================== YOUTUBE PLAYER =====================
class _YouTubePlayerBox extends StatefulWidget {
  final String url;
  const _YouTubePlayerBox({Key? key, required this.url}) : super(key: key);

  @override
  State<_YouTubePlayerBox> createState() => _YouTubePlayerBoxState();
}

class _YouTubePlayerBoxState extends State<_YouTubePlayerBox> {
  YoutubePlayerController? _yt;
  String? _videoId;
  bool _error = false;

  bool _isYouTubeUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('youtube.com/watch') || u.contains('youtu.be/');
  }

  @override
  void initState() {
    super.initState();
    try {
      if (!_isYouTubeUrl(widget.url)) {
        debugPrint('[_YouTubePlayerBox] URL no es de YouTube: ${widget.url}');
        _error = true;
      } else {
        _videoId = YoutubePlayer.convertUrlToId(widget.url);
        if (_videoId == null) {
          debugPrint('[_YouTubePlayerBox] no se pudo extraer videoId desde ${widget.url}');
          _error = true;
        } else {
          debugPrint('[_YouTubePlayerBox] init videoId=$_videoId');
          _yt = YoutubePlayerController(
            initialVideoId: _videoId!,
            flags: const YoutubePlayerFlags(
              autoPlay: false,
              mute: false,
              enableCaption: true,
              controlsVisibleAtStart: true,
            ),
          );
        }
      }
    } catch (e, st) {
      debugPrint('[_YouTubePlayerBox] ERROR init: $e\n$st');
      _error = true;
    }
    setState(() {});
  }

  @override
  void dispose() {
    debugPrint('[_YouTubePlayerBox] dispose videoId=$_videoId');
    _yt?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error || _yt == null) {
      return const _VideoErrorBox(url: 'YouTube');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: YoutubePlayer(
        controller: _yt!,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Colors.blueAccent,
      ),
    );
  }
}
