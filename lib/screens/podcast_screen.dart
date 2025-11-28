// lib/screens/podcast_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:ips_app_chileatiende/screens/item_screen.dart';
import 'package:ips_app_chileatiende/screens/logged_in_screen.dart';
import 'package:ips_app_chileatiende/screens/profile_screen.dart';
import 'package:ips_app_chileatiende/screens/saved_news_screen.dart';
import 'package:ips_app_chileatiende/screens/video_screen.dart';


import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:url_launcher/url_launcher.dart';




class PodcastLink {
  final String linkText;
  final String linkUrl;
  PodcastLink({required this.linkText, required this.linkUrl});
}

class PodcastAccordion {
  final String title;
  final List<PodcastLink> links;
  PodcastAccordion({required this.title, required this.links});
}

final _storage = FlutterSecureStorage();

class PodcastScreen extends StatefulWidget {
  const PodcastScreen({Key? key}) : super(key: key);

  @override
  State<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends State<PodcastScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Drawer / usuario
  String? userEmail = 'Cargando...';
  String? fullname = 'Cargando...';
  bool _isLoadingMenu = true;
  List<dynamic> _menuItems = [];

  // Navegación inferior
  int _currentIndex = 0;
  String? _selectedEndpoint;
  final List<Widget> _screens = [
    LoggedInScreen(),
    SavedNewsScreen(),
    ProfileScreen(),
  ];

  // Datos de podcasts
  late Future<List<PodcastAccordion>> _futurePodcasts;

  // ====== AUDIO (miniplayer con just_audio) ======
  final ja.AudioPlayer _player = ja.AudioPlayer();
  String? _currentUrl;
  String? _currentTitle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _userSeeking = false;

  // ====== DIAGNÓSTICO ======
  final List<String> _logs = <String>[];
  bool _showDiag = false;
  static const _ua = 'IPSApp/1.0 (Android)';
  static const _referer = 'https://intranet.chileatiende.cl'; // ajusta si tu CDN lo exige

  void _log(String msg, {String level = 'INFO'}) {
    final ts = DateTime.now().toIso8601String();
    final line = '[$level] $ts  $msg';
    // ignore: avoid_print
    print(line);
    setState(() {
      _logs.add(line);
      if (_logs.length > 500) _logs.removeRange(0, 50);
    });
  }

  @override
  void initState() {
    super.initState();
    _initAudio();
    _loadUserData();
    _fetchMenuItems();
    _futurePodcasts = _fetchPodcastData();

    // Streams del reproductor
    _player.playerStateStream.listen((state) {
      final playing = state.playing;
      final proc = state.processingState;
      _isPlaying = playing && proc != ja.ProcessingState.completed;
      if (proc == ja.ProcessingState.completed) {
        _log('Playback complete');
        _isPlaying = false;
        _position = Duration.zero;
        // no hacemos stop para permitir replay si toca Play de nuevo
      }
      setState(() {});
    });

    _player.durationStream.listen((d) {
      if (d != null) {
        _duration = d;
        _log('Duration -> ${d.inMilliseconds}ms');
        setState(() {});
      }
    });

    _player.positionStream.listen((p) {
      if (!_userSeeking) {
        _position = p;
        setState(() {});
      }
    });
  }

  Future<void> _initAudio() async {
    // Configura el audio session (permite pausar música externa, etc.)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // ======== Usuario y menú ========
  Future<void> _loadUserData() async {
    final email = await _storage.read(key: 'user_email');
    final fullName = await _storage.read(key: 'user_full_name');
    if (!mounted) return;
    setState(() {
      userEmail = email ?? 'No disponible';
      fullname = fullName ?? 'Usuario';
    });
  }

  Future<void> _fetchMenuItems() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) throw Exception('No se encontró un token de acceso.');

