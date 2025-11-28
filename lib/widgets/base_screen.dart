// lib/widgets/base_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'package:ips_app_chileatiende/screens/login_screen.dart';
import 'package:ips_app_chileatiende/screens/video_screen.dart';
import 'package:ips_app_chileatiende/screens/podcast_screen.dart';
import '../screens/logged_in_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/saved_news_screen.dart';
import '../screens/item_screen.dart';
import '../screens/posts_search_screen.dart';

final _storage = FlutterSecureStorage();

class BaseScreen extends StatefulWidget {
  @override
  _BaseScreenState createState() => _BaseScreenState();
}

class _BaseScreenState extends State<BaseScreen> {
  int _currentIndex = 0;
  String? userEmail = 'Cargando...';
  String? fullname = 'Cargando...';
  String? _selectedEndpoint;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<Widget> _screens = [
    LoggedInScreen(),
    SavedNewsScreen(),
    ProfileScreen(),
  ];

  List<dynamic> _menuItems = [];
  bool _isLoadingMenu = true;

  // ===== Historias desde API =====
  List<Story> _stories = [];
  bool _loadingStories = true;

  // ===== Notificaciones =====
  int _unreadCount = 0;
  Timer? _notifTimer;

  static const String _apiBase =
      'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app';

  @override
  void initState() {
    super.initState();
    _fetchMenuItems();
    _loadUserData();
    _loadStories();
    _loadUnreadNotifications(); // primera carga

    // 🔁 refrescar contador cada 5 segundos
    _notifTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadUnreadNotifications();
    });
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, String>> _authHeaders({bool urlEncoded = false}) async {
    final token = await _storage.read(key: 'access_token');
    if (token == null) throw Exception('Token ausente');
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (urlEncoded) 'Content-Type': 'application/x-www-form-urlencoded',
    };
  }

  Future<String> _currentUserId() async {
    final uid = await _storage.read(key: 'user_id');
    if (uid == null) throw Exception('user_id ausente');
    return uid;
  }

  Future<void> _loadUserData() async {
    final email = await _storage.read(key: 'user_email');
    final fullName = await _storage.read(key: 'user_full_name');
    setState(() {
      userEmail = email ?? 'No disponible';
      fullname = fullName ?? 'Usuario';
    });
  }

  Future<void> _fetchMenuItems() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$_apiBase/menu-content/get-menu-items'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _menuItems = data['data'];
          _isLoadingMenu = false;
        });
      } else {
        throw Exception('Error al cargar el menú: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoadingMenu = false);
    }
  }

  Future<void> _loadStories() async {
    try {
      final uid = await _currentUserId();
      final headers = await _authHeaders();
      final url = '$_apiBase/get-stories?app_user_id=$uid';
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final List list = jsonData['data'];
        final parsed = list.map((e) => Story.fromJson(e)).toList();
        setState(() {
          _stories = parsed;
          _loadingStories = false;
        });
      } else {
        setState(() => _loadingStories = false);
        debugPrint(
            'Error al obtener historias: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Error al cargar historias: $e');
      setState(() => _loadingStories = false);
    }
  }

  // ====== CONTADOR DE NOTIFICACIONES (CAMPANA) ======

  /// Carga el número de notificaciones sin leer para la campanita.
  /// Usa AppSync (GraphQL) con getNotifications y cuenta:
  /// viewed == false && !deleted && deletedAt == null
  Future<void> _loadUnreadNotifications() async {
    try {
      final appsyncUrl = dotenv.env['APPSYNC_HTTP_URL'] ?? '';
      final appsyncKey = dotenv.env['APPSYNC_API_KEY'] ?? '';

      if (appsyncUrl.isEmpty || appsyncKey.isEmpty) {
        debugPrint('[notifications] AppSync env vars missing, skip');
        return;
      }

      String? email = (await _storage.read(key: 'user_email'))?.trim();
      if (email == null || email.isEmpty) {
        debugPrint('[notifications] email vacío, skip');
        return;
      }

      final uri = Uri.parse(appsyncUrl);

      final payload = {
        'query': '''
          query GetNotifications(\$userEmail: String!) {
            getNotifications(userEmail: \$userEmail) {
              id
              title
              message
              viewed
              viewedAt
              deleted
              deletedAt
              timestamp
            }
          }
        ''',
        'variables': {
          'userEmail': email,
        },
      };

      final headers = {
        'Content-Type': 'application/json',
        'x-api-key': appsyncKey,
      };

      final resp = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      );

      debugPrint(
          '[notifications] status=${resp.statusCode} url=$uri body=${resp.body}');

      if (resp.statusCode != 200) {
        debugPrint('[notifications] error HTTP: ${resp.body}');
        return;
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final List<dynamic> rawList =
          (decoded['data']?['getNotifications'] as List?) ?? <dynamic>[];

      int unread = 0;

      for (final item in rawList) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item as Map);

        final bool viewed = m['viewed'] == true;
        final deleted = m['deleted'];
        final deletedAt = m['deletedAt'];

        final bool deletedFlag = (deleted == true ||
            deleted == 1 ||
            (deleted is String && deleted.toLowerCase() == 'true'));

        final bool hasDeletedAt =
            deletedAt != null && deletedAt.toString().trim().isNotEmpty;

        final bool isUnread = !viewed && !deletedFlag && !hasDeletedAt;

        debugPrint(
          '[notifications] item id=${m['id']} '
          'viewed=$viewed deleted=$deleted deletedAt=$deletedAt '
          'isUnread=$isUnread',
        );

        if (isUnread) unread++;
      }

      debugPrint(
          '[notifications] raw=${rawList.length} filtered_unread=$unread');

      if (!mounted) return;
      setState(() {
        _unreadCount = unread;
      });
    } catch (e) {
      debugPrint('[notifications] exception: $e');
    }
  }

  Future<void> _toggleLike(Story story) async {
    try {
      final uid = await _currentUserId();
      final wasLiked = story.liked;
      setState(() => story.liked = !wasLiked);

      final headers = await _authHeaders(urlEncoded: true);
      final url =
          wasLiked ? '$_apiBase/remove-like-story' : '$_apiBase/like-story';

      final resp = await (wasLiked
          ? http.delete(Uri.parse(url),
              headers: headers,
              body: {'app_user_id': uid, 'story_id': story.id.toString()})
          : http.post(Uri.parse(url),
              headers: headers,
              body: {'app_user_id': uid, 'story_id': story.id.toString()}));

      if (resp.statusCode != 200) {
        setState(() => story.liked = wasLiked); // revertir si falla
        debugPrint('Error like/unlike: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('Excepción like/unlike: $e');
    }
  }

  Future<void> _logoutUser(BuildContext context) async {
    try {
      final headers = await _authHeaders(urlEncoded: true);
      final uid = await _currentUserId();

      final response = await http.post(
        Uri.parse('$_apiBase/register-logout'),
        headers: headers,
        body: {'app_user_id': uid},
      );

      if (response.statusCode == 200) {
        await _storage.deleteAll();
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => LoginScreen()));
      } else {
        debugPrint("Error al cerrar sesión: ${response.body}");
      }
    } catch (e) {
      debugPrint("Excepción al cerrar sesión: $e");
    }
  }

  // ===== Barra de Historias (estilo Instagram) =====
  Widget _storiesBar() {
    if (_loadingStories) {
      return const SizedBox(
        height: 110,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_stories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 110,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: _stories.length + 1, // +1 para "Tu historia"
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _AddStoryItem(
              label: 'Tu historia',
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Agregar historia (próximamente)')),
              ),
            );
          }

          final story = _stories[index - 1];
          final cover =
              story.coverUrl ?? _placeholderForStory(story.title);
          return _StoryItem(
            name: story.title,
            imageUrl: cover,
            liked: story.liked,
            isVideo: story.firstIsVideo && story.coverUrl == null,
            onTapLike: () => _toggleLike(story),
            onTap: () => _openStoriesViewer(initialIndex: index - 1),
          );
        },
      ),
    );
  }

  String _placeholderForStory(String title) =>
      'https://source.unsplash.com/featured/?chile,${Uri.encodeComponent(title.isEmpty ? "paisaje" : title)}';

  void _openStoriesViewer({required int initialIndex}) {
    if (_stories.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height,
          child: _StoriesViewer(
            stories: _stories,
            initialIndex: initialIndex,
            placeholderFor: _placeholderForStory,
            onToggleLike: (s) => _toggleLike(s),
            onOpenComments: (story) => _openCommentsSheet(ctx, story),
          ),
        );
      },
    );
  }

  void _openCommentsSheet(BuildContext parentCtx, Story story) {
    showModalBottomSheet(
      context: parentCtx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _CommentsSheet(
          apiBase: _apiBase,
          storage: _storage,
          story: story,
          placeholderFor: _placeholderForStory,
        ),
      ),
    );
  }

  bool get _isHomeView => _selectedEndpoint == null && _currentIndex == 0;

  @override
  Widget build(BuildContext context) {
    final bodyContent = _selectedEndpoint != null
        ? ItemScreen(
            endpoint: _selectedEndpoint!,
            onItemSelected: (newEndpoint) =>
                setState(() => _selectedEndpoint = newEndpoint),
          )
        : _screens[_currentIndex];

    final effectiveBody = _isHomeView
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _storiesBar(),
              const Divider(height: 1),
              Expanded(child: bodyContent),
            ],
          )
        : bodyContent;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Image.asset('assets/images/logo.png', height: 40))
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          // 🔍 botón de búsqueda tipo Instagram
          IconButton(
            tooltip: 'Buscar posts',
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PostsSearchScreen()),
              );
            },
          ),
          // 🔔 campana con badge
          IconButton(
            tooltip: 'Notificaciones',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none),
                if (_unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Center(
                        child: Text(
                          _unreadCount > 99
                              ? '99+'
                              : '$_unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () async {
              await Navigator.pushNamed(context, '/notifications/recent');
              // refrescar contador al volver
              if (mounted) _loadUnreadNotifications();
            },
          ),
          IconButton(
            tooltip: 'Menú',
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
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
                    accountName: Text(fullname ?? 'Usuario',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    accountEmail: Text(userEmail ?? 'No disponible',
                        style: const TextStyle(fontSize: 14)),
                    currentAccountPicture: const CircleAvatar(
                      backgroundImage: NetworkImage(
                        'https://static.vecteezy.com/system/resources/thumbnails/005/545/335/small/user-sign-icon-person-symbol-human-avatar-isolated-on-white-backogrund-vector.jpg',
                      ),
                    ),
                    margin: EdgeInsets.zero,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text('Cerrar sesión',
                          style: TextStyle(color: Colors.white)),
                      onPressed: () async => await _logoutUser(context),
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
                    : ListView(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.notifications_none,
                                color: Colors.white),
                            title: const Text('Notificaciones',
                                style: TextStyle(color: Colors.white)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(
                                  context, '/notifications/recent');
                            },
                          ),
                          const Divider(
                              height: 1, color: Colors.white24),
                          ...List.generate(_menuItems.length, (index) {
                            final item = _menuItems[index];
                            final String? endpoint = item['endpoint'];
                            final String? iconUrl = item['icon'];
                            final String assetPath =
                                'assets/images/${iconUrl ?? "news"}.png';
                            final String title =
                                ((item['title'] as String?)
                                            ?.trim()
                                            .isNotEmpty ??
                                        false)
                                    ? item['title']
                                    : 'Sin título';

                            return ListTile(
                              leading: SizedBox(
                                width: 25,
                                height: 25,
                                child: Image.asset(
                                  assetPath,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      Image.asset(
                                          'assets/images/news.png',
                                          fit: BoxFit.contain),
                                ),
                              ),
                              title: Text(title,
                                  style: const TextStyle(
                                      color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                if (endpoint != null &&
                                    endpoint.isNotEmpty) {
                                  final endLower =
                                      endpoint.toLowerCase();
                                  if (endLower == 'home' ||
                                      endLower == 'inicio') {
                                    setState(() {
                                      _selectedEndpoint = null;
                                      _currentIndex = 0;
                                    });
                                  } else if (endLower == 'podcast') {
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const PodcastScreen()));
                                  } else if (endLower == 'videos') {
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const VideoScreen()));
                                  } else {
                                    setState(() =>
                                        _selectedEndpoint = endpoint);
                                  }
                                }
                              },
                            );
                          }),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
      body: effectiveBody,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() {
          _selectedEndpoint = null;
          _currentIndex = index;
        }),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home), label: 'Inicio'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bookmark), label: 'Marcadores'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

