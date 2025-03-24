import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LikesScreen extends StatefulWidget {
  final String postId;

  const LikesScreen({Key? key, required this.postId}) : super(key: key);

  @override
  _LikesScreenState createState() => _LikesScreenState();
}

class _LikesScreenState extends State<LikesScreen> {
   final _storage = FlutterSecureStorage();
  List<dynamic> likes = [];
  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    fetchLikes();
  }

 Future<void> fetchLikes() async {
     final token = await _storage.read(key: 'access_token');

  final String apiUrl =
      'https://somos-api-cms.qa.chileatiende.cl/api/mobile-app/likes-post?post_id=${widget.postId}';

  try {
    final response = await http.get(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $token', // Asegúrate de que el token sea correcto
        'Content-Type': 'application/json',
      },
    );

    print('Código de respuesta: ${response.statusCode}');
    print('Respuesta del servidor: ${response.body}'); // 👀 Verifica la estructura de la respuesta

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data.containsKey('data')) { // Cambiado de "likes" a "data"
        setState(() {
          likes = data['data'];  // Usar la clave correcta
          isLoading = false;
          hasError = false;
        });
      } else {
        throw Exception('Clave "data" no encontrada en la respuesta');
      }
    } else {
      throw Exception('Error al cargar los datos, código: ${response.statusCode}');
    }
  } catch (e) {
    print('Error: $e');
    setState(() {
      isLoading = false;
      hasError = true;
    });
  }
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios que dieron Me Gusta')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : hasError
              ? const Center(child: Text('Error al cargar datos'))
              : ListView.builder(
                  itemCount: likes.length,
                  itemBuilder: (context, index) {
                    final user = likes[index]['app_user'];
                    final String name = user['full_name'] ?? 'Usuario Desconocido';
                    final String email = user['email'] ?? 'Correo no disponible';
                    final String? profilePicture = user['profile_picture_url'];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: profilePicture != null
                            ? NetworkImage(profilePicture)
                            : const AssetImage('assets/default_avatar.png') as ImageProvider,
                        radius: 25,
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(email),
                    );
                  },
                ),
    );
  }
}
