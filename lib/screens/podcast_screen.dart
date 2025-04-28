import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ips_app_chileatiende/screens/item_screen.dart';
import 'package:ips_app_chileatiende/screens/logged_in_screen.dart';
import 'package:ips_app_chileatiende/screens/login_screen.dart';
import 'package:ips_app_chileatiende/screens/profile_screen.dart';
import 'package:ips_app_chileatiende/screens/saved_news_screen.dart';
import 'package:ips_app_chileatiende/screens/video_screen.dart';
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
  _PodcastScreenState createState() => _PodcastScreenState();
}

class _PodcastScreenState extends State<PodcastScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? userEmail = 'Cargando...';
  String? fullname = 'Cargando...';
  String? _selectedEndpoint;
  bool _isLoadingMenu = true;
  List<dynamic> _menuItems = [];
  int _currentIndex = 0; 
  final List<Widget> _screens = [
    LoggedInScreen(),   
    SavedNewsScreen(),   
    ProfileScreen(),     
  ];
  late Future<List<PodcastAccordion>> _futurePodcasts;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchMenuItems();
    _futurePodcasts = _fetchPodcastData();
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
      print('Error al cargar menú: $e');
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
        print("⚠️ Error: No se encontró el token o el ID de usuario.");
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
        Navigator.pushReplacementNamed(context, '/');
      } else {
        print(" Error al cerrar sesión: ${response.body}");
      }
    } catch (e) {
      print(" Excepción al cerrar sesión: $e");
    }
  }
  Future<List<PodcastAccordion>> _fetchPodcastData() async {
    String? token = await _storage.read(key: 'access_token');
    if (token == null) {
      throw Exception("Token de autenticación no encontrado");
    }

    final url = Uri.parse(
      'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-content-by-endpoint?endpoint=podcast',
    );

    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonData = json.decode(response.body);

      final metadata = jsonData['data']['metadata'] as List<dynamic>?;
      if (metadata == null) {
        return [];
      }
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
        final String accordionTitle = metaValue['accordion-title'] ?? 'Sin título';
        final List<dynamic> inputLinks = metaValue['input'] ?? [];

        final links = inputLinks.map((obj) {
          return PodcastLink(
            linkText: obj['link-text'] ?? 'Sin texto',
            linkUrl: obj['link-url'] ?? '',
          );
        }).toList();

        result.add(PodcastAccordion(
          title: accordionTitle,
          links: links,
        ));
      }
    }
    return result;
  }
  @override
  Widget build(BuildContext context) {
    Widget bodyContent2;
    if (_selectedEndpoint != null) {
      bodyContent2 = ItemScreen(
        endpoint: _selectedEndpoint!,
        onItemSelected: (newEndpoint) {
          setState(() {
            _selectedEndpoint = newEndpoint;
          });
        },
      );
    } else {
      bodyContent2 = _screens[_currentIndex];
    }
    final bodyContent = FutureBuilder<List<PodcastAccordion>>(
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

        return ListView.builder(
          itemCount: accordions.length,
          itemBuilder: (context, index) {
            final accordion = accordions[index];
            return Card(
              child: ExpansionTile(
                title: Text(
                  accordion.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                children: accordion.links.map((link) {
                  return ListTile(
                    title: Text(link.linkText),
                    subtitle: Text(link.linkUrl),
                    onTap: () async {
                      final mp3Uri = Uri.parse(link.linkUrl);
                      if (await canLaunchUrl(mp3Uri)) {
                        await launchUrl(
                          mp3Uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        print('No se pudo abrir: ${link.linkUrl}');
                      }
                    },
                  );
                }).toList(),
              ),
            );
          },
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
                    : ListView.builder(
                        itemCount: _menuItems.length,
                        itemBuilder: (context, index) {
                          final item = _menuItems[index];
                          String? endpoint = item['endpoint'];

                          String? iconUrl = item['icon'];
                          String assetPath = 'assets/images/${iconUrl ?? "assets/images/news.png"}.png';

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
                                  Navigator.pop(context); // Cierra el Drawer
                                  setState(() {
                                    _selectedEndpoint = null; // Asegurarse de que no se esté mostrando ItemScreen
                                    _currentIndex = 0; // Selecciona la pestaña "Inicio"
                                  });
                                } else if (endLower == 'noticias') {
                                  setState(() {
                                    _selectedEndpoint = 'news';
                                  });
                                } else if (endLower == 'podcast') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const PodcastScreen(),
                                    ),
                                  );
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
                                print('No se encontró un endpoint para este ítem.');
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
      body: _selectedEndpoint != null ? bodyContent2 : bodyContent,
   bottomNavigationBar: BottomNavigationBar(
  currentIndex: _currentIndex,
  onTap: (int index) {
    print("BottomNavigationBar: se tocó el índice $index");
    Navigator.pop(context);
    setState(() {
      _selectedEndpoint = null; // Asegurarse de que no se esté mostrando ItemScreen
      _currentIndex = index;    // Actualiza el índice para mostrar la pantalla correspondiente
    });
    if (index == 0) {
      print("Acción para Inicio: Mostrando LoggedInScreen");
    } else if (index == 1) {
      print("Acción para Marcadores: Mostrando SavedNewsScreen");
    } else if (index == 2) {
      print("Acción para Perfil: Mostrando ProfileScreen");
    }
    print("Nuevo _currentIndex: $_currentIndex, _selectedEndpoint: $_selectedEndpoint");
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
