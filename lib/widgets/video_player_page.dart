import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  // WebView (legacy API) fallback
  String? _webInitialUrl;

  // ---- Storage para token
  final _secure = const FlutterSecureStorage();

  // ---- Detección de tipo
  bool get _isYouTube => _extractYouTubeId(widget.url) != null;
  bool get _isDirectVideo => _hasVideoExtension(widget.url);
  bool get _isVimeo => _extractVimeoId(widget.url) != null;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
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
        setState(() {});
        return;
      }

      // 2) Directo (mp4/webm/mov/m3u8) con headers
      if (_isDirectVideo) {
        final headers = await _buildHttpHeaders(Uri.parse(widget.url));

        _videoCtrl = VideoPlayerController.network(
          widget.url,
          httpHeaders: headers,
        );

        await _videoCtrl!.initialize();

        _chewieCtrl = ChewieController(
          videoPlayerController: _videoCtrl!,
          autoPlay: false,
          looping: false,
          allowMuting: true,
          allowFullScreen: true,
          allowPlaybackSpeedChanging: true,
        );

        setState(() {});
        return;
      }

      // 3) Vimeo u otros -> WebView (embed si es Vimeo)
      _webInitialUrl = _isVimeo
          ? _buildVimeoEmbedUrl(_extractVimeoId(widget.url)!)
          : widget.url;
      setState(() {});
    } catch (e) {
      // Si el nativo falla (p.ej., 403 por headers), abrimos WebView como fallback
      _webInitialUrl = widget.url;
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo reproducir de forma nativa, abriendo en la app.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _ytController?.dispose();
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title.isEmpty ? 'Video' : widget.title;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: _buildPlayer()),
    );
  }

  Widget _buildPlayer() {
    // YouTube
    if (_isYouTube) {
      if (_ytController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return YoutubePlayerBuilder(
        player: YoutubePlayer(controller: _ytController!),
        builder: (context, player) => player,
      );
    }

    // Directo
    if (_isDirectVideo) {
      if (_videoCtrl == null ||
          _chewieCtrl == null ||
          !_videoCtrl!.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      final ar = _videoCtrl!.value.aspectRatio;
      return Center(
        child: AspectRatio(
          aspectRatio: (ar == 0 || ar.isNaN) ? 16 / 9 : ar,
          child: Chewie(controller: _chewieCtrl!),
        ),
      );
    }

    // WebView (Vimeo / otros / fallback)
    if (_webInitialUrl == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return WebView(
      initialUrl: _webInitialUrl!,
      javascriptMode: JavascriptMode.unrestricted,
      navigationDelegate: (NavigationRequest request) {
        // Mantener navegación dentro del WebView
        return NavigationDecision.navigate;
      },
      onWebResourceError: (WebResourceError error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error de carga: ${error.description}')),
          );
        }
      },
      gestureNavigationEnabled: true,
    );
  }

  // ===================== Helpers =====================

  Future<Map<String, String>> _buildHttpHeaders(Uri uri) async {
    final headers = <String, String>{
      // Algunos orígenes bloquean sin UA/Referer
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Mobile Safari/537.36',
      'Accept': '*/*',
      'Connection': 'keep-alive',
      // Ajusta al dominio permitido por tu CDN/origen (anti-hotlink)
      'Referer': 'https://somos-api-cms.qa.chileatiende.cl/',
    };

    // Si el archivo requiere autorización por token:
    final token = await _secure.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
    // Si tu backend usa cookies o headers personalizados, agrégalos aquí.
  }

  // YouTube: soporta youtu.be/ID, youtube.com/watch?v=ID, /embed/ID
  String? _extractYouTubeId(String url) {
    try {
      final uri = Uri.parse(url);

      // youtu.be/<id>
      if (uri.host.contains('youtu.be')) {
        final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        return (id != null && id.isNotEmpty) ? id : null;
      }

      if (uri.host.contains('youtube.com')) {
        // /watch?v=ID
        final v = uri.queryParameters['v'];
        if (v != null && v.isNotEmpty) return v;

        // /embed/ID
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
      final reg = RegExp(
        r'vimeo\.com/(?:video/|channels/[^/]+/|groups/[^/]+/videos/)?(\d+)',
      );
      final m = reg.firstMatch(url);
      return m != null ? m.group(1) : null;
    } catch (_) {
      return null;
    }
  }

  String _buildVimeoEmbedUrl(String id) {
    // playsinline permite reproducir dentro de la vista
    return 'https://player.vimeo.com/video/$id?playsinline=1&title=0&byline=0&portrait=0';
  }
}
