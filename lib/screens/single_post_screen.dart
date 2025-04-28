import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;
import 'package:carousel_slider/carousel_slider.dart';
import 'likes_screen.dart'; // Asegúrate de tener importado LikesScreen
class SinglePostScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  const SinglePostScreen({Key? key, required this.post}) : super(key: key);

  @override
  State<SinglePostScreen> createState() => _SinglePostScreenState();
}

class _SinglePostScreenState extends State<SinglePostScreen> {
  late final List<String> images; 
  int _currentIndex = 0; 
  final Map<String, Future<Uint8List?>> _imageCache = {}; 
  List<Map<String, dynamic>> likes = [];
  bool isLikesLoading = true;

  @override
  void initState() {
    super.initState();
    images = _extractImages(widget.post);
    print("InitState: Se han extraído ${images.length} imagen(es): $images");
    _fetchLikes(); // Se sigue invocando para mantener la función, aunque la visualización sea en otra vista
  }
  List<String> _extractImages(Map<String, dynamic> post) {
    if (post['images'] is List) {
      List<String> list = List<String>.from(post['images']);
      print("Se encontró la lista 'images' en el post: $list");
      return list;
    }
    final rawMeta = post['meta_key']?.toString();
    if (rawMeta != null && rawMeta.isNotEmpty) {
      print("Meta key encontrada: $rawMeta");
      List<dynamic>? metaList;
      try {
        metaList = json.decode(rawMeta);
      } catch (e) {
        print("Error al decodificar meta_key la primera vez: $e");
        try {
          metaList = json.decode(
              rawMeta.replaceAll(r'\\', r'\\\\').replaceAll(r'\/', '/'));
        } catch (e) {
          print("Error al decodificar meta_key en el segundo intento: $e");
        }
      }
      if (metaList is List) {
        for (var item in metaList) {
          print("Procesando item de meta: $item");
          if (item['type'] == 'image-carousel' && item['cards'] is List) {
            List<String> list = List<String>.from(
              (item['cards'] as List).map((e) => (e['image'] ?? '').toString()),
            );
            print("Se encontró carrusel de imágenes: $list");
            return list;
          }
        }
      }
    }
    if (post['image'] != null) {
      print("Fallback a imagen única: ${post['image']}");
      return [post['image'] as String];
    }
    print("No se encontraron imágenes en el post.");
    return [];
  }
  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      print("Descargando imagen de: $url");
      final response = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          'Referer': 'https://chileatiende.gob.cl',
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        },
      );
      print("Respuesta de la descarga (status ${response.statusCode}) para: $url");
      return response.statusCode == 200 ? response.bodyBytes : null;
    } catch (e) {
      print("Error al descargar imagen de $url: $e");
      return null;
    }
  }

  Future<Uint8List?> _getImage(String url) {
    return _imageCache.putIfAbsent(url, () => _fetchImageBytes(url));
  }

  Widget _imageWidget(String url) {
    if (url.isEmpty) {
      print("URL vacía, mostrando placeholder.");
      return Container(
        color: Colors.grey[300],
        child: const Center(child: Text('Imagen no disponible')),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _getImage(url),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          print("Cargando imagen para URL: $url");
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          print("No se pudo cargar la imagen de URL: $url");
          return Container(
            color: Colors.grey[300],
            child: const Center(child: Text('Imagen no disponible')),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 250,
        );
      },
    );
  }
  Widget _buildGallery(List<String> urls) {
    print("Construyendo el carousel con ${urls.length} imagen(es).");
    return Column(
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: 250,
            viewportFraction: 1.0,
            enableInfiniteScroll: urls.length > 1,
            onPageChanged: (index, reason) {
              setState(() {
                _currentIndex = index;
              });
              print("Carousel page changed a: $index, reason: $reason");
            },
          ),
          items: urls.map((raw) {
            final cleaned = raw.replaceAll(r'\\', '').replaceAll(r'\/', '/');
            final encoded = Uri.encodeFull(cleaned);
            print("Mostrando imagen en carousel: $encoded");
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _imageWidget(encoded),
            );
          }).toList(),
        ),
        if (urls.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: urls.asMap().entries.map((entry) {
              final active = _currentIndex == entry.key;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 12 : 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? Colors.blueAccent : Colors.grey[400],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
  Future<void> _fetchLikes() async {
    final postId = widget.post['id'].toString();
    final url = 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/likes-post?post_id=$postId';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] != null && data['data'] is List) {
          setState(() {
            likes = List<Map<String, dynamic>>.from(data['data']);
            isLikesLoading = false;
          });
        } else {
          setState(() {
            isLikesLoading = false;
          });
        }
      } else {
        print("Error al obtener likes del post, status code: ${response.statusCode}");
        setState(() {
          isLikesLoading = false;
        });
      }
    } catch (e) {
      print("Error al obtener likes: $e");
      setState(() {
        isLikesLoading = false;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.post['title'] ?? 'Detalle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            images.isNotEmpty
                ? _buildGallery(images)
                : Container(
                    height: 250,
                    color: Colors.grey[300],
                    child: const Center(child: Text('Imagen no disponible')),
                  ),
            const SizedBox(height: 16),
            Text(
              'Publicado el: ${widget.post['published_at'] ?? ''}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        LikesScreen(postId: widget.post['id'].toString()),
                  ),
                );
              },
              
              child: Row(
                children: [
                   const Icon(Icons.favorite, color: Colors.red),
                  Text(
                    '${widget.post['likes'] ?? 0} Me gusta',
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 4),
                 
                ],
              ),
            ),
            const SizedBox(height: 16),
            Html(data: widget.post['content'] ?? ''),
          ],
        ),
      ),
    );
  }
}
