import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class SinglePostScreen extends StatelessWidget {
  final Map<String, dynamic> post;

  const SinglePostScreen({Key? key, required this.post}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(post['title'])),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen principal del post
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                post['image'],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    color: Colors.grey[300],
                    child: Center(child: Text("Imagen no disponible")),
                  );
                },
              ),
            ),
            SizedBox(height: 16),

            // Fecha de publicación
            Text(
              "Publicado el: ${post['published_at']}",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            SizedBox(height: 10),

            // Cantidad de "Me gusta" y comentarios
            Row(
              children: [
               
                SizedBox(width: 4),
                Text("${post['likes']} Me gusta"),
                SizedBox(width: 16),
               
              ],
            ),
            SizedBox(height: 16),

            // Contenido del post en HTML
            Html(data: post['content']),
          ],
        ),
      ),
    );
  }
}
