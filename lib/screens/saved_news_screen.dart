import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';

final _storage = FlutterSecureStorage();

class SavedNewsScreen extends StatefulWidget {
  @override
  _SavedNewsScreenState createState() => _SavedNewsScreenState();
}

class _SavedNewsScreenState extends State<SavedNewsScreen> {
  List<Map<String, dynamic>> savedNews = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSavedPosts();
  }

  /// 🔹 Función para obtener los posts guardados desde la API 🔹
  Future<void> _fetchSavedPosts() async {
    try {
      String? userId = await _storage.read(key: 'user_id');
      if (userId == null) throw Exception("ID de usuario no encontrado.");

      final token = await _storage.read(key: 'access_token');
      if (token == null) throw Exception("Token de autenticación no encontrado.");

      final response = await http.get(
        Uri.parse(
            'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/saved-posts?app_user_id=$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      );

      print('Código de respuesta: ${response.statusCode}');
      print('Respuesta completa: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] is List) {
          setState(() {
            savedNews = List<Map<String, dynamic>>.from(data['data']);
            isLoading = false;
          });
        } else {
          throw Exception("Formato de datos inesperado.");
        }
      } else {
        throw Exception("Error al cargar los posts guardados.");
      }
    } catch (e) {
      print('Error al obtener los posts guardados: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200], // Fondo similar al de Instagram
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : savedNews.isEmpty
              ? Center(
                  child: Text(
                    "No tienes noticias guardadas.",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                )
              : ListView.builder(
                  itemCount: savedNews.length,
                  itemBuilder: (context, index) {
                    final post = savedNews[index];

                    // Decodificar `meta_key` para extraer imágenes y contenido
                    List<dynamic> metaData = [];
                    if (post['meta_key'] != null && post['meta_key'].isNotEmpty) {
                      try {
                        metaData = json.decode(post['meta_key']);
                      } catch (e) {
                        print("Error al decodificar `meta_key`: $e");
                      }
                    }

                    // Obtener la primera imagen del carrusel
                    String imageUrl = '';
                    for (var item in metaData) {
                      if (item['type'] == 'image-carousel' && item['cards'] is List) {
                        if (item['cards'].isNotEmpty) {
                          imageUrl = item['cards'][0]['image'] ?? '';
                        }
                      }
                    }

                    print("🖼️ URL IMAGEN: $imageUrl");

                    // Obtener la descripción
                    String description = '';
                    for (var item in metaData) {
                      if (item['type'] == 'paragraph' && item.containsKey('paragraph-text')) {
                        description = item['paragraph-text']
                            .replaceAll('<p>', '')
                            .replaceAll('</p>', '');
                        break;
                      }
                    }

                    return Container(
                      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            spreadRadius: 2,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Encabezado con el título y la fecha de publicación
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.grey[300],
                                  backgroundImage: AssetImage('assets/icons/profile_placeholder.png'),
                                  radius: 20,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        post['title'] ?? 'Sin título',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        post['published_at'] ?? 'Sin fecha',
                                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Imagen del post con validación y fallback
                          ClipRRect(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(12),
                              topRight: Radius.circular(12),
                            ),
                            child: imageUrl.isNotEmpty
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: 250,
                                    headers: {
                                      'User-Agent':
                                          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      print("❌ Error al cargar imagen: $imageUrl");
                                      return Image.asset(
                                        'assets/icons/default_news.png',
                                        fit: BoxFit.cover,
                                        height: 250,
                                        width: double.infinity,
                                      );
                                    },
                                  )
                                : Image.asset(
                                    'assets/icons/default_news.png',
                                    fit: BoxFit.cover,
                                    height: 250,
                                    width: double.infinity,
                                  ),
                          ),
                          // Descripción
                          Padding(
  padding: const EdgeInsets.all(12.0),
  child: Html(
    data: description.isNotEmpty ? description : '<p>Sin descripción disponible.</p>',
    style: {
      "p": Style(
        fontSize: FontSize(14),
        color: Colors.black87,
        textAlign: TextAlign.justify,
      ),
      "a": Style(
        color: Colors.blue, // Enlaces en color azul
        textDecoration: TextDecoration.underline, // Subrayado en enlaces
      ),
    },
    onLinkTap: (url, attributes, element) async {
      if (url != null) {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          print("No se pudo abrir el enlace: $url");
        }
      }
    },
  ),
),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
