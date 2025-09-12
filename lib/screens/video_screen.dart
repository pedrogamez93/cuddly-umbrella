import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ips_app_chileatiende/screens/logged_in_screen.dart';
import 'package:ips_app_chileatiende/screens/profile_screen.dart';
import 'package:ips_app_chileatiende/screens/saved_news_screen.dart';
import 'package:ips_app_chileatiende/screens/podcast_screen.dart';

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
  final List<Widget> _screens = [
    LoggedInScreen(),
    SavedNewsScreen(),
    ProfileScreen(),
  ];
  late Future<VideoData> _futureData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchMenuItems();
    _futureData = fetchVideoData();
  }
  Future<void> _loadUserData() async {
    String? email = await _storage.read(key: 'user_email');
    String? fullName = await _storage.read(key: 'user_full_name');
    setState(() {
      userEmail = email ?? 'No disponible';
      fullname = fullName ?? 'Usuario';
    });
  }
  Future<void> _fetchMenuItems() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) throw Exception('No token');

      final response = await http.get(
        Uri.parse(
            'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-menu-items'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _menuItems = data['data'];
          _isLoadingMenu = false;
        });
      } else {
        throw Exception('Status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error menú: $e');
      setState(() => _isLoadingMenu = false);
    }
  }
  Future<void> _logoutUser(BuildContext context) async {
    try {
      String? token = await _storage.read(key: 'access_token');
      String? userId = await _storage.read(key: 'user_id');
      if (token == null || userId == null) return;

      final response = await http.post(
        Uri.parse(
            'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/register-logout'),
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
        Navigator.pushReplacementNamed(context, '/');
      } else {
        print('Logout error: ${response.body}');
      }
    } catch (e) {
      print('Logout ex: $e');
    }
  }
  Future<VideoData> fetchVideoData() async {
    final token = await _storage.read(key: 'access_token');
    if (token == null) throw Exception('No token');

    final response = await http.get(
      Uri.parse(
          'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-content-by-endpoint?endpoint=videos'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Status: ${response.statusCode}');
    }

    final metadata =
        json.decode(response.body)['data']['metadata'] as List<dynamic>?;

    if (metadata == null) return VideoData(videoCards: [], extraLinks: []);

    return _parseVideoMetadata(metadata);
  }

  VideoData _parseVideoMetadata(List<dynamic> metadataList) {
    final videoCards = <VideoCard>[];
    final extraLinks = <VideoExtraLink>[];

    for (var meta in metadataList) {
      final metaKey = meta['meta_key'];
      final metaValue = meta['meta_value'];

      if (metaKey == 'video_card' && metaValue is Map) {
        final rawCards = metaValue['cards'] as List<dynamic>? ?? [];
        final videos = rawCards
            .map((c) => VideoInfo(
                  url: c['url'] ?? '',
                  title: c['title'] ?? 'Video sin título',
                ))
            .toList();
        videoCards.add(VideoCard(videos: videos));
      } else if (metaKey == 'link' && metaValue is Map) {
        extraLinks.add(VideoExtraLink(
          linkText: metaValue['link-text'] ?? '',
          linkUrl: metaValue['link-url'] ?? '',
        ));
      }
    }
    return VideoData(videoCards: videoCards, extraLinks: extraLinks);
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
        if (data == null ||
            (data.videoCards.isEmpty && data.extraLinks.isEmpty)) {
          return const Center(child: Text('No hay videos disponibles.'));
        }

        return ListView(
          children: [
            ...data.videoCards.map((vc) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: vc.videos.map((v) {
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                         title: Text(v.title),
                        // subtitle: Text(v.url),
                        onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerPage(url: v.url, title: v.title),
                          ),
                        );
                      },
                      ),
                    );
                  }).toList(),
                )),
            ...data.extraLinks.map((l) => Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(l.linkText,
                        style: const TextStyle(color: Colors.blue)),
                    subtitle: Text(l.linkUrl),
                    onTap: () async {
                      final uri = Uri.parse(l.linkUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
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
            Flexible(
              child: Image.asset('assets/images/logo.png', height: 40),
            ),
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
                    decoration:
                        const BoxDecoration(color: Color(0xFF0E4B7E)),
                    accountName: Text(fullname ?? 'Usuario',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    accountEmail: Text(userEmail ?? 'No disponible',
                        style: const TextStyle(fontSize: 14)),
                    currentAccountPicture: const CircleAvatar(
                      backgroundImage: NetworkImage(
                          'https://static.vecteezy.com/system/resources/thumbnails/005/545/335/small/user-sign-icon-person-symbol-human-avatar-isolated-on-white-backogrund-vector.jpg'),
                    ),
                    margin: EdgeInsets.zero,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text('Cerrar sesión',
                          style: TextStyle(color: Colors.white)),
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
                          final assetPath =
                              'assets/images/${iconUrl ?? "news"}.png';

                          return ListTile(
                            leading: SizedBox(
                              width: 25,
                              height: 25,
                              child: Image.asset(
                                assetPath,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Image.asset(
                                    'assets/images/news.png',
                                    fit: BoxFit.contain),
                              ),
                            ),
                            title: Text(item['title'] ?? 'Sin título'),
                            textColor: Colors.white,
                            onTap: () {
                              Navigator.pop(context);

                              if (endpoint == null || endpoint.isEmpty) {
                                print('Endpoint vacío');
                                return;
                              }

                              final endLower =
                                  endpoint.toLowerCase().trim();

                              if (endLower == 'home' ||
                                  endLower == 'inicio') {
                                Navigator.pop(context);
                              } else if (endLower == 'podcast') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const PodcastScreen()),
                                );
                              } else if (endLower == 'videos') {
                              } else {
                                print('Abrir endpoint $endpoint');
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
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Inicio'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bookmark), label: 'Marcadores'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}
