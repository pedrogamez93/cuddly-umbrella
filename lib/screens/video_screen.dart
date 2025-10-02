import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// tabs
import 'package:ips_app_chileatiende/screens/logged_in_screen.dart';
import 'package:ips_app_chileatiende/screens/profile_screen.dart';
import 'package:ips_app_chileatiende/screens/saved_news_screen.dart';
import 'package:ips_app_chileatiende/screens/podcast_screen.dart';

// reproductor local para MP4 (no YouTube)
import 'package:ips_app_chileatiende/widgets/video_player_page.dart';

class VideoInfo {
  final String url;
  final String title;
  VideoInfo({required this.url, required this.title});
}

class VideoCard {
  final List<VideoInfo> videos;
  VideoCard({required this.videos});
}

class VideoExtraLink {
  final String linkText;
  final String linkUrl;
  VideoExtraLink({required this.linkText, required this.linkUrl});
}

class VideoData {
  final List<VideoCard> videoCards;
  final List<VideoExtraLink> extraLinks;
  VideoData({required this.videoCards, required this.extraLinks});
}

final _storage = FlutterSecureStorage();

class VideoScreen extends StatefulWidget {
  const VideoScreen({Key? key}) : super(key: key);

  @override
  _VideoScreenState createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isLoadingMenu = true;
  List<dynamic> _menuItems = [];
  String? userEmail = 'Cargando...';
  String? fullname = 'Cargando...';

  int _currentIndex = 0;