// ================== Modelos y utilidades ==================

class Story {
  final int id;
  final String title;
  final bool featured;
  final int likesCount;
  final int commentsCount;
  final int viewsCount;
  final String? publishedAt;
  final String? expiresAt;
  final List<StoryMedia> media; // imágenes / videos parseados del meta
  bool liked;

  Story({
    required this.id,
    required this.title,
    required this.featured,
    required this.likesCount,
    required this.commentsCount,
    required this.viewsCount,
    this.publishedAt,
    this.expiresAt,
    required this.media,
    this.liked = false,
  });

  // portada: prioriza imagen; si no hay, usa primer video
  String? get coverUrl {
    final img = media.firstWhere(
      (m) => m.isImage,
      orElse: () =>
          media.isNotEmpty ? media.first : StoryMedia(type: 'none', url: ''),
    );
    return img.url.isEmpty ? null : img.url;
  }

  bool get firstIsVideo => media.isNotEmpty && media.first.isVideo;

  factory Story.fromJson(Map<String, dynamic> json) {
    final media = _extractMedia(json['meta_key']);
    return Story(
      id: json['id'],
      title: (json['title'] ?? '').toString(),
      featured: (json['featured'] ?? false) == true,
      likesCount: json['likes_count'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
      viewsCount: json['views_count'] ?? 0,
      publishedAt: json['published_at'],
      expiresAt: json['expires_at'],
      media: media,
      liked: (json['liked'] ?? false) == true,
    );
  }

  // Parse de meta_key (string JSON o map) para extraer media
  static List<StoryMedia> _extractMedia(dynamic metaKey) {
    final List<StoryMedia> items = [];
    if (metaKey == null) return items;

    dynamic meta;
    try {
      meta = (metaKey is String) ? jsonDecode(metaKey) : metaKey;
    } catch (_) {
      return items;
    }

    // meta puede ser lista con un objeto, o directamente un objeto con "cards"
    List<dynamic> cards = [];
    if (meta is List &&
        meta.isNotEmpty &&
        meta.first is Map &&
        meta.first['cards'] is List) {
      cards = (meta.first['cards'] as List);
    } else if (meta is Map && meta['cards'] is List) {
      cards = (meta['cards'] as List);
    }

    String cleanUrl(String u) {
      // limpia slashes escapados y backslashes, y normaliza https://
      var s =
          u.replaceAll(r'\/', '/').replaceAll('\\/', '/').replaceAll('\\', '');
      if (s.startsWith('https:/') && !s.startsWith('https://')) {
        s = s.replaceFirst('https:/', 'https://');
      }
      if (s.startsWith('http:/') && !s.startsWith('http://')) {
        s = s.replaceFirst('http:/', 'http://');
      }
      return s;
    }

    for (final c in cards) {
      if (c is! Map) continue;
      final type = (c['type'] ?? '').toString().toLowerCase();
      final urlRaw = (c['url'] ?? '').toString();
      final url = cleanUrl(urlRaw);

      if (type == 'image' && url.isNotEmpty) {
        items.add(StoryMedia(type: 'image', url: url));
      } else if (type == 'video' && url.isNotEmpty) {
        items.add(StoryMedia(type: 'video', url: url));
      } else if (type == 'multimedia-carousel') {
        // soporte por si vienen items internos
        final inner = c['items'];
        if (inner is List) {
          for (final it in inner) {
            if (it is! Map) continue;
            final t = (it['type'] ?? 'image').toString().toLowerCase();
            final u = cleanUrl((it['url'] ?? '').toString());
            if (u.isEmpty) continue;
            items.add(StoryMedia(
                type: t == 'video' ? 'video' : 'image', url: u));
          }
        }
      }
    }

    return items;
  }
}

class StoryMedia {
  final String type; // 'image' | 'video'
  final String url;
  const StoryMedia({required this.type, required this.url});
  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';
}

// ================== Widgets UI (barra / visor) ==================

class _AddStoryItem extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _AddStoryItem({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFB0BEC5), Color(0xFFE0E0E0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const CircleAvatar(
                  radius: 32,
                  backgroundImage: NetworkImage(
                    'https://static.vecteezy.com/system/resources/thumbnails/005/545/335/small/user-sign-icon-person-symbol-human-avatar-isolated-on-white-backogrund-vector.jpg',
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Color(0xFF0F69B4),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Center(
                      child:
                          Icon(Icons.add, size: 16, color: Colors.white)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 72,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final String name;
  final String imageUrl;
  final bool liked;
  final bool isVideo;
  final VoidCallback? onTap;
  final VoidCallback? onTapLike;

  const _StoryItem({
    required this.name,
    required this.imageUrl,
    this.liked = false,
    this.isVideo = false,
    this.onTap,
    this.onTapLike,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFFA95B),
                      Color(0xFFE72D8B),
                      Color(0xFF7B4AED)
                    ],
                  ),
                ),
                child: Container(
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  padding: const EdgeInsets.all(2),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(imageUrl,
                            fit: BoxFit.cover, errorBuilder:
                                (_, __, ___) {
                          return const ColoredBox(
                              color: Colors.black12);
                        }),
                        if (isVideo)
                          const Align(
                            alignment: Alignment.center,
                            child: Icon(Icons.play_circle_fill,
                                color: Colors.white70, size: 26),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: GestureDetector(
                  onTap: onTapLike,
                  child: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Colors.red : Colors.grey,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 72,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Visor full-screen (Instagram-like con videos y acceso a comentarios) =====
class _StoriesViewer extends StatefulWidget {
  final List<Story> stories;
  final int initialIndex;
  final String Function(String title) placeholderFor;
  final ValueChanged<Story> onToggleLike;
  final ValueChanged<Story> onOpenComments;

  const _StoriesViewer({
    required this.stories,
    required this.initialIndex,
    required this.placeholderFor,
    required this.onToggleLike,
    required this.onOpenComments,
  });

  @override
  State<_StoriesViewer> createState() => _StoriesViewerState();
}

class _StoriesViewerState extends State<_StoriesViewer> {
  late final PageController _storyController;
  late int _storyIndex;

  @override
  void initState() {
    super.initState();
    _storyIndex =
        widget.initialIndex.clamp(0, widget.stories.length - 1);
    _storyController = PageController(initialPage: _storyIndex);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          PageView.builder(
            controller: _storyController,
            onPageChanged: (i) => setState(() => _storyIndex = i),
            itemCount: widget.stories.length,
            itemBuilder: (context, i) {
              final s = widget.stories[i];
              return _StorySlides(
                story: s,
                placeholderFor: widget.placeholderFor,
                onDoubleTapLike: () {
                  setState(() {
                    s.liked = !s.liked;
                  });
                  widget.onToggleLike(s);
                },
                onRequestNextStory: () {
                  if (i < widget.stories.length - 1) {
                    _storyController.nextPage(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut);
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                onRequestPrevStory: () {
                  if (i > 0) {
                    _storyController.previousPage(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut);
                  }
                },
                onTapLikeButton: () {
                  setState(() {
                    s.liked = !s.liked;
                  });
                  widget.onToggleLike(s);
                },
                onOpenComments: () => widget.onOpenComments(s),
              );
            },
          ),

          // Top bar (título + cerrar)
          Positioned(
            top: 16,
            left: 12,
            right: 12,
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.white24,
                  child:
                      Icon(Icons.bolt, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.stories[_storyIndex].title.isEmpty
                        ? 'Historia'
                        : widget.stories[_storyIndex].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () =>
                      Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Slides internos de una historia (imágenes y/o videos)
class _StorySlides extends StatefulWidget {
  final Story story;
  final String Function(String title) placeholderFor;
  final VoidCallback onRequestNextStory;
  final VoidCallback onRequestPrevStory;
  final VoidCallback onDoubleTapLike;
  final VoidCallback onTapLikeButton;
  final VoidCallback onOpenComments;

  const _StorySlides({
    required this.story,
    required this.placeholderFor,
    required this.onRequestNextStory,
    required this.onRequestPrevStory,
    required this.onDoubleTapLike,
    required this.onTapLikeButton,
    required this.onOpenComments,
  });

  @override
  State<_StorySlides> createState() => _StorySlidesState();
}

class _StorySlidesState extends State<_StorySlides> {
  static const Duration kImageDuration = Duration(seconds: 5);

  int _slideIndex = 0;
  Timer? _imageTimer;
  VideoPlayerController? _videoController;
  bool _muted = true;
  bool _isLongPressing = false;

  List<StoryMedia> get _slides => widget.story.media.isEmpty
      ? [
          StoryMedia(
              type: 'image',
              url: widget.placeholderFor(widget.story.title))
        ]
      : widget.story.media;

  @override
  void initState() {
    super.initState();
    _prepareCurrentSlide(autoPlay: true);
  }

  @override
  void didUpdateWidget(covariant _StorySlides oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.story.id != widget.story.id) {
      _disposeMedia();
      _slideIndex = 0;
      _prepareCurrentSlide(autoPlay: true);
    }
  }

  @override
  void dispose() {
    _disposeMedia();
    super.dispose();
  }

  void _disposeMedia() {
    _imageTimer?.cancel();
    _imageTimer = null;
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _videoController = null;
  }

  void _prepareCurrentSlide({bool autoPlay = false}) async {
    _disposeMedia(); // limpia anterior
    final current = _slides[_slideIndex];

    if (current.isImage) {
      if (autoPlay) {
        _imageTimer = Timer(kImageDuration, _nextSlideOrStory);
      }
      setState(() {}); // repintar
    } else if (current.isVideo) {
      final ctrl =
          VideoPlayerController.networkUrl(Uri.parse(current.url));
      _videoController = ctrl;
      await ctrl.initialize();
      ctrl.setLooping(false);
      ctrl.setVolume(_muted ? 0.0 : 1.0);
      ctrl.addListener(_onVideoTick);
      if (autoPlay && !_isLongPressing) ctrl.play();
      setState(() {});
    }
  }

  void _onVideoTick() {
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final d = ctrl.value.duration;
    final p = ctrl.value.position;
    if (d > Duration.zero &&
        p >= d - const Duration(milliseconds: 200)) {
      _nextSlideOrStory();
    }
  }

  void _pause() {
    _imageTimer?.cancel();
    if (_videoController?.value.isPlaying ?? false) {
      _videoController?.pause();
    }
  }

  void _resume() {
    if (_slides[_slideIndex].isImage) {
      _imageTimer =
          Timer(kImageDuration, _nextSlideOrStory);
    } else if (_slides[_slideIndex].isVideo) {
      if (!(_videoController?.value.isPlaying ?? true)) {
        _videoController?.play();
      }
    }
  }

  void _nextSlideOrStory() {
    if (_slideIndex < _slides.length - 1) {
      setState(() => _slideIndex++);
      _prepareCurrentSlide(autoPlay: true);
    } else {
      widget.onRequestNextStory();
    }
  }

  void _prevSlideOrStory() {
    if (_slideIndex > 0) {
      setState(() => _slideIndex--);
      _prepareCurrentSlide(autoPlay: false);
    } else {
      widget.onRequestPrevStory();
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _videoController?.setVolume(_muted ? 0.0 : 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final current = _slides[_slideIndex];
    final isVideo = current.isVideo;

    Widget content;
    if (current.isImage) {
      content = Image.network(
        current.url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Colors.black),
      );
    } else {
      final ctrl = _videoController;
      if (ctrl == null || !ctrl.value.isInitialized) {
        content = const Center(
            child:
                CircularProgressIndicator(color: Colors.white));
      } else {
        content = FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ctrl.value.size.width,
            height: ctrl.value.size.height,
            child: VideoPlayer(ctrl),
          ),
        );
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) {
        _isLongPressing = true;
        _pause();
      },
      onLongPressEnd: (_) {
        _isLongPressing = false;
        _resume();
      },
      onDoubleTap: widget.onDoubleTapLike,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,

          // gradiente inferior para legibilidad
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // Tap zones (izq/der)
          Row(
            children: [
              Expanded(
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _prevSlideOrStory)),
              Expanded(
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _nextSlideOrStory)),
            ],
          ),

          // segmentos (progreso) por slide (simple: activo/inactivo)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(
              children: List.generate(_slides.length, (i) {
                final active = i == _slideIndex;
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: EdgeInsets.only(
                        right: i == _slides.length - 1 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white24,
                      borderRadius:
                          BorderRadius.circular(999),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Bottom actions (like + mute si video + comentarios)
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Row(
              children: [
                // Like
                InkWell(
                  onTap: widget.onTapLikeButton,
                  borderRadius: BorderRadius.circular(32),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      widget.story.liked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: widget.story.liked
                          ? Colors.redAccent
                          : Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Abrir comentarios
                InkWell(
                  onTap: widget.onOpenComments,
                  borderRadius: BorderRadius.circular(32),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.mode_comment_outlined,
                        color: Colors.white, size: 24),
                  ),
                ),
                const Spacer(),
                if (isVideo)
                  IconButton(
                    icon: Icon(
                        _muted
                            ? Icons.volume_off
                            : Icons.volume_up,
                        color: Colors.white),
                    onPressed: _toggleMute,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================== Comentarios de historias ==================

class _CommentsSheet extends StatefulWidget {
  final String apiBase;
  final FlutterSecureStorage storage;
  final Story story;
  final String Function(String title) placeholderFor;

  const _CommentsSheet({
    required this.apiBase,
    required this.storage,
    required this.story,
    required this.placeholderFor,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  bool _loading = true;
  bool _posting = false;
  int _page = 1;
  bool _hasMore = true;
  final List<Comment> _comments = [];

  // reply state
  Comment? _replyTo;

  @override
  void initState() {
    super.initState();
    _fetchPage();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers({bool urlEncoded = false}) async {
    final token = await widget.storage.read(key: 'access_token');
    if (token == null) throw Exception('Token ausente');
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (urlEncoded) 'Content-Type': 'application/x-www-form-urlencoded',
    };
  }

  Future<String> _uid() async {
    final uid = await widget.storage.read(key: 'user_id');
    if (uid == null) throw Exception('user_id ausente');
    return uid;
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 120) {
      _fetchPage();
    }
  }

  Future<void> _fetchPage() async {
    try {
      setState(() => _loading = true);
      final headers = await _headers();
      final url =
          '${widget.apiBase}/get-comments?story_id=${widget.story.id}&page=$_page&per_page=20';
      final resp = await http.get(Uri.parse(url), headers: headers);
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        final List data = body['data'] ?? [];
        final items = data.map((e) => Comment.fromJson(e)).toList();
        setState(() {
          _comments.addAll(items);
          _page++;
          _hasMore = items.isNotEmpty;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Error get-comments: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleLikeComment(Comment c) async {
    try {
      final uid = await _uid();
      final headers = await _headers(urlEncoded: true);
      final wasLiked = c.liked;
      setState(() {
        c.liked = !wasLiked;
        c.likesCount += c.liked ? 1 : -1;
        if (c.likesCount < 0) c.likesCount = 0;
      });

      final url = wasLiked
          ? '${widget.apiBase}/remove-like-comment'
          : '${widget.apiBase}/like-comment';

      final resp = await (wasLiked
          ? http.delete(Uri.parse(url),
              headers: headers,
              body: {
                  'app_user_id': uid,
                  'comment_id': c.id.toString()
                })
          : http.post(Uri.parse(url),
              headers: headers,
              body: {
                  'app_user_id': uid,
                  'comment_id': c.id.toString()
                }));

      if (resp.statusCode != 200) {
        // revertir
        setState(() {
          c.liked = wasLiked;
          c.likesCount += wasLiked ? 1 : -1;
          if (c.likesCount < 0) c.likesCount = 0;
        });
      }
    } catch (e) {
      debugPrint('like-comment error: $e');
    }
  }

  Future<void> _postComment() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _posting = true);
    try {
      final uid = await _uid();
      final headers = await _headers(urlEncoded: true);

      // Si hay replyTo, mandamos comment_id; si no, story_id
      final body = {
        'app_user_id': uid,
        'content': text,
        if (_replyTo == null) 'story_id': widget.story.id.toString(),
        if (_replyTo != null) 'comment_id': _replyTo!.id.toString(),
      };

      final resp = await http.post(
        Uri.parse('${widget.apiBase}/save-comment'),
        headers: headers,
        body: body,
      );

      if (resp.statusCode == 200) {
        // recargar primera página rápidamente (o insertar optimista)
        _inputCtrl.clear();
        setState(() {
          _comments.clear();
          _page = 1;
          _hasMore = true;
          _replyTo = null;
        });
        await _fetchPage();
        if (mounted) {
          FocusScope.of(context).unfocus();
        }
      } else {
        debugPrint(
            'save-comment error: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('save-comment ex: $e');
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _loadReplies(Comment parent) async {
    if (parent.repliesLoaded || parent.loadingReplies) return;
    setState(() => parent.loadingReplies = true);
    try {
      final headers = await _headers();
      final url =
          '${widget.apiBase}/get-child-comments?comment_id=${parent.id}&page=1&per_page=50';
      final resp =
          await http.get(Uri.parse(url), headers: headers);
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        final List data = body['data'] ?? [];
        parent.replies =
            data.map((e) => Comment.fromJson(e)).toList();
        parent.repliesLoaded = true;
      }
    } catch (e) {
      debugPrint('get-child-comments error: $e');
    } finally {
      setState(() => parent.loadingReplies = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover =
        widget.story.coverUrl ??
        widget.placeholderFor(widget.story.title);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            ClipOval(
              child: Image.network(
                cover,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.black12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.story.title.isEmpty
                    ? 'Historia'
                    : widget.story.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.of(context).maybePop(),
          )
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _comments.clear();
                  _page = 1;
                  _hasMore = true;
                });
                await _fetchPage();
              },
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: _comments.length + 1,
                itemBuilder: (context, index) {
                  if (index == _comments.length) {
                    if (_loading) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(
                            vertical: 20),
                        child: Center(
                            child:
                                CircularProgressIndicator()),
                      );
                    }
                    if (!_hasMore && _comments.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                            child: Text(
                                'Sé el primero en comentar')),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final c = _comments[index];
                  return _CommentTile(
                    comment: c,
                    onLike: () => _toggleLikeComment(c),
                    onReply: () =>
                        setState(() => _replyTo = c),
                    onExpandReplies: () =>
                        _loadReplies(c),
                  );
                },
              ),
            ),
          ),

          // Barra de escribir comentario
          const Divider(height: 1),
          if (_replyTo != null)
            Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Respondiendo a ${_replyTo!.authorName}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _replyTo = null),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 8.0),
                      child: Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Añade un comentario...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(
                                Radius.circular(24))),
                        contentPadding:
                            EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _posting
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                              child:
                                  CircularProgressIndicator(
                                      strokeWidth: 2)))
                      : IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _postComment,
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

class Comment {
  final int id;
  final String content;
  final String authorName;
  final String? createdAt;
  int likesCount;
  int childCount;

  bool liked; // auxiliar UI (el API no lo trae explícito)
  bool loadingReplies = false;
  bool repliesLoaded = false;
  List<Comment> replies = [];

  Comment({
    required this.id,
    required this.content,
    required this.authorName,
    required this.createdAt,
    required this.likesCount,
    required this.childCount,
    this.liked = false,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    final names =
        (json['names'] ?? '').toString().trim();
    final surnames =
        (json['surnames'] ?? '').toString().trim();
    final author =
        [names, surnames].where((s) => s.isNotEmpty).join(' ');
    return Comment(
      id: json['id'],
      content: (json['content'] ?? '').toString(),
      authorName: author.isEmpty
          ? (json['email'] ?? 'Usuario')
          : author,
      createdAt: json['created_at'],
      likesCount: json['likes_count'] ?? 0,
      childCount: json['child_comments_count'] ?? 0,
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onExpandReplies;

  const _CommentTile({
    required this.comment,
    required this.onLike,
    required this.onReply,
    required this.onExpandReplies,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // fila principal
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFE0E0E0),
                child: Icon(Icons.person,
                    size: 18, color: Colors.white70),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(comment.authorName,
                        style: const TextStyle(
                            fontWeight:
                                FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(comment.content),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _formatDate(comment.createdAt),
                          style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: onReply,
                          child: Text('Responder',
                              style: TextStyle(
                                  color:
                                      Colors.grey.shade700,
                                  fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton(
                    icon: Icon(
                      comment.liked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: comment.liked
                          ? Colors.red
                          : Colors.grey,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(),
                    onPressed: onLike,
                  ),
                  const SizedBox(height: 4),
                  Text('${comment.likesCount}',
                      style:
                          const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),

          // botón "Ver respuestas"
          if (comment.childCount > 0 &&
              !comment.repliesLoaded)
            Padding(
              padding: const EdgeInsets.only(
                  left: 48, top: 6),
              child: InkWell(
                onTap: onExpandReplies,
                child: Text(
                  'Ver ${comment.childCount} respuesta(s)',
                  style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),

          // loader de respuestas
          if (comment.loadingReplies)
            const Padding(
              padding:
                  EdgeInsets.only(left: 48, top: 6),
              child: SizedBox(
                  height: 20,
                  child: Row(children: [
                    CircularProgressIndicator(
                        strokeWidth: 2)
                  ])),
            ),

          // respuestas cargadas
          if (comment.repliesLoaded &&
              comment.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                  left: 40, top: 8),
              child: Column(
                children: comment.replies
                    .map((r) => Padding(
                          padding:
                              const EdgeInsets.only(
                                  bottom: 10),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    Color(0xFFE0E0E0),
                                child: Icon(Icons.person,
                                    size: 16,
                                    color:
                                        Colors.white70),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(r.authorName,
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                            fontSize: 13)),
                                    const SizedBox(
                                        height: 2),
                                    Text(r.content),
                                    const SizedBox(
                                        height: 4),
                                    Text(
                                      _formatDate(
                                          r.createdAt),
                                      style: TextStyle(
                                          color: Colors
                                              .grey
                                              .shade600,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt =
          DateTime.tryParse(iso)?.toLocal();
      if (dt == null) return '';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}
