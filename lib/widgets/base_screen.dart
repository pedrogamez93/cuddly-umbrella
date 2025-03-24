import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ips_app_chileatiende/screens/login_screen.dart';
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

  // Variable para almacenar el endpoint seleccionado (null si no se muestra ItemScreen)
  String? _selectedEndpoint;

  // GlobalKey para controlar el Scaffold
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Lista de pantallas (para el bottom navigation)
  final List<Widget> _screens = [
    LoggedInScreen(),
    SavedNewsScreen(),
    ProfileScreen(),
  ];

  // Lista de elementos del menú
  List<dynamic> _menuItems = [];
  bool _isLoadingMenu = true;

  @override
  void initState() {
    super.initState();
    _fetchMenuItems();
    _loadUserData();
  }

  // Función para cargar el email y el nombre completo desde Secure Storage
  Future<void> _loadUserData() async {
    String? email = await _storage.read(key: 'user_email');
    String? fullName = await _storage.read(key: 'user_full_name');

    setState(() {
      userEmail = email ?? 'No disponible';
      fullname = fullName ?? 'Usuario';
    });

    print('Email cargado: $userEmail');
    print('Nombre completo cargado: $fullname');
  }

  // Función para consultar los elementos del menú con el token
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
      print('Error: $e');
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
        body: {
          'app_user_id': userId,
        },
      );

      print("📢 Código de respuesta: ${response.statusCode}");
      print("📢 Respuesta del servidor: ${response.body}");

      if (response.statusCode == 200) {
        // ✅ Cerrar sesión correctamente
        await _storage.delete(key: 'access_token'); // Eliminar token
        await _storage.delete(key: 'user_id'); // Eliminar user ID

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      } else {
        print("⚠️ Error al cerrar sesión: ${response.body}");
        print("usuario: $userId");
      }
    } catch (e) {
      print("❌ Excepción al cerrar sesión: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Decide qué se muestra en el body:
    // 1) Si _selectedEndpoint está definido, muestra la pantalla de ItemScreen
    // 2) Si no, muestra la pantalla correspondiente a _currentIndex
     Widget bodyContent;
    if (_selectedEndpoint != null) {
      bodyContent = ItemScreen(
        endpoint: _selectedEndpoint!,
        // Este callback se llamará desde ItemScreen cuando quieras cambiar a otro endpoint
        onItemSelected: (newEndpoint)  {
          setState(() {
            _selectedEndpoint = newEndpoint;
          });
        },
      );
    } else {
      bodyContent = _screens[_currentIndex];
    }

    return Scaffold(
      key: _scaffoldKey, // Asigna la clave al Scaffold
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
            // Contenedor azul que incluye el encabezado y el botón
            Container(
              color: Color(0xFF0F69B4),
              child: Column(
                children: [
                  // Encabezado del Drawer
                  UserAccountsDrawerHeader(
                    decoration: BoxDecoration(color: Color(0xFF0E4B7E)),
                    accountName: Text(
                      fullname ?? 'Usuario',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    accountEmail: Text(
                      userEmail ?? 'No disponible',
                      style: TextStyle(fontSize: 14),
                    ),
                    currentAccountPicture: CircleAvatar(
                      backgroundImage: NetworkImage(
                        'https://static.vecteezy.com/system/resources/thumbnails/005/545/335/small/user-sign-icon-person-symbol-human-avatar-isolated-on-white-backogrund-vector.jpg', // Imagen de ejemplo
                      ),
                    ),
                    margin: EdgeInsets.zero,
                  ),
                  // Botón de cerrar sesión dentro del fondo azul
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        minimumSize: Size(double.infinity, 48),
                      ),
                      icon: Icon(Icons.logout, color: Colors.white),
                      label: Text(
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
            // Opciones del menú
            Expanded(
              child: Container(
                color: Color(0xFF0F69B4),
                child: _isLoadingMenu
                    ? Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _menuItems.length,
                        itemBuilder: (context, index) {
                          final item = _menuItems[index];
                          String? endpoint = item['endpoint'];

                          // Obtener la URL del icono desde la API
                          String? iconUrl = item['icon'];
                          String assetPath =
                              'assets/images/${iconUrl ?? "assets/images/news.png"}.png';

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
                                // Redirección a LoggedInScreen si el endpoint es home o inicio
                                if (endpoint.toLowerCase() == 'home' || endpoint.toLowerCase() == 'inicio') {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LoggedInScreen(),
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

      body: bodyContent,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          // Cada vez que el usuario toca el BottomNav, volvemos a "ocultar" el ItemScreen
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
