import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ips_app_chileatiende/screens/likes_screen.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:carousel_slider/carousel_slider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:typed_data';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';


class LoggedInScreen extends StatefulWidget {
  @override
  _LoggedInScreenState createState() => _LoggedInScreenState();
}

class _LoggedInScreenState extends State<LoggedInScreen> {
  final _storage = FlutterSecureStorage();
  List<Map<String, dynamic>> posts = [];
  bool _isLoading = true;
  Map<int, bool> likedPosts = {}; // Estado de los "Me gusta"
  Map<int, bool> savedPosts = {}; // Estado de los "Guardados"
  Map<int, int> postLikesCount = {}; // Cantidad de likes por post


  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('es', timeago.EsMessages());
    _loadAccessToken();
  }

 Future<void> _loadAccessToken() async {
  try {
    final token = await _storage.read(key: 'access_token');
    final userId = await _storage.read(key: 'user_id');

    if (token != null && userId != null) {
      await _fetchLikedPosts(userId, token); // 🔥 Consultar likes antes de mostrar los posts
       await _fetchSavedPosts(userId, token);
      await _fetchPosts(int.parse(userId), token); // Luego cargar los posts
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


Future<void> _fetchPosts(int userId, String token) async {
  final url = 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/get-posts?app_user_id=$userId';
  final likeUrl = 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-posts-app-user?app_user_id=$userId';

  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
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

      print(postData);

      if (postData != null && postData['data'] != null) {
        setState(() {
          posts = List<Map<String, dynamic>>.from(postData['data']);

          likedPosts.clear();
          postLikesCount.clear();

          // Guardamos los likes en un mapa
          for (var like in likeData['data']) {
            likedPosts[like['id']] = true;
          }

          // Guardamos la cantidad de likes en otro mapa
          for (var post in posts) {
            postLikesCount[post['id']] = post['likes_count'] ?? 0;
          }
        });
      } else {
        print('No se encontraron posts.');
      }
    } else {
      print('Error al obtener los posts o likes: ${response.statusCode} / ${likeResponse.statusCode}');
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
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Referer': 'https://somos-media.qa.chileatiende.cl', // 🔥 IMPORTANTE: Ajusta según el servidor
      },
    );

    if (response.statusCode == 200) {
      return response.bodyBytes; // Retorna los bytes de la imagen
    } else {
      print("⚠️ Error al obtener la imagen (${response.statusCode}): $imageUrl");
      return null;
    }
  } catch (e) {
    print("❌ Excepción al obtener imagen: $e");
    return null;
  }
}


 
Future<void> _toggleLike(int postId) async {
  final userId = await _storage.read(key: 'user_id');
  final token = await _storage.read(key: 'access_token');

  if (userId == null || token == null) {
    print("⚠️ No se encontró el ID de usuario o el token.");
    return;
  }

  try {
    // **Paso 1: Consultar si el post ya tiene "Me gusta"**
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

    // **Paso 2: Determinar si se debe agregar o quitar el "Me gusta"**
    String url = isLiked
        ? 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/remove-like-post'
        : 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-post';

    final body = jsonEncode({
      "app_user_id": userId,
      "post_id": postId.toString(),
    });

    // **Paso 3: Enviar la solicitud adecuada**
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
        likedPosts[postId] = !isLiked; // Cambia el estado visualmente
        postLikesCount[postId] =
            isLiked ? (postLikesCount[postId] ?? 0) - 1 : (postLikesCount[postId] ?? 0) + 1;
      });
      print(isLiked ? '❌ Like eliminado' : '❤️ Like agregado');
    } else {
      final errorData = json.decode(response.body);
      print('⚠️ Error al dar/retirar like: ${errorData['message']}');
    }
  } catch (e) {
    print('⚠️ Error en la solicitud HTTP: $e');
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
            for (var post in data['data']) post['id']: true // Marcar como guardado
          };
        });
      } else {
        print('⚠️ Error al obtener los posts guardados: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Error en la solicitud HTTP: $e');
    }
  }


 Future<void> _toggleSave(int postId) async {
  final userId = await _storage.read(key: 'user_id');
  final token = await _storage.read(key: 'access_token');

  if (userId == null || token == null) {
    print("⚠️ No se encontró el ID de usuario o el token.");
    return;
  }

  try {
    // **Paso 1: Consultar si el post ya está guardado**
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

      // Buscar si el post ya está en la lista de guardados
      isSaved = checkData['data'].any((post) => post['id'] == postId);
    } else {
      print('⚠️ Error al verificar si el post está guardado: ${checkResponse.statusCode}');
      return;
    }

    // **Paso 2: Determinar si se debe guardar o eliminar**
    String url = isSaved
        ? 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/remove-saved-post'
        : 'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/save-post';

    final body = jsonEncode({
      "app_user_id": userId,
      "post_id": postId.toString(),
    });

    // **Paso 3: Enviar la solicitud correcta**
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

    print("📢 Código de respuesta: ${response.statusCode}");
    print("📢 Respuesta del servidor: ${response.body}");

    if (response.statusCode == 200) {
      setState(() {
        savedPosts[postId] = !isSaved;
      });
      print(isSaved
          ? '🗑️ Post eliminado de marcadores exitosamente.'
          : '✅ Post guardado exitosamente.');
    } else {
      final errorData = json.decode(response.body);
      print('❌ Error al guardar/eliminar el post: ${errorData['message']}');
    }
  } catch (e) {
    print('⚠️ Error en la solicitud HTTP: $e');
  }
}

