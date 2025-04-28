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
  final String endpoint;
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
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> records = [];
  bool isLoading = true;       // spinner inicial
  bool _isLoadingPage = false; // spinner de página siguiente
  bool _hasMore = true;        // se vuelve false cuando la API ya no trae datos
  int _currentPage = 1;        // página actual

  String? pageTitle;
  List<dynamic> _menuItems = [];
  bool _isLoadingMenu = true;
  String? userEmail = 'Cargando...';
  String? fullname = 'Cargando...';

  @override
  void initState() {
    super.initState();

    _fetchItemData(page: _currentPage); // primera página
    _fetchMenuItems();
    _loadUserData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadNextPage();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ItemScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endpoint != widget.endpoint) {
      _currentPage = 1;
      _hasMore = true;
      records.clear();
      _fetchItemData(page: _currentPage);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  Future<void> _loadUserData() async {
    final email = await _storage.read(key: 'user_email');
    final fullName = await _storage.read(key: 'user_full_name');
    setState(() {
      userEmail = email ?? 'No disponible';
      fullname = fullName ?? 'Usuario';
    });
  }
  Future<void> _loadNextPage() async {
    if (_isLoadingPage || !_hasMore) return;
    _currentPage += 1;
    await _fetchItemData(page: _currentPage, append: true);
  }
  Future<void> _fetchItemData({required int page, bool append = false}) async {
    if (!append) setState(() => isLoading = true);
    setState(() => _isLoadingPage = true);

    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) throw Exception('Token de autenticación no encontrado');

      final apiUrl =
          'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/menu-content/get-content-by-endpoint?page=$page&endpoint=${widget.endpoint}';

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<Map<String, dynamic>> newRecords =
            List<Map<String, dynamic>>.from(data['data'] ?? []);

        setState(() {
          if (append) {
            records.addAll(newRecords);
          } else {
            records = newRecords;
          }
          pageTitle = data['title'] ?? 'Sin título';
          _hasMore = newRecords.isNotEmpty;
          isLoading = false;
        });
      } else {
        throw Exception('Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error al obtener datos: $e');
      setState(() {
        _hasMore = false;
        isLoading = false;
      });
    } finally {
      setState(() => _isLoadingPage = false);
    }
  }
  Future<void> _fetchMenuItems() async {
    try {
      final token = await _storage.read(key: 'access_token');
      if (token == null) throw Exception('No se encontró token');

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
        throw Exception('Error menú ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error menú: $e');
      setState(() => _isLoadingMenu = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: _buildDrawer(context),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildNewsList(),
    );
  }
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0F69B4),
      child: Column(
        children: [
          _buildDrawerHeader(),
          Expanded(child: _buildMenuList()),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      color: const Color(0xFF0E4B7E),
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF0E4B7E)),
            accountName: Text(fullname ?? 'Usuario'),
            accountEmail: Text(userEmail ?? 'No disponible'),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white),
            margin: EdgeInsets.zero,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuList() {
    if (_isLoadingMenu) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: _menuItems.length,
      itemBuilder: (context, index) {
        final item = _menuItems[index];
        final endpoint = item['endpoint'] as String?;
        final iconUrl = item['icon'];
        final assetPath = 'assets/images/${iconUrl ?? "default_icon"}.png';

        return ListTile(
          leading: SizedBox(
            width: 25,
            height: 25,
            child: Image.asset(assetPath, fit: BoxFit.contain, errorBuilder: (_, __, ___) {
              return Image.asset('assets/icons/default_icon.png');
            }),
          ),
          title: Text(item['title'] ?? 'Sin título', style: const TextStyle(color: Colors.white)),
          onTap: () {
            Navigator.pop(context);
            if (endpoint != null && endpoint.isNotEmpty) {
              widget.onItemSelected?.call(endpoint);
            }
          },
        );
      },
    );
  }

  Widget _buildNewsList() {
    if (records.isEmpty) {
      return const Center(child: Text('No se encontraron datos.'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: records.length + 1, // +1 para el loader final
      itemBuilder: (context, index) {
        if (index == records.length) {
          return _isLoadingPage
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const SizedBox.shrink();
        }

        final record = records[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 4,
          child: ListTile(
            title: Text(record['title'] ?? 'Sin título'),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemDetailScreen(itemData: record),
                  ),
                );
              },
            child: Row(
  mainAxisSize: MainAxisSize.min,
  children: const [
    Text(
      'Ver Detalle',
      style: TextStyle(color: Colors.white),
    ),
    SizedBox(width: 8),
    Icon(Icons.arrow_forward, size: 18, color: Colors.white),
  ],
),

            ),
          ),
        );
      },
    );
  }
}
