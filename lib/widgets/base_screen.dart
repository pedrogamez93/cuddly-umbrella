import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ips_app_chileatiende/screens/login_screen.dart';
import 'package:ips_app_chileatiende/screens/video_screen.dart';
import 'package:ips_app_chileatiende/screens/podcast_screen.dart';
import '../screens/logged_in_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/saved_news_screen.dart';
import '../screens/item_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchMenuItems();
    _loadUserData();
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
      if (token == null) {
        throw Exception('No se encontró un token de acceso.');
      }

      final response = await http.get(
        Uri.parse('https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-menu-items'),
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
        throw Exception('Error al cargar los elementos del menú: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error: $e');
      setState(() {
        _isLoadingMenu = false;
      });
    }
  }

  Future<void> _logoutUser(BuildContext context) async {
    try {
      String? token = await _storage.read(key: 'access_token');
      String? userId = await _storage.read(key: 'user_id');

      if (token == null || userId == null) {
        debugPrint("Error: No se encontró el token o el ID de usuario.");
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

      if (response.statusCode == 200) {
        await _storage.delete(key: 'access_token');
        await _storage.delete(key: 'user_id');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      } else {
        debugPrint(" Error al cerrar sesión: ${response.body}");
      }
    } catch (e) {
      debugPrint(" Excepción al cerrar sesión: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;
    if (_selectedEndpoint != null) {
      bodyContent = ItemScreen(
        endpoint: _selectedEndpoint!,
        onItemSelected: (newEndpoint) {
          setState(() {
            _selectedEndpoint = newEndpoint;
          });
        },
      );
    } else {
      bodyContent = _screens[_currentIndex];
    }

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
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            tooltip: 'Notificaciones',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => Navigator.pushNamed(context, '/notifications/recent'),
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
                    decoration: const BoxDecoration(color: Color(0xFF0E4B7E)),
                    accountName: Text(
                      fullname ?? 'Usuario',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    accountEmail: Text(
                      userEmail ?? 'No disponible',
                      style: const TextStyle(fontSize: 14),
                    ),
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
                    : ListView(
                        children: [
                          // Ítem fijo: Notificaciones
                          ListTile(
                            leading: const Icon(Icons.notifications_none, color: Colors.white),
                            title: const Text('Notificaciones', style: TextStyle(color: Colors.white)),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/notifications');
                            },
                          ),
                          const Divider(height: 1, color: Colors.white24),

                          // Ítems dinámicos desde el API
                          ...List.generate(_menuItems.length, (index) {
                            final item = _menuItems[index];
                            final String? endpoint = item['endpoint'];
                            final String? iconUrl = item['icon'];
                            final String assetPath = 'assets/images/${iconUrl ?? "news"}.png';
                            final String title =
                                ((item['title'] as String?)?.trim().isNotEmpty ?? false)
                                    ? item['title']
                                    : 'Sin título';

                            return ListTile(
                              leading: SizedBox(
                                width: 25,
                                height: 25,
                                child: Image.asset(
                                  assetPath,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Image.asset('assets/images/news.png', fit: BoxFit.contain);
                                  },
                                ),
                              ),
                              title: Text(title, style: const TextStyle(color: Colors.white)),
                              onTap: () {
                                Navigator.pop(context);
                                if (endpoint != null && endpoint.isNotEmpty) {
                                  final endLower = endpoint.toLowerCase();

                                  if (endLower == 'home' || endLower == 'inicio') {
                                    setState(() {
                                      _selectedEndpoint = null;
                                      _currentIndex = 0;
                                    });
                                  } else if (endLower == 'podcast') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const PodcastScreen()),
                                    );
                                  } else if (endLower == 'videos') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const VideoScreen()),
                                    );
                                  } else {
                                    setState(() {
                                      _selectedEndpoint = endpoint;
                                    });
                                  }
                                } else {
                                  debugPrint('No se encontró un endpoint para este ítem.');
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
      body: bodyContent,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
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
    );
  }
}