Future<void> _fetchLikedPosts(String userId, String token) async {
  try {
    final response = await http.get(
      Uri.parse(
          'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/like-posts-app-user?app_user_id=$userId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      setState(() {
        likedPosts = {
          for (var post in data['data']) post['id']: true // Marca los posts con like
        };
      });

      // print('✅ Likes obtenidos correctamente.');
    } else {
      print('⚠️ Error al obtener los likes: ${response.statusCode}');
    }
  } catch (e) {
    print('⚠️ Error en la solicitud de likes: $e');
  }
}


@override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : posts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'No hay posts disponibles.',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _loadAccessToken,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                onRefresh: _loadAccessToken, // Ejecuta la función al hacer swipe hacia abajo
                child: ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    final postId = post['id'];

                    // Validar y procesar meta_key
                    List<String> imageUrls = [];
                    String paragraphText = 'Sin descripción';
                    DateTime? publishedDate;
                    String imageUrl = post['image_url'] ?? '';
                    print('URL IMAGEN: $imageUrl');
                    
                    
                    if (post['meta_key'] != null && post['meta_key'] is String) {
                      try {
                        List<dynamic> metaKeyList = json.decode(post['meta_key']);
                        for (var metaKey in metaKeyList) {
                          if (metaKey['cards'] is List) {
                            for (var card in metaKey['cards']) {
                              if (card['image'] != null) {
                                imageUrls.add(card['image']);
                              }
                            }
                          }
                          if (metaKey['paragraph-text'] != null) {
                            paragraphText = metaKey['paragraph-text']
                                .replaceAll('<p>', '')
                                .replaceAll('</p>', '');
                          }
                        }
                      } catch (e) {
                        print('Error al procesar meta_key: $e');
                      }
                    }


                          if (imageUrls.isNotEmpty) {
                              imageUrl = imageUrls.first;
                            } else {
                              imageUrl = ''; // Para evitar URLs vacías
                            }
                     if (post['published_at'] != null) {
                      publishedDate = DateTime.parse(post['published_at']);
                    }

                    String timeAgoText = publishedDate != null
                    ? timeago.format(publishedDate, locale: 'es')
                    : 'Fecha desconocida';


                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [

    const SizedBox(height: 10),
                            Text(
                              post['title'] ?? 'Sin título',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            
    // 🕒 Fecha con icono de reloj (arriba de la imagen y en la misma línea)
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start, // Alinear a la izquierda
        crossAxisAlignment: CrossAxisAlignment.center, // Centrar verticalmente
        children: [
          Icon(Icons.access_time, size: 18, color: Colors.grey), // Icono de reloj
          const SizedBox(width: 5), // Espaciado entre el icono y el texto
          Text(
            publishedDate != null
                ? timeago.format(publishedDate, locale: 'es') // Formato en español
                : 'Fecha desconocida',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    ),
                             FutureBuilder<Uint8List?>(
  future: imageUrl.isNotEmpty ? fetchImageBytes(imageUrl) : Future.value(null),
  builder: (context, snapshot) {
    print("🖼️ URL IMAGEN: $imageUrl");

    if (imageUrl.isEmpty) {
      print("⚠️ La URL de la imagen está vacía. Mostrando placeholder.");
      return Image.asset(
        'assets/images/placeholder.png',
        height: 250,
        fit: BoxFit.cover,
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    } else if (snapshot.hasError || snapshot.data == null) {
      print("❌ Error al cargar la imagen: $imageUrl");
      return Image.asset(
        'assets/images/placeholder.png', // Imagen de respaldo si falla la carga
        height: 250,
        fit: BoxFit.cover,
      );
    } else {
      return Image.memory(
        snapshot.data!,
        height: 250,
        fit: BoxFit.cover,
      );
    }
  },
),
                            
                            const SizedBox(height: 10),
                            Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Row(
      children: [
        IconButton(
          icon: Icon(
            likedPosts[postId] == true ? Icons.favorite : Icons.favorite_border,
            color: likedPosts[postId] == true ? Colors.red : Colors.black,
          ),
          onPressed: () {
            _toggleLike(postId);
          },
        ),
        GestureDetector(
          onTap: () {
            // Navegar a la pantalla de LikesScreen al tocar el texto "Me gusta"
           Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LikesScreen(postId: postId.toString()), // Convertir a String
            ),
          );
          },
          child: Text(
            '${postLikesCount[postId] ?? 0} Me gusta',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue, // Cambiar color para indicar que es interactivo
            ),
          ),
        ),
      ],
    ),
    IconButton(
      icon: Icon(
        savedPosts[postId] == true ? Icons.bookmark : Icons.bookmark_border,
        color: savedPosts[postId] == true ? Colors.amber : Colors.black,
      ),
      onPressed: () {
        _toggleSave(postId);
      },
    ),
  ],
),
       Html(
  data: paragraphText, // Renderiza el HTML correctamente
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