  late Future<VideoData> _futureData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchMenuItems();
    _futureData = fetchVideoData();
  }

  Future<void> _loadUserData() async {
    final email = await _storage.read(key: 'user_email');
    final fullName = await _storage.read(key: 'user_full_name');
    if (!mounted) return;
    setState(() {
      userEmail = email ?? 'No disponible';
      fullname = fullName ?? 'Usuario';
    });
  }

  void _goToLogin({String? message}) {
    if (!mounted) return;
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
    Navigator.pushReplacementNamed(context, '/');
  }

  Future<void> _fetchMenuItems() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) throw Exception('No token');

      final response = await http.get(
        Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-menu-items'),
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
      } else if (response.statusCode == 401) {
        if (!mounted) return;
        setState(() => _isLoadingMenu = false);
        _goToLogin(message: 'Sesión expirada. Inicia sesión nuevamente.');
      } else {
        throw Exception('Status: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMenu = false);
      // No hacemos print para no ensuciar logs.
    }
  }

  Future<void> _logoutUser(BuildContext context) async {
    try {
      final token = await _storage.read(key: 'access_token');
      final userId = await _storage.read(key: 'user_id');
      if (token == null || userId == null) {
        _goToLogin();
        return;
      }

      final response = await http.post(
        Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/register-logout'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'app_user_id': userId},
      );

      await _storage.delete(key: 'access_token');
      await _storage.delete(key: 'user_id');

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/');
    } catch (_) {
      _goToLogin();
    }
  }

  Future<VideoData> fetchVideoData() async {
    final token = await _storage.read(key: 'access_token');
    if (token == null) throw Exception('No token');

    final response = await http.get(
      Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-content-by-endpoint?endpoint=videos'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final metadata = data['data']?['metadata'] as List<dynamic>?;
      if (metadata == null) return VideoData(videoCards: [], extraLinks: []);
      return _parseVideoMetadata(metadata);
    } else if (response.statusCode == 401) {
      // redirige y devuelve dataset vacío para no romper el FutureBuilder
      _goToLogin(message: 'Sesión expirada. Inicia sesión nuevamente.');
      return VideoData(videoCards: [], extraLinks: []);
    } else {
      throw Exception('Status: ${response.statusCode}');
    }
  }

  VideoData _parseVideoMetadata(List<dynamic> metadataList) {
    final videoCards = <VideoCard>[];
    final extraLinks = <VideoExtraLink>[];

    for (final meta in metadataList) {
      final metaKey = meta['meta_key'];
      dynamic metaValue = meta['meta_value'];

      // Algunos CMS mandan Strings con JSON adentro
      if (metaValue is String) {
        try { metaValue = json.decode(metaValue); } catch (_) {}
      }

      if (metaKey == 'video_card' && metaValue is Map) {
        final rawCards = (metaValue['cards'] as List?) ?? const [];
        final videos = rawCards.map((c) {
          final m = (c is String) ? (json.decode(c) as Map) : (c as Map);
          return VideoInfo(
            url: (m['url'] ?? '').toString(),
            title: (m['title'] ?? 'Video sin título').toString(),
          );
        }).toList();
        videoCards.add(VideoCard(videos: videos));
      } else if (metaKey == 'link' && metaValue is Map) {
        extraLinks.add(VideoExtraLink(
          linkText: (metaValue['link-text'] ?? '').toString(),
          linkUrl: (metaValue['link-url'] ?? '').toString(),
        ));
      }
    }
    return VideoData(videoCards: videoCards, extraLinks: extraLinks);
  }

  // --- UI helpers ---

  // Thumbnail sin red (evita "Invalid image data")
  Widget _videoLeading() {
    return Container(
      width: 120,
      height: 68,
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(Icons.play_circle_fill, size: 36),
    );
  }

  bool _isMp4(String url) => url.toLowerCase().trim().endsWith('.mp4');

  void _onVideoTap(VideoInfo v) async {
    final u = v.url.trim();
    if (_isMp4(u)) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoPlayerPage(url: u, title: v.title)),
      );
    } else {
      final uri = Uri.tryParse(u);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el enlace')),
        );
      }
    }
  }

  void _onBottomTap(int i) {
    setState(() => _currentIndex = i);
    if (i == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoggedInScreen()),
      );
    } else if (i == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SavedNewsScreen()),
      );
    } else if (i == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ProfileScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = FutureBuilder<VideoData>(
      future: _futureData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final data = snapshot.data;
        if (data == null || (data.videoCards.isEmpty && data.extraLinks.isEmpty)) {
          return const Center(child: Text('No hay videos disponibles.'));
        }

        return ListView(
          children: [
            ...data.videoCards.map((vc) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: vc.videos.map((v) {
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: ListTile(
                        leading: _videoLeading(),
                        title: Text(v.title),
                        subtitle: Text(v.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _onVideoTap(v),
                      ),
                    );
                  }).toList(),
                )),
            ...data.extraLinks.map((l) => Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ListTile(
                    title: Text(l.linkText, style: const TextStyle(color: Colors.blue)),
                    subtitle: Text(l.linkUrl),
                    onTap: () async {
                      final uri = Uri.tryParse(l.linkUrl);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                )),
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
            Flexible(child: Image.asset('assets/images/logo.png', height: 40)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 2,
      ),
      endDrawer: Drawer(
        child: Column(
          children: [
            Container(
              color: const Color(0xFF0F69B4),
              child: Column(
                children: [
                  UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(color: Color(0xFF0E4B7E)),
                    accountName: Text(
                      fullname ?? 'Usuario',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    accountEmail: Text(userEmail ?? 'No disponible', style: const TextStyle(fontSize: 14)),
                    currentAccountPicture: const CircleAvatar(
                      backgroundImage: NetworkImage(
                        'https://static.vecteezy.com/system/resources/thumbnails/005/545/335/small/user-sign-icon-person-symbol-human-avatar-isolated-on-white-backogrund-vector.jpg',
                      ),
                    ),
                    margin: EdgeInsets.zero,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
                      onPressed: () async => _logoutUser(context),
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
                          final endpoint = item['endpoint'] as String?;
                          final iconUrl = item['icon'];
                          final assetPath = 'assets/images/${iconUrl ?? "news"}.png';

                          return ListTile(
                            leading: SizedBox(
                              width: 25,
                              height: 25,
                              child: Image.asset(
                                assetPath,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    Image.asset('assets/images/news.png', fit: BoxFit.contain),
                              ),
                            ),
                            title: Text(item['title'] ?? 'Sin título'),
                            textColor: Colors.white,
                            onTap: () {
                              Navigator.pop(context);
                              if (endpoint == null || endpoint.isEmpty) return;
                              final endLower = endpoint.toLowerCase().trim();
                              if (endLower == 'home' || endLower == 'inicio') {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => const LoggedInScreen()),
                                );
                              } else if (endLower == 'podcast') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const PodcastScreen()),
                                );
                              } else if (endLower == 'videos') {
                                // ya estás aquí
                              } else {
                                // aquí podrías navegar a ItemScreen si corresponde
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
      body: bodyContent,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onBottomTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Marcadores'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
