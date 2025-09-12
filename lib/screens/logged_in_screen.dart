import 'dart:convert';
import 'dart:typed_data';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;
import 'package:ips_app_chileatiende/screens/likes_screen.dart';
import 'package:ips_app_chileatiende/screens/login_screen.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../services/appsync_ws.dart';
// (opcional) si quieres banner nativo:
import '../services/local_notifications.dart';


class LoggedInScreen extends StatefulWidget {
   const LoggedInScreen({super.key});
  @override
  _LoggedInScreenState createState() => _LoggedInScreenState();
}

class _LoggedInScreenState extends State<LoggedInScreen> {
  final _storage = FlutterSecureStorage();
  AppSyncWS? _ws;
  List<Map<String, dynamic>> posts = [];
  bool _isLoading = true;
  Map<int, bool> likedPosts = {};
  Map<int, bool> savedPosts = {};
  Map<int, int> postLikesCount = {};
  final Map<String, Future<Uint8List?>> _imageFutures = {};
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _isFetchingMore = false;
  bool _hasMorePages = true; // Se volverá false cuando la API no devuelva más datos

  @override
  void initState() {
    super.initState();
    _bootstrap();
    timeago.setLocaleMessages('es', timeago.EsMessages());
    _loadAccessToken();
    _scrollController.addListener(_onScroll);
    
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
     _ws?.dispose();
  }
  void _onScroll() {
    final threshold = 300; // px antes de llegar al final
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - threshold &&
        !_isFetchingMore &&
        _hasMorePages) {
      _fetchMorePosts();
    }
  }

  Future<void> _bootstrap() async {
    // 1) Obtén email del usuario
    final token = await _storage.read(key: 'auth_token');
    String? email;
    if (token != null && token.isNotEmpty) {
      final claims = JwtDecoder.decode(token);
      email = (claims['email'] ?? claims['user_email'] ?? claims['upn'])?.toString();
    }
    email ??= await _storage.read(key: 'user_email');
    if (email == null) return;

    // 2) Conecta WS (usa tus valores reales)
    _ws = AppSyncWS(
      wssUrl: 'wss://notificaciones-somos-wss.qa.chileatiende.cl/graphql/realtime',
      host: 'avnaqxexqvabxdndyro3w42zfi.appsync-api.us-east-1.amazonaws.com',
      apiKey: '<APP_SYNC_API_KEY_QA>',
      onNotification: (notif) async {
        if (!mounted) return;
        // UI rápida
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🔔 ${notif['title'] ?? 'Notificación'}')),
        );
        // Opcional: notificación local
        // await LocalNotifs.show(notif);
        // TODO: navegar con notif['targetUrl'] o ['targetId'] si existe
      },
    );

    await _ws!.connectAndSubscribe(userEmail: email);
  }



  Future<void> _fetchMorePosts() async {
    _isFetchingMore = true;
    _currentPage += 1;

    final token = await _storage.read(key: 'access_token');
    final userId = await _storage.read(key: 'user_id');
    if (token != null && userId != null) {
      await _fetchPosts(int.parse(userId), token,
          page: _currentPage, append: true);
    }

    _isFetchingMore = false;
  }
  Future<void> _loadAccessToken() async {
    try {
      final token = await _storage.read(key: 'access_token');
      final userId = await _storage.read(key: 'user_id');

      if (token != null && userId != null) {
        await _fetchLikedPosts(userId, token);
        await _fetchSavedPosts(userId, token);
        _currentPage = 1;
        _hasMorePages = true;
        await _fetchPosts(int.parse(userId), token,
            page: _currentPage, append: false);
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error al recuperar el token: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
 
Future<void> _fetchLikedPosts(String userId, String token) async {
  try {
    likedPosts.clear();
    int page = 1;
    bool hasMore = true;

    while (hasMore) {
      final url = Uri.parse(
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-posts-app-user'
        '?app_user_id=$userId&page=$page',
      );
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        print(' Error al obtener likes (página $page): ${response.statusCode}');
        break;
      }

      final data = json.decode(response.body);
      final List<dynamic> items = data['data'] ?? [];

      if (items.isEmpty) {
        hasMore = false;
      } else {
        for (var item in items) {
          final id = item['id'];
          if (id != null) {
            likedPosts[id as int] = true;
          }
        }
        page++;
      }
    }

    setState(() {
    });
  } catch (e) {
    print(' Error en la solicitud HTTP de likes: $e');
  }
}
  Future<void> _fetchPosts(int userId, String token,
      {required int page, required bool append}) async {
    final baseUrl =
        'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/get-posts?app_user_id=$userId';
    final url = '$baseUrl&page=$page';

    final likeUrl =
         'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-posts-app-user'
        '?app_user_id=$userId&page=$page';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                  '(KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      );

      final likeResponse = await http.get(
        Uri.parse(likeUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200 && likeResponse.statusCode == 200) {
        final postData = json.decode(response.body);
        final likeData = json.decode(likeResponse.body);

        if (postData != null && postData['data'] != null) {
          setState(() {
            if (append) {
              posts.addAll(List<Map<String, dynamic>>.from(postData['data']));
            } else {
              posts = List<Map<String, dynamic>>.from(postData['data']);
              likedPosts.clear();
              postLikesCount.clear();
            }
            for (var like in likeData['data']) {
              likedPosts[like['id']] = true;
            }
            for (var post in posts) {
              postLikesCount[post['id']] = post['likes_count'] ?? 0;
            }
            if (postData['data'].isEmpty) _hasMorePages = false;
          });
        } else {
          print('No se encontraron posts.');
          _hasMorePages = false;
        }
      } else {
        print(
            'Error al obtener los posts o likes: ${response.statusCode}/${likeResponse.statusCode}');
        _hasMorePages = false;
      }
    } catch (e) {
      print('Error al realizar la solicitud HTTP: $e');
    }
  }
  Future<Uint8List?> fetchImageBytes(String imageUrl) async {
    try {
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                  '(KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Referer': 'https://chileatiende.gob.cl',
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
        },
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print(' Error: código ${response.statusCode} al descargar la imagen.');
        return null;
      }
    } catch (e) {
      print(' Excepción al descargar la imagen: $e');
      return null;
    }
  }
  Future<Uint8List?> _getImageFuture(String url) {
    if (_imageFutures.containsKey(url)) {
      return _imageFutures[url]!;
    } else {
      final future = fetchImageBytes(url);
      _imageFutures[url] = future;
      return future;
    }
  }

  Widget _buildImageWidget(String url) {
    return FutureBuilder<Uint8List?>(
      future: _getImageFuture(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return Image.asset(
            'assets/images/placeholder.png',
            height: 250,
            fit: BoxFit.cover,
          );
        }
        return Image.memory(
          snapshot.data!,
          height: 250,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              'assets/images/placeholder.png',
              height: 250,
              fit: BoxFit.cover,
            );
          },
        );
      },
    );
  }
  int _currentIndex = 0;

  Widget buildGalleryWidget(List<String> imageUrls) {
    return Column(
      children: [
        CarouselSlider(
          options: CarouselOptions(
            height: 250,
            viewportFraction: 1.0,
            enableInfiniteScroll: false,
            enlargeCenterPage: false,
            onPageChanged: (index, reason) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
          items: imageUrls.map((imageUrl) {
            final encodedUrl = Uri.encodeFull(imageUrl.replaceAll(r'\', ''));
            return ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.network(
                encodedUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: imageUrls.asMap().entries.map((entry) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _currentIndex == entry.key ? 12.0 : 8.0,
              height: 8.0,
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentIndex == entry.key
                    ? Colors.blueAccent
                    : Colors.grey[400],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
  Future<void> _toggleLike(int postId) async {
    final userId = await _storage.read(key: 'user_id');
    final token = await _storage.read(key: 'access_token');

    if (userId == null || token == null) {
      print(" No se encontró el ID de usuario o el token.");
      return;
    }

    try {
      final checkResponse = await http.get(
        Uri.parse(
            'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-posts-app-user?app_user_id=$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      bool isLiked = likedPosts[postId] ?? false;
      if (checkResponse.statusCode == 200) {
        final checkData = json.decode(checkResponse.body);
        isLiked = checkData['data'].any((post) => post['id'] == postId);
      }
      String url = isLiked
          ? 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/remove-like-post'
          : 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-post';

      final body = jsonEncode({
        "app_user_id": userId,
        "post_id": postId.toString(),
      });

      final response = isLiked
          ? await http.delete(
              Uri.parse(url),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              body: body,
            )
          : await http.post(
              Uri.parse(url),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              body: body,
            );

      if (response.statusCode == 200) {
        setState(() {
          likedPosts[postId] = !isLiked;
          postLikesCount[postId] =
              isLiked ? (postLikesCount[postId] ?? 0) - 1 : (postLikesCount[postId] ?? 0) + 1;
        });
        print(isLiked ? ' Like eliminado' : ' Like agregado');
      } else {
        final errorData = json.decode(response.body);
        print(' Error al dar/retirar like: ${errorData['message']}');
      }
    } catch (e) {
      print(' Error en la solicitud HTTP: $e');
    }
  }
  Future<void> _fetchSavedPosts(String userId, String token) async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/saved-posts?app_user_id=$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          savedPosts = {
            for (var post in data['data']) post['id']: true,
          };
        });
      } else {
        print(' Error al obtener los posts guardados: ${response.statusCode}');
      }
    } catch (e) {
      print(' Error en la solicitud HTTP: $e');
    }
  }

  Future<void> _toggleSave(int postId) async {
    final userId = await _storage.read(key: 'user_id');
    final token = await _storage.read(key: 'access_token');

    if (userId == null || token == null) {
      print(" No se encontró el ID de usuario o el token.");
      return;
    }
    try {
      final checkResponse = await http.get(
        Uri.parse(
            'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/saved-posts?app_user_id=$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      bool isSaved = false;
      if (checkResponse.statusCode == 200) {
        final checkData = json.decode(checkResponse.body);
        isSaved = checkData['data'].any((post) => post['id'] == postId);
      } else {
        print(
            '⚠️ Error al verificar si el post está guardado: ${checkResponse.statusCode}');
        return;
      }

      String url = isSaved
          ? 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/remove-saved-post'
          : 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/save-post';

      final body = jsonEncode({
        "app_user_id": userId,
        "post_id": postId.toString(),
      });

      final response = isSaved
          ? await http.delete(
              Uri.parse(url),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              body: body,
            )
          : await http.post(
              Uri.parse(url),
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
              body: body,
            );

      print(" Código de respuesta: ${response.statusCode}");
      print(" Respuesta del servidor: ${response.body}");

      if (response.statusCode == 200) {
        setState(() {
          savedPosts[postId] = !isSaved;
        });
        print(isSaved
            ? ' Post eliminado de marcadores exitosamente.'
            : ' Post guardado exitosamente.');
      } else {
        final errorData = json.decode(response.body);
        print(' Error al guardar/eliminar el post: ${errorData['message']}');
      }
    } catch (e) {
      print(' Error en la solicitud HTTP: $e');
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.home),
            SizedBox(width: 8),
            Text('Últimas Noticias'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : posts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Estuviste mucho tiempo sin actividad',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LoginScreen(),
                            ),
                          );
                        },
                        child: const Text('Ir a login'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAccessToken,
                  child: ListView.builder(
                    controller: _scrollController, // 🔄 MOD – ScrollController
                    itemCount:
                        posts.length + (_hasMorePages ? 1 : 0), // Loader extra
                    itemBuilder: (context, index) {
                      if (index >= posts.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final post = posts[index];
                      final postId = post['id'];
                      List<String> imageUrls = [];
                      String paragraphText = 'Sin descripción';
                      DateTime? publishedDate;

                      if (post['meta_key'] != null && post['meta_key'] is String) {
                        try {
                          final metaKeyList =
                              json.decode(post['meta_key']) as List<dynamic>;
                          for (var metaItem in metaKeyList) {
                            if (metaItem['cards'] is List) {
                              for (var card in metaItem['cards']) {
                                final rawUrl = card['image'];
                                if (rawUrl != null) {
                                  String cleanedUrl =
                                      rawUrl.replaceAll(r'\', '');
                                  cleanedUrl =
                                      Uri.encodeFull(cleanedUrl.trim());
                                  imageUrls.add(cleanedUrl);
                                }
                              }
                            }
                            if (metaItem['paragraph-text'] != null) {
                              paragraphText = metaItem['paragraph-text']
                                  .replaceAll('<p>', '')
                                  .replaceAll('</p>', '');
                            }
                          }
                        } catch (e) {
                          print('Error al procesar meta_key: $e');
                        }
                      }

                      if (post['published_at'] != null) {
                        publishedDate = DateTime.parse(post['published_at']);
                      }
                      final timeAgoText = (publishedDate != null)
                          ? timeago.format(publishedDate, locale: 'es')
                          : 'Fecha desconocida';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 15),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              Text(
                                post['title'] ?? 'Sin título',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time,
                                        size: 18, color: Colors.grey),
                                    const SizedBox(width: 5),
                                    Text(
                                      timeAgoText,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (imageUrls.isEmpty)
                                Image.asset(
                                  'assets/images/placeholder.png',
                                  height: 250,
                                  fit: BoxFit.cover,
                                )
                              else if (imageUrls.length == 1)
                                _buildImageWidget(imageUrls[0])
                              else
                                buildGalleryWidget(imageUrls),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          likedPosts[postId] == true
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: likedPosts[postId] == true
                                              ? Colors.red
                                              : Colors.black,
                                        ),
                                        onPressed: () {
                                          _toggleLike(postId);
                                        },
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  LikesScreen(
                                                      postId: postId.toString()),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          '${postLikesCount[postId] ?? 0} Me gusta',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      savedPosts[postId] == true
                                          ? Icons.bookmark
                                          : Icons.bookmark_border,
                                      color: savedPosts[postId] == true
                                          ? Colors.amber
                                          : Colors.black,
                                    ),
                                    onPressed: () {
                                      _toggleSave(postId);
                                    },
                                  ),
                                ],
                              ),
                              Html(
                                data: paragraphText,
                                style: {
                                  "p": Style(
                                    fontSize: FontSize(14),
                                    textAlign: TextAlign.justify,
                                  ),
                                  "a": Style(
                                    color: Colors.blue,
                                    textDecoration: TextDecoration.underline,
                                  ),
                                },
                                onLinkTap:
                                    (url, attributes, element) async {
                                  if (url != null) {
                                    final uri = Uri.parse(url);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri,
                                          mode: LaunchMode.externalApplication);
                                    } else {
                                      print(
                                          "No se pudo abrir el enlace: $url");
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
