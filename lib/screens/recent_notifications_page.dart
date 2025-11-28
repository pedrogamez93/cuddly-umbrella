// lib/screens/recent_notifications_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/notification_item.dart';
import '../services/notifications_api.dart';

// otras pantallas (drawer / bottom nav)
import '../screens/login_screen.dart';
import '../screens/video_screen.dart';
import '../screens/podcast_screen.dart';
import '../screens/item_screen.dart';
import '../screens/saved_news_screen.dart';
import '../screens/profile_screen.dart';
import '../widgets/base_screen.dart';
import 'item_detail_screen.dart';
import 'notification_detail_screen.dart';

final _storage = FlutterSecureStorage();

class RecentNotificationsPage extends StatefulWidget {
  const RecentNotificationsPage({super.key});

  @override
  State<RecentNotificationsPage> createState() => _RecentNotificationsPageState();
}

class _RecentNotificationsPageState extends State<RecentNotificationsPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- Header / Drawer ---
  String? _userEmail = 'Cargando...';
  String? _fullName = 'Cargando...';
  List<dynamic> _menuItems = [];
  bool _isLoadingMenu = true;

  // --- Notificaciones ---
  late final NotificationsApi _api = NotificationsApi(
    endpoint: dotenv.env['APPSYNC_HTTP_URL'] ?? '',
    apiKey: dotenv.env['APPSYNC_API_KEY'] ?? '',
  );

  bool _loading = true;
  static const int _limit = 10;
  List<NotificationItem> _items = [];

  // bottom nav
  int _bottomIndex = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _fetchMenuItems();
  }

  Future<void> _bootstrap() async {
    String? email = (await _storage.read(key: 'user_email'))?.trim();
    if (email == null || email.isEmpty) {
      final jwt = await _storage.read(key: 'auth_token');
      if (jwt != null && jwt.isNotEmpty) {
        final claims = JwtDecoder.decode(jwt);
        email = (claims['email'] ?? claims['user_email'] ?? claims['upn'])?.toString();
      }
    }
    final fullName = await _storage.read(key: 'user_full_name');

    setState(() {
      _userEmail = email?.isNotEmpty == true ? email : 'No disponible';
      _fullName = (fullName ?? 'Usuario').trim().isEmpty ? 'Usuario' : fullName;
    });

    await _load();
  }

  Future<void> _fetchMenuItems() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) throw Exception('No se encontró un token de acceso.');
      final response = await http.get(
        Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-menu-items'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
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
      debugPrint('Error menú: $e');
      setState(() => _isLoadingMenu = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final email = (_userEmail ?? '').trim();
      if (email.isEmpty || email == 'No disponible') {
        setState(() {
          _items = [];
          _loading = false;
        });
        return;
      }

      // Trae todas y deja solo las 10 más recientes (por timestamp).
      final list = await _api.fetch(userEmail: email, onlyUnread: false);
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() => _items = list.take(_limit).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar notificaciones: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllViewed() async {
    try {
      final email = (_userEmail ?? '').trim();
      if (email.isEmpty || email == 'No disponible') return;
      await _api.markAllAsViewed(email);
      // Optimista: marcar las visibles como vistas
      setState(() {
        _items = _items.map((n) => n.copyWith(viewed: true, viewedAt: DateTime.now())).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _markViewedOne(NotificationItem n) async {
    _applyOptimisticViewed(n.id);
    try {
      await _api.markNotificationAsViewed(n.id);
    } catch (e) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _applyOptimisticViewed(String id) {
    setState(() {
      final idx = _items.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        _items[idx] = _items[idx].copyWith(viewed: true, viewedAt: DateTime.now());
      }
    });
  }

  // ---------- Navegación desde una notificación (igual que en NotificationsPage) ----------
  Future<void> _openFromNotification(NotificationItem n) async {
    await _markViewedOne(n);

    final hint = _guessTargetFromNotification(n);

    // Abre URL si aparece
    if (hint.url != null && hint.url!.startsWith('http')) {
      final uri = Uri.parse(hint.url!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    // Si hay ID => busca detalle y abre
    if (hint.id != null && hint.id!.isNotEmpty) {
      try {
        final token = await _storage.read(key: 'access_token');
        if (token == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay sesión para abrir el contenido.')),
          );
          return;
        }
        final uri = Uri.parse(
          'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/news/get-page?page_id=${hint.id}',
        );
        final resp = await http.get(uri, headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        });

        if (resp.statusCode == 200) {
          final jsonBody = json.decode(resp.body) as Map<String, dynamic>;
          final data = jsonBody['data'];
          if (data != null && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ItemDetailScreen(itemData: Map<String, dynamic>.from(data)),
              ),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('[RecentNotificationsPage] detalle por id falló: $e');
      }
    }

    // Fallback a pantalla completa con toda la información
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationDetailScreen(notification: n),
      ),
    );
  }

  // Intenta deducir id/url desde la notificación (mensaje puede venir en JSON o con links)
  _TargetHint _guessTargetFromNotification(NotificationItem n) {
    String? id = n.targetId;
    String? url = n.targetUrl;

    final msg = n.message.trim();

    // 1) Si el mensaje es JSON o contiene JSON
    Map<String, dynamic>? parsed;
    try {
      if (msg.startsWith('{') && msg.endsWith('}')) {
        parsed = json.decode(msg);
      } else {
        final start = msg.indexOf('{');
        final end = msg.lastIndexOf('}');
        if (start >= 0 && end > start) {
          parsed = json.decode(msg.substring(start, end + 1));
        }
      }
    } catch (_) {}
    if (parsed != null) {
      id  ??= parsed['targetId']?.toString() ?? parsed['id']?.toString();
      url ??= parsed['targetUrl']?.toString() ?? parsed['url']?.toString();
    }

    // 2) URL en texto (string normal con escapes)
    final mUrl = RegExp('https?:\\/\\/[^\\s)\'"<>]+').firstMatch(msg);
    if (mUrl != null) url ??= mUrl.group(0);

    // 3) page_id=123 / post_id=123 / id: 123 en el texto
    final mId = RegExp(
      r'(?:page_id|post_id|id)\s*[:=]\s*([0-9]+)',
      caseSensitive: false,
    ).firstMatch(msg);
    if (mId != null) id ??= mId.group(1);

    return _TargetHint(id: id, url: url);
  }

  void _onBottomTap(int index) {
    setState(() => _bottomIndex = index);
    if (index == 0) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BaseScreen()));
      }
    } else if (index == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SavedNewsScreen()));
    } else if (index == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProfileScreen()));
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            tooltip: 'Marcar todas como vistas',
            icon: const Icon(Icons.done_all),
            onPressed: _items.isEmpty ? null : _markAllViewed,
          ),
          IconButton(
            tooltip: 'Menú',
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),

      endDrawer: _DrawerMenuRecent(
        fullName: _fullName,
        userEmail: _userEmail,
        isLoadingMenu: _isLoadingMenu,
        menuItems: _menuItems,
        onLogout: () async {
          try {
            final token = await _storage.read(key: 'access_token');
            final userId = await _storage.read(key: 'user_id');
            if (token == null || userId == null) return;

            final response = await http.post(
              Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/register-logout'),
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
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            }
          } catch (_) {}
        },
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_items.isEmpty
              ? const Center(child: Text('Sin notificaciones'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Notificaciones recientes',
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/notifications'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Ver todas',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        Expanded(
                          child: ListView.separated(
                            itemCount: _items.length, // solo 10
                            separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.6),
                            itemBuilder: (_, i) {
                              final n = _items[i];
                              return _NotificationRow(
                                title: n.title.isEmpty ? '(Sin título)' : n.title,
                                message: n.message,
                                dateTime: n.timestamp,
                                viewed: n.viewed,
                                onTap: () => _openFromNotification(n),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                )),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomIndex,
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

class _TargetHint {
  final String? id;
  final String? url;
  _TargetHint({this.id, this.url});
}

// -------- Drawer específico para la vista de recientes --------
class _DrawerMenuRecent extends StatelessWidget {
  const _DrawerMenuRecent({
    required this.fullName,
    required this.userEmail,
    required this.isLoadingMenu,
    required this.menuItems,
    required this.onLogout,
  });

  final String? fullName;
  final String? userEmail;
  final bool isLoadingMenu;
  final List<dynamic> menuItems;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(children: [
        Container(
          color: const Color(0xFF0F69B4),
          child: Column(children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF0E4B7E)),
              accountName: Text(fullName ?? 'Usuario',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              accountEmail: Text(userEmail ?? 'No disponible', style: const TextStyle(fontSize: 14)),
              currentAccountPicture: const CircleAvatar(
                backgroundImage: NetworkImage(
                  'https://static.vecteezy.com/system/resources/thumbnails/005/545/335/small/user-sign-icon-person-symbol-human-avatar-isolated-on-white-backogrund-vector.jpg',
                ),
              ),
              margin: EdgeInsets.zero,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 48),
                ),
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text('Cerrar sesión', style: TextStyle(color: Colors.white)),
                onPressed: onLogout,
              ),
            ),
          ]), 
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF0F69B4),
            child: isLoadingMenu
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      // acceso a la lista completa
                      ListTile(
                        leading: const Icon(Icons.notifications_none, color: Colors.white),
                        title: const Text('Notificaciones (todas)', style: TextStyle(color: Colors.white)),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/notifications');
                        },
                      ),
                      // acceso a recientes
                      ListTile(
                        leading: const Icon(Icons.fiber_new, color: Colors.white),
                        title: const Text('Notificaciones recientes', style: TextStyle(color: Colors.white)),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/notifications/recent');
                        },
                      ),
                      const Divider(height: 1, color: Colors.white24),
                      ...menuItems.map((item) {
                        final String? endpoint = item['endpoint'];
                        final String? iconUrl = item['icon'];
                        final String assetPath = 'assets/images/${iconUrl ?? "news"}.png';
                        final String title =
                            ((item['title'] as String?)?.trim().isNotEmpty ?? false) ? item['title'] : 'Sin título';
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
                          title: Text(title, style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            if (endpoint == null || endpoint.isEmpty) return;
                            final e = endpoint.toLowerCase();
                            if (e == 'podcast') {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const PodcastScreen()));
                            } else if (e == 'videos') {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const VideoScreen()));
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ItemScreen(endpoint: endpoint, onItemSelected: (_) {}), 
                                ),
                              );
                            }
                          },
                        );
                      }),
                    ],
                  ),
          ),
        ),
      ]),
    );
  }
}

// --------- Ítem de lista ----------
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.title,
    required this.message,
    required this.dateTime,
    required this.viewed,
    required this.onTap,
  });

  final String title;
  final String message;
  final DateTime dateTime;
  final bool viewed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]);

    final Color? bg = viewed ? Colors.grey[200] : Colors.white;
    final FontWeight titleWeight = viewed ? FontWeight.w500 : FontWeight.w700;

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // avatar y punto azul si no leída
              Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: viewed ? Colors.grey[400] : Colors.grey[300],
                ),
                child: !viewed
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.25, color: theme.textTheme.bodyMedium?.color),
                        children: [
                          TextSpan(text: title, style: TextStyle(fontWeight: titleWeight)),
                          const TextSpan(text: '  '),
                          TextSpan(text: message),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(_relativeTime(dateTime), style: small),
                      ],
                    ),
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