      final response = await http.get(
        Uri.parse(
          'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-menu-items',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!mounted) return;
        setState(() {
          _menuItems = data['data'];
          _isLoadingMenu = false;
        });
      } else {
        throw Exception(
          'Error al cargar los elementos del menú: ${response.statusCode}',
        );
      }
    } catch (e) {
      _log('Error al cargar menú: $e', level: 'WARN');
      if (!mounted) return;
      setState(() {
        _isLoadingMenu = false;
      });
    }
  }

  Future<void> _logoutUser(BuildContext context) async {
    try {
      final token = await _storage.read(key: 'access_token');
      final userId = await _storage.read(key: 'user_id');
      if (token == null || userId == null) return;

      final response = await http.post(
        Uri.parse(
          'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/register-logout',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'app_user_id': userId},
      );

      if (response.statusCode == 200) {
        await _storage.delete(key: 'access_token');
        await _storage.delete(key: 'user_id');
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/');
      } else {
        _log("Error al cerrar sesión: ${response.body}", level: 'WARN');
      }
    } catch (e) {
      _log("Excepción al cerrar sesión: $e", level: 'ERROR');
    }
  }

  // ======== Datos de podcasts ========
  Future<List<PodcastAccordion>> _fetchPodcastData() async {
    final token = await _storage.read(key: 'access_token');
    if (token == null) {
      throw Exception("Token de autenticación no encontrado");
    }

    final url = Uri.parse(
      'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-content-by-endpoint?endpoint=podcast',
    );

    final response = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonData = json.decode(response.body);
      final metadata = jsonData['data']['metadata'] as List<dynamic>?;
      if (metadata == null) return [];
      return _parsePodcastMetadata(metadata);
    } else {
      throw Exception('Error al obtener podcasts: ${response.statusCode}');
    }
  }

  List<PodcastAccordion> _parsePodcastMetadata(List<dynamic> metadataList) {
    final result = <PodcastAccordion>[];
    for (var meta in metadataList) {
      if (meta['meta_key'] == 'accordion' && meta['meta_value'] != null) {
        final metaValue = meta['meta_value'];
        final String accordionTitle =
            metaValue['accordion-title'] ?? 'Sin título';
        final List<dynamic> inputLinks = metaValue['input'] ?? [];

        final links = inputLinks.map((obj) {
          final text = (obj['link-text'] ?? '').toString().trim();
          return PodcastLink(
            linkText: text.isEmpty ? 'Sin título' : text,
            linkUrl: obj['link-url'] ?? '',
          );
        }).toList();

        result.add(PodcastAccordion(title: accordionTitle, links: links));
      }
    }
    return result;
  }

  // ======== DIAGNÓSTICO HTTP/STREAM ========

  Future<Uri> _followRedirectsHead(Uri start, {int maxHops = 5}) async {
    var uri = start;
    for (int i = 0; i < maxHops; i++) {
      final hop = i + 1;
      _log('HEAD hop $hop -> $uri');
      final client = HttpClient()
        ..userAgent = _ua
        ..maxConnectionsPerHost = 2
        ..connectionTimeout = const Duration(seconds: 8);

      client.badCertificateCallback = (cert, host, port) {
        _log('⚠️ Certificado no válido para $host:$port', level: 'WARN');
        return false;
      };

      HttpClientRequest req = await client.openUrl('HEAD', uri);
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      req.headers.set(HttpHeaders.refererHeader, _referer);
      req.followRedirects = false;

      final resp = await req.close().timeout(const Duration(seconds: 8));
      _log('HEAD ${resp.statusCode} ${resp.reasonPhrase}');
      _log('  Content-Type: ${resp.headers.value(HttpHeaders.contentTypeHeader)}');
      _log('  Content-Length: ${resp.headers.value(HttpHeaders.contentLengthHeader)}');
      _log('  Accept-Ranges: ${resp.headers.value(HttpHeaders.acceptRangesHeader)}');
      _log('  Server: ${resp.headers.value('server')}');

      if (resp.isRedirect) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        _log('  Redirect -> $loc', level: 'WARN');
        if (loc == null) break;
        final next = Uri.parse(loc);
        uri = next.isAbsolute ? next : uri.resolve(loc);
        client.close(force: true);
        continue;
      }

      client.close(force: true);
      return uri;
    }
    return uri;
  }

  Future<void> _rangeProbe(Uri uri, {int? contentLength}) async {
    final client = HttpClient()
      ..userAgent = _ua
      ..maxConnectionsPerHost = 2
      ..connectionTimeout = const Duration(seconds: 8);

    // 1) Inicio: bytes=0-1
    try {
      _log('RANGE probe #1 bytes=0-1');
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.refererHeader, _referer);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      _log('  Status: ${resp.statusCode}');
      _log('  Content-Range: ${resp.headers.value(HttpHeaders.contentRangeHeader)}');
      if (resp.statusCode != 206) {
        _log('  ⚠️ El servidor NO devolvió 206 en Range inicial', level: 'WARN');
      }
      await resp.drain();
    } catch (e) {
      _log('  Error RANGE #1: $e', level: 'ERROR');
    }

    // 2) Final: bytes=(len-2)-(len-1)
    if (contentLength != null && contentLength > 4) {
      try {
        final start = contentLength - 2;
        final end = contentLength - 1;
        _log('RANGE probe #2 bytes=$start-$end (Content-Length=$contentLength)');
        final req2 = await client.getUrl(uri);
        req2.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        req2.headers.set(HttpHeaders.userAgentHeader, _ua);
        req2.headers.set(HttpHeaders.refererHeader, _referer);
        final resp2 = await req2.close().timeout(const Duration(seconds: 8));
        _log('  Status: ${resp2.statusCode}');
        _log('  Content-Range: ${resp2.headers.value(HttpHeaders.contentRangeHeader)}');
        if (resp2.statusCode != 206) {
          _log('  ⚠️ El servidor NO devolvió 206 en Range final', level: 'WARN');
        }
        await resp2.drain();
      } catch (e) {
        _log('  Error RANGE #2: $e', level: 'ERROR');
      }
    } else {
      _log('RANGE probe #2 omitida (sin Content-Length válido)');
    }

    client.close(force: true);
  }

  Future<void> diagnoseUrl(String url) async {
    _log('===== Diagnóstico para URL =====');
    _log(url);
    try {
      final startUri = Uri.parse(url);

      // HEAD + redirects
      final finalUri = await _followRedirectsHead(startUri);
      _log('URI final: $finalUri');

      // HEAD final con package:http
      final headResp = await http.head(finalUri, headers: {
        'User-Agent': _ua,
        'Accept': '*/*',
        'Referer': _referer,
      }).timeout(const Duration(seconds: 8));

      _log('HEAD final status: ${headResp.statusCode}');
      headResp.headers.forEach((k, v) => _log('  $k: $v'));

      final ct = headResp.headers['content-type'] ?? '';
      final clStr = headResp.headers['content-length'];
      final ar = headResp.headers['accept-ranges'];
      final server = headResp.headers['server'];

      int? cl;
      if (clStr != null) cl = int.tryParse(clStr);

      if (!(ct.startsWith('audio/') || ct.contains('mpeg') || ct.contains('mp3'))) {
        _log('⚠️ Content-Type no parece de audio: $ct', level: 'WARN');
      }
      if (ar == null || !ar.toLowerCase().contains('bytes')) {
        _log('⚠️ Accept-Ranges NO presente o no es "bytes" -> posible problema con Android Media/ExoPlayer', level: 'WARN');
      }
      _log('Servidor: ${server ?? 'n/a'}');

      // Probe RANGE
      await _rangeProbe(finalUri, contentLength: cl);

      // GET simple (por si HEAD falla)
      try {
        _log('GET simple (prueba sin Range, primeros bytes)');
        final req = await HttpClient().getUrl(finalUri);
        req.headers.set(HttpHeaders.userAgentHeader, _ua);
        req.headers.set(HttpHeaders.acceptHeader, '*/*');
        req.headers.set(HttpHeaders.refererHeader, _referer);
        final resp = await req.close().timeout(const Duration(seconds: 10));
        _log('GET simple status: ${resp.statusCode}');
        await resp.drain();
      } catch (e) {
        _log('GET simple error: $e', level: 'ERROR');
      }

      _log('===== Fin Diagnóstico =====');

    } on TimeoutException {
      _log('⏳ Timeout en diagnóstico', level: 'ERROR');
    } catch (e) {
      _log('❌ Error en diagnóstico: $e', level: 'ERROR');
    }
  }

  // ======== Descarga (fallback) ========

  Future<File?> _downloadToTemp(String url) async {
    try {
      final client = HttpClient()
        ..userAgent = _ua
        ..connectionTimeout = const Duration(seconds: 20);

      _log('Descargando a temp: $url');
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      req.headers.set(HttpHeaders.refererHeader, _referer);

      final resp = await req.close().timeout(const Duration(seconds: 30));
      _log('GET download status: ${resp.statusCode}');
      if (resp.statusCode != 200) {
        _log('No se puede descargar: status ${resp.statusCode}', level: 'ERROR');
        client.close(force: true);
        return null;
      }

      final dir = await Directory.systemTemp.createTemp('ips_pod_');
      final file = File('${dir.path}/episode.mp3');
      final sink = file.openWrite();
      int bytes = 0;

      await for (final chunk in resp) {
        bytes += chunk.length;
        sink.add(chunk);
        if (bytes % 200000 == 0) {
          _log('Descargados ~${(bytes / (1024*1024)).toStringAsFixed(1)} MB');
        }
      }
      await sink.flush();
      await sink.close();
      client.close(force: true);
      _log('Descarga completa: ${(bytes / (1024*1024)).toStringAsFixed(2)} MB -> ${file.path}');
      return file;
    } catch (e) {
      _log('Error de descarga: $e', level: 'ERROR');
      return null;
    }
  }

  Future<void> _downloadAndPlay(String url, String title) async {
    final f = await _downloadToTemp(url);
    if (f == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo descargar el audio.')),
      );
      return;
    }

    try {
      await _player.stop();
      setState(() {
        _currentUrl = url; // referencia al remoto
        _currentTitle = '$title (offline)';
        _position = Duration.zero;
        _duration = Duration.zero;
      });
      _log('Reproduciendo archivo local…');
      await _player.setAudioSource(ja.AudioSource.uri(Uri.file(f.path)));
      await _player.play();
    } catch (e) {
      _log('Error reproduciendo archivo local: $e', level: 'ERROR');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo reproducir el archivo local.')),
      );
    }
  }

  // ======== Reproductor ========

  Future<void> _openExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      await _player.stop();
      setState(() {
        _currentUrl = null;
        _currentTitle = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
      });
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _log('No se pudo abrir externo: $e', level: 'ERROR');
    }
  }

  Future<void> _playUrl(String url, String title) async {
    final sw = Stopwatch()..start();
    try {
      _log('Intentando reproducir: $title');
      _log('URL: $url');

      // Preflight rápido (HEAD)
      final uri = Uri.parse(url);
      final head = await http.head(uri, headers: {
        'User-Agent': _ua,
        'Accept': '*/*',
        'Referer': _referer,
      }).timeout(const Duration(seconds: 8), onTimeout: () => http.Response('', 599));

      _log('HEAD status: ${head.statusCode}');
      if (head.statusCode == 403 || head.statusCode == 401) {
        _log('CDN bloquea HEAD (status ${head.statusCode}). Intentaré descarga + play local', level: 'WARN');
        await _downloadAndPlay(url, title);
        return;
      }

      // Resume si es el mismo y está pausado
      if (_currentUrl == url && !_isPlaying && _position > Duration.zero) {
        await _player.play();
        _log('Resume OK en ${sw.elapsedMilliseconds}ms');
        return;
      }

      // Cambio de pista
      if (_currentUrl != url) {
        await _player.stop();
        _position = Duration.zero;
        _duration = Duration.zero;
        _currentUrl = url;
        _currentTitle = title;

        // just_audio con headers (sí soporta)
        _log('setAudioSource(AudioSource.uri) con headers');
        await _player.setAudioSource(
          ja.AudioSource.uri(
            Uri.parse(url),
            headers: {
              'User-Agent': _ua,
              'Accept': '*/*',
              'Referer': _referer,
            },
          ),
        );
      }

      _log('Reproduciendo…');
      await _player.play();
      _log('Reproducción iniciada en ${sw.elapsedMilliseconds}ms');

    } on TimeoutException {
      _log('Timeout en reproducción. Intentaré descarga + play local.', level: 'ERROR');
      await _downloadAndPlay(url, title);
    } catch (e) {
      _log('Error al reproducir (stream): $e', level: 'ERROR');
      // fallback: descarga + play local
      await _downloadAndPlay(url, title);
    } finally {
      sw.stop();
    }
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        _log('Pause');
        await _player.pause();
      } else {
        _log('Play');
        await _player.play();
      }
    } catch (e) {
      _log('Toggle error: $e', level: 'ERROR');
    }
  }

  Future<void> _stopPlayback() async {
    try {
      _log('Stop');
      await _player.stop();
      setState(() {
        _currentUrl = null;
        _currentTitle = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
      });
    } catch (e) {
      _log('Stop error: $e', level: 'ERROR');
    }
  }

  String _formatDur(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  // ======== UI ========
  @override
  Widget build(BuildContext context) {
    final bodyContentWhenEndpoint = _selectedEndpoint != null
        ? ItemScreen(
            endpoint: _selectedEndpoint!,
            onItemSelected: (newEndpoint) {
              setState(() => _selectedEndpoint = newEndpoint);
            },
          )
        : _screens[_currentIndex];

    final bodyPodcast = FutureBuilder<List<PodcastAccordion>>(
      future: _futurePodcasts,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final accordions = snapshot.data ?? [];
        if (accordions.isEmpty) {
          return const Center(child: Text('No hay podcasts disponibles.'));
        }

        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: accordions.length,
                itemBuilder: (context, index) {
                  final accordion = accordions[index];
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        childrenPadding: const EdgeInsets.only(
                            left: 8, right: 8, bottom: 12),
                        title: Text(
                          accordion.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        trailing:
                            const Icon(Icons.keyboard_arrow_down_rounded),
                        children: [
                          ...accordion.links.map((link) {
                            final isCurrent = _currentUrl == link.linkUrl;

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.grey.shade300, width: 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Título + botones
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          link.linkText,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton.filledTonal(
                                        tooltip: (isCurrent && _isPlaying)
                                            ? 'Pausar'
                                            : 'Reproducir',
                                        icon: Icon(
                                          (isCurrent && _isPlaying)
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                        onPressed: () {
                                          if (isCurrent && _isPlaying) {
                                            _player.pause();
                                          } else {
                                            _playUrl(link.linkUrl, link.linkText);
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      // IconButton(
                                      //   tooltip: 'Diagnosticar esta URL',
                                      //   icon: const Icon(Icons.bug_report),
                                      //   onPressed: () {
                                      //     diagnoseUrl(link.linkUrl);
                                      //     setState(() => _showDiag = true);
                                      //   },
                                      // ),
                                    ],
                                  ),
                                  // Si es el actual, barra de progreso local
                                  if (isCurrent) ...[
                                    const SizedBox(height: 6),
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 3,
                                        thumbShape:
                                            const RoundSliderThumbShape(
                                                enabledThumbRadius: 8),
                                      ),
                                      child: Slider(
                                        value: _position.inMilliseconds
                                            .clamp(0, _duration.inMilliseconds)
                                            .toDouble(),
                                        min: 0,
                                        max: _duration.inMilliseconds > 0
                                            ? _duration.inMilliseconds
                                                .toDouble()
                                            : 1.0,
                                        onChangeStart: (_) {
                                          _userSeeking = true;
                                        },
                                        onChanged: (v) {
                                          setState(() {
                                            _position =
                                                Duration(milliseconds: v.toInt());
                                          });
                                        },
                                        onChangeEnd: (v) async {
                                          final target = Duration(
                                              milliseconds: v.toInt());
                                          await _player.seek(target);
                                          _userSeeking = false;
                                        },
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDur(_position),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                        Text(
                                          _formatDur(_duration),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Panel de diagnóstico (toggle)
            if (_showDiag)
              Container(
                height: 220,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.black12)),
                  color: Colors.white,
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      width: double.infinity,
                      color: Colors.grey.shade200,
                      child: Row(
                        children: [
                          const Icon(Icons.bug_report, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Diagnóstico',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setState(() => _logs.clear()),
                            icon: const Icon(Icons.delete_sweep),
                            label: const Text('Limpiar'),
                          ),
                          IconButton(
                            tooltip: 'Cerrar panel',
                            onPressed: () => setState(() => _showDiag = false),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => Text(
                          _logs[i],
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Image.asset(
                'assets/images/logo.png',
                height: 40,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        actions: [
          // IconButton(
          //   tooltip: 'Mostrar/Ocultar diagnóstico',
          //   icon: const Icon(Icons.bug_report),
          //   onPressed: () => setState(() => _showDiag = !_showDiag),
          // ),
        ],
      ),
      endDrawer: Drawer(
        child: Column(
          children: [
            Container(
              color: const Color(0xFF0F69B4),
              child: Column(
                children: [
                  UserAccountsDrawerHeader(
                    decoration:
                        const BoxDecoration(color: Color(0xFF0E4B7E)),
                    accountName: Text(
                      fullname ?? 'Usuario',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    accountEmail: Text(
                      userEmail ?? 'No disponible',
                      style: const TextStyle(fontSize: 14),
                    ),
                    currentAccountPicture: const CircleAvatar(
                      backgroundImage:
                          AssetImage('assets/images/avatar_placeholder.png'),
                    ),
                    margin: EdgeInsets.zero,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text(
                        'Cerrar sesión',
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: () async {
                        await _logoutUser(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: const Color(0xFF0F69B4),
                child: _isLoadingMenu
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _menuItems.length,
                        itemBuilder: (context, index) {
                          final item = _menuItems[index];
                          final String? iconName = item['icon']; // ej: 'news'
                          final String assetPath = (iconName != null && iconName.isNotEmpty)
                              ? 'assets/images/$iconName.png'
                              : 'assets/images/news.png';

                          final String? endpoint = item['endpoint'];

                          return ListTile(
                            leading: SizedBox(
                              width: 25,
                              height: 25,
                              child: Image.asset(
                                assetPath,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Image.asset(
                                    'assets/images/news.png',
                                    fit: BoxFit.contain,
                                  );
                                },
                              ),
                            ),
                            title: Text(item['title'] ?? 'Sin título'),
                            textColor: Colors.white,
                            onTap: () {
                              Navigator.pop(context);
                              if (endpoint != null && endpoint.isNotEmpty) {
                                final endLower = endpoint.toLowerCase();
                                if (endLower == 'home' || endLower == 'inicio') {
                                  setState(() {
                                    _selectedEndpoint = null;
                                    _currentIndex = 0;
                                  });
                                } else if (endLower == 'noticias') {
                                  setState(() {
                                    _selectedEndpoint = 'news';
                                  });
                                } else if (endLower == 'podcast') {
                                  // ya estamos en podcast
                                } else if (endLower == 'videos') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const VideoScreen(),
                                    ),
                                  );
                                } else {
                                  setState(() {
                                    _selectedEndpoint = endpoint;
                                  });
                                }
                              } else {
                                _log('No se encontró un endpoint para este ítem.',
                                    level: 'WARN');
                              }
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      body: _selectedEndpoint != null ? bodyContentWhenEndpoint : bodyPodcast,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (int index) {
          Navigator.pop(context); // por si el Drawer estaba abierto
          setState(() {
            _selectedEndpoint = null;
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark),
            label: 'Marcadores',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),

      // Mini Player anclado
      bottomSheet: (_currentUrl != null)
          ? _MiniPlayer(
              title: _currentTitle ?? 'Reproduciendo…',
              isPlaying: _isPlaying,
              position: _position,
              duration: _duration,
              onPlayPause: _togglePlayPause,
              onStop: _stopPlayback,
              onSeek: (to) async {
                await _player.seek(to);
              },
            )
          : null,
    );
  }
}

// ---------- Widget del MiniPlayer ----------
class _MiniPlayer extends StatelessWidget {
  final String title;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final ValueChanged<Duration> onSeek;

  const _MiniPlayer({
    required this.title,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onStop,
    required this.onSeek,
    Key? key,
  }) : super(key: key);

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final max = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
    final val = position.inMilliseconds.clamp(0, max);

    return Material(
      elevation: 12,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Título y acciones
              Row(
                children: [
                  const Icon(Icons.podcasts_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded),
                    iconSize: 32,
                    onPressed: onPlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onStop,
                  ),
                ],
              ),
              // Barra de progreso
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  value: val.toDouble(),
                  min: 0,
                  max: max.toDouble(),
                  onChanged: (x) => onSeek(Duration(milliseconds: x.toInt())),
                ),
              ),
              // Tiempos
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(position),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    Text(_fmt(duration),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
