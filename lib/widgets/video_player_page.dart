import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:webview_flutter/webview_flutter.dart'; // API antigua (pre-4)
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  const VideoPlayerPage({super.key, required this.url, required this.title});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  // ---- Controllers
  YoutubePlayerController? _ytController;
  VideoPlayerController? _videoCtrl;
  ChewieController? _chewieCtrl;

  // WebView (API antigua): sólo guardamos la URL inicial
  String? _webInitialUrl;

  // Storage para token
  final _secure = const FlutterSecureStorage();

  // ---- Detección de tipo
  bool get _isYouTube => _extractYouTubeId(widget.url) != null;
  bool get _isDirectVideo => _hasVideoExtension(widget.url);
  bool get _isVimeo => _extractVimeoId(widget.url) != null;

  // UI
  double _aspectRatio = 16 / 9;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // 1) YouTube
    if (_isYouTube) {
      final id = _extractYouTubeId(widget.url)!;
      _ytController = YoutubePlayerController(
        initialVideoId: id,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          enableCaption: true,
          controlsVisibleAtStart: true,
        ),
      );
      if (mounted) setState(() {});
      return;
    }

    // 2) Directo (mp4/webm/mov/m3u8) con headers
    if (_isDirectVideo) {
      try {
        final headers = await _buildHttpHeaders(Uri.parse(widget.url));
        final ctrl = VideoPlayerController.networkUrl(
          Uri.parse(widget.url), // ✅ API nueva del plugin de video
          httpHeaders: headers,
        );
        await ctrl.initialize();

        final ar = ctrl.value.aspectRatio;
        if (mounted && ar.isFinite && ar > 0) {
          _aspectRatio = ar;
        }

        _videoCtrl = ctrl;
        _chewieCtrl = ChewieController(
          videoPlayerController: _videoCtrl!,
          autoPlay: false,
          looping: false,
          allowMuting: true,
          allowFullScreen: true,
          allowPlaybackSpeedChanging: true,
          showControlsOnInitialize: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: Theme.of(context).colorScheme.primary,
            bufferedColor: Theme.of(context).colorScheme.primary.withOpacity(.3),
            handleColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Colors.black26,
          ),
          placeholder: Container(color: Colors.black),
        );

        if (mounted) setState(() {});
        return;
      } catch (_) {
        // caída a WebView
        _webInitialUrl = widget.url;
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo reproducir de forma nativa, abriendo en la app.')),
          );
        }
        return;
      }
    }

    // 3) Vimeo u otros -> WebView (embed si es Vimeo)
    _webInitialUrl = _isVimeo
        ? _buildVimeoEmbedUrl(_extractVimeoId(widget.url)!)
        : widget.url;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ytController?.pause();
    _ytController?.dispose();
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title.isEmpty ? 'Video' : widget.title;
    final host = Uri.tryParse(widget.url)?.host.replaceFirst('www.', '') ?? '—';
    final origin = _isYouTube ? 'YouTube' : _isVimeo ? 'Vimeo' : _isDirectVideo ? 'Archivo' : host;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        titleSpacing: 0,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
       
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _PlayerCard(
              aspectRatio: _aspectRatio,
              child: _buildPlayer(),
            ),
            const SizedBox(height: 16),

            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: -8,
              children: [
                Chip(
                  label: Text(origin),
                  avatar: const Icon(Icons.play_circle_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(host),
                  avatar: const Icon(Icons.public, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),

         
            
          ],
        ),
      ),
    );
  }

  // ===================== UI builders =====================

  Widget _buildPlayer() {
    // YouTube
    if (_isYouTube) {
      if (_ytController == null) return const Center(child: CircularProgressIndicator());
      return YoutubePlayerBuilder(
        player: YoutubePlayer(controller: _ytController!),
        builder: (_, player) => player,
      );
    }

    // Directo
    if (_isDirectVideo) {
      if (_videoCtrl == null || _chewieCtrl == null || !_videoCtrl!.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      final ar = _videoCtrl!.value.aspectRatio;
      final safeAR = (ar == 0 || ar.isNaN) ? 16 / 9 : ar;
      return AspectRatio(aspectRatio: safeAR, child: Chewie(controller: _chewieCtrl!));
    }

    // WebView (Vimeo / otros / fallback) — API antigua
    if (_webInitialUrl == null) return const Center(child: CircularProgressIndicator());

    return WebView(
      initialUrl: _webInitialUrl!,
      javascriptMode: JavascriptMode.unrestricted, // ✅ ojo: Java**s**criptMode
      navigationDelegate: (NavigationRequest request) {
        return NavigationDecision.navigate;
      },
      onWebResourceError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de carga: ${error.description}')),
        );
      },
      gestureNavigationEnabled: true,
    );
  }

  // ===================== Helpers =====================

  Future<Map<String, String>> _buildHttpHeaders(Uri uri) async {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Mobile Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
      'Referer': 'https://somos-api-cms.qa.chileatiende.cl/',
    };
    final token = await _secure.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  String? _extractYouTubeId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('youtu.be')) {
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        return (id != null && id.isNotEmpty) ? id : null;
      }
      if (uri.host.contains('youtube.com')) {
        final v = uri.queryParameters['v'];
        if (v != null && v.isNotEmpty) return v;
        if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'embed') {
          return uri.pathSegments[1];
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _hasVideoExtension(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov');
  }

  String? _extractVimeoId(String url) {
    try {
      final reg = RegExp(r'vimeo\.com/(?:video/|channels/[^/]+/|groups/[^/]+/videos/)?(\d+)');
      final m = reg.firstMatch(url);
      return m != null ? m.group(1) : null;
    } catch (_) {
      return null;
    }
  }

  String _buildVimeoEmbedUrl(String id) {
    return 'https://player.vimeo.com/video/$id?playsinline=1&title=0&byline=0&portrait=0';
  }
}

// ====== Widgets de presentación ======

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.child,
    required this.aspectRatio,
  });

  final Widget child;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final safeAR = (aspectRatio.isFinite && aspectRatio > 0) ? aspectRatio : 16 / 9;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: safeAR,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0B1020), Color(0xFF1C1F2A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.05)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


