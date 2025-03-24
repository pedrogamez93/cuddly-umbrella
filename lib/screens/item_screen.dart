import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../screens/profile_screen.dart';
import '../screens/logged_in_screen.dart';
import '../screens/saved_news_screen.dart';
import '../screens/item_detail_screen.dart';

final _storage = FlutterSecureStorage();

class ItemScreen extends StatefulWidget {
  /// Endpoint actual a mostrar
  final String endpoint;

  /// Callback opcional para avisar al padre que se seleccionó otro endpoint.
  /// (Por ejemplo, si quieres que el padre cambie de vista o refresque.)
  final ValueChanged<String>? onItemSelected;

  const ItemScreen({
    Key? key,
    required this.endpoint,
    this.onItemSelected,
  }) : super(key: key);

  @override
  _ItemScreenState createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  List<Map<String, dynamic>> records = [];
  bool isLoading = true;
  String? pageTitle;

  // Menú lateral
  List<dynamic> _menuItems = [];
  bool _isLoadingMenu = true;

  // Datos de usuario
  String? userEmail = 'Cargando...';
  String? fullname = 'Cargando...';

  @override
  void initState() {
    super.initState();
    _fetchItemData();    // Cargar datos según widget.endpoint
    _fetchMenuItems();   // Cargar menú lateral
    _loadUserData();     // Cargar info de usuario
  }

  /// Se llama automáticamente cuando el widget padre reconstruye
  /// y pasa un `endpoint` distinto. Aquí detectamos el cambio y recargamos.
  @override
  void didUpdateWidget(covariant ItemScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint != widget.endpoint) {
      // El endpoint cambió: recargamos datos
      _fetchItemData();
    }
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

  /// Carga el contenido principal de este ItemScreen a partir de `widget.endpoint`
  Future<void> _fetchItemData() async {
    setState(() {
      isLoading = true;
    });

    try {
      String? token = await _storage.read(key: 'access_token');
      if (token == null) {
        throw Exception("Token de autenticación no encontrado");
      }

      final String apiUrl =
          'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-content-by-endpoint?endpoint=${widget.endpoint}';

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      print('Código de respuesta: ${response.statusCode}');
      print('Respuesta completa: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        pageTitle = data['title'] ?? 'Sin título';

        if (data['data'] is List) {
          setState(() {
            records = List<Map<String, dynamic>>.from(data['data']);
            isLoading = false;
          });
        } else if (data['data'] is Map) {
          setState(() {
            records = [data['data']];
            isLoading = false;
          });
        } else {
          throw Exception("Formato de datos inesperado.");
        }
      } else {
        throw Exception(
          'Error en la solicitud: Código ${response.statusCode}, Respuesta: ${response.body}',
        );
      }
    } catch (e) {
      print('Error al obtener datos del item: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  /// Carga el menú lateral
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Aquí se construye un Scaffold propio, con Drawer específico.
      endDrawer: Drawer(
        backgroundColor: const Color(0xFF0F69B4),
        child: Column(
          children: [
            Container(
              color: const Color(0xFF0E4B7E),
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
                        '',
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
                      label: const Text(
                        'Cerrar sesión',
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Menú dinámico
            Expanded(
              child: _isLoadingMenu
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _menuItems.length,
                      itemBuilder: (context, index) {
                        final item = _menuItems[index];
                        final String? endpoint = item['endpoint'];

                        // Obtener la URL del icono desde la API
                        String? iconUrl = item['icon'];
                        String assetPath = 'assets/images/${iconUrl ?? "default_icon"}.png';

                        return ListTile(
                          leading: SizedBox(
                            width: 25,
                            height: 25,
                            child: Image.asset(
                              assetPath,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Image.asset(
                                  'assets/icons/default_icon.png', // Imagen de respaldo
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
                              // Usamos el callback para notificar al padre
                              if (widget.onItemSelected != null) {
                                widget.onItemSelected!(endpoint);
                              } else {
                                // Si no hay callback, por defecto podríamos hacer un push
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ItemScreen(
                                      endpoint: endpoint,
                                      // Reutilizamos el mismo callback, si quieres
                                      onItemSelected: widget.onItemSelected,
                                    ),
                                  ),
                                );
                              }
                            } else {
                              print('No se encontró un endpoint para este ítem.');
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      // Contenido principal
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : records.isNotEmpty
              ? ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 4,
                      child: ListTile(
                        title: Text(record['title'] ?? 'Sin título'),
                        textColor: Colors.black,
                        trailing: ElevatedButton(
                          onPressed: () {
                            print("Registro seleccionado: $record");
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ItemDetailScreen(itemData: record),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Ver Detalle',
                                style: TextStyle(fontSize: 16, color: Colors.white),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                )
              : const Center(child: Text('No se encontraron datos para este ítem.')),
    );
  }
}
