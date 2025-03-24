import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'single_post_screen.dart'; // Importar la vista del post individual

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = FlutterSecureStorage();
  String? profileImage = 'https://via.placeholder.com/150'; // Imagen por defecto
  String? fullname = 'Cargando...';
  String? email = 'Cargando...';
  List<Map<String, dynamic>> likedPosts = []; // Ahora almacenamos más datos de los posts
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  /// **🔹 Cargar datos del usuario desde Secure Storage**
  Future<void> _loadUserData() async {
    String? storedFullname = await _storage.read(key: 'user_full_name');
    String? storedEmail = await _storage.read(key: 'user_email');
    String? storedUserId = await _storage.read(key: 'user_id');
    String? storedToken = await _storage.read(key: 'access_token');

    setState(() {
      fullname = storedFullname ?? 'No disponible';
      email = storedEmail ?? 'No disponible';
    });

    if (storedUserId != null && storedToken != null) {
      await _fetchLikedPosts(int.parse(storedUserId), storedToken);
    }
  }

  /// **🔹 Obtener los posts marcados con "Me gusta" y extraer datos relevantes**
  Future<void> _fetchLikedPosts(int userId, String token) async {
    final url =
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-posts-app-user?app_user_id=$userId';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null) {
          List<Map<String, dynamic>> tempLikedPosts = [];

          for (var post in data['data']) {
            try {
              List<dynamic> metaKeyList = json.decode(post['meta_key']);
              String? firstImage;
              String? content;

              // Extraer la primera imagen del primer `image-carousel`
              for (var metaKey in metaKeyList) {
                if (metaKey['type'] == 'image-carousel' && metaKey['cards'] is List) {
                  if (metaKey['cards'].isNotEmpty) {
                    firstImage = metaKey['cards'][0]['image'];
                  }
                  break;
                }
              }

              // Extraer el contenido del primer `paragraph`
              for (var metaKey in metaKeyList) {
                if (metaKey['type'] == 'paragraph') {
                  content = metaKey['paragraph-text'];
                  break;
                }
              }

              tempLikedPosts.add({
                'id': post['id'],
                'title': post['title'],
                'image': firstImage ?? 'https://via.placeholder.com/150',
                'content': content ?? 'Sin contenido disponible',
                'likes': post['likes_count'],
                'comments': post['comments_count'],
                'published_at': post['published_at'],
              });

            } catch (e) {
              print('⚠️ Error al procesar meta_key en post ${post['id']}: $e');
            }
          }

          setState(() {
            likedPosts = tempLikedPosts;
            isLoading = false;
          });
        }
      } else {
        print('⚠️ Error al obtener los posts con "Me gusta": ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Error al realizar la solicitud HTTP: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? Center(child: CircularProgressIndicator()) // Indicador de carga
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // **Foto de perfil**
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: NetworkImage(profileImage!),
                    ),
                    const SizedBox(height: 16),

                    // **Nombre**
                    Text(
                      fullname!,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // **Correo electrónico**
                    Text(
                      email!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // **Sección "Mis Me gusta"**
                    Row(
                      children: const [
                        Icon(Icons.favorite, color: Colors.black),
                        SizedBox(width: 8),
                        Text(
                          'Mis me gusta',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // **Mostrar imágenes de posts con "Me gusta"**
                    likedPosts.isEmpty
                        ? const Text(
                            'No tienes posts marcados con "Me gusta".',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          )
                        : GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: likedPosts.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, // 3 columnas
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemBuilder: (context, index) {
                              final post = likedPosts[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SinglePostScreen(post: post),
                                    ),
                                  );
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    post['image'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Image.asset(
                                        'assets/icons/default_image.png',
                                        fit: BoxFit.cover,
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ),
    );
  }
}
